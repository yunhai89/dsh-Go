# Android 审计：Bug、性能与攻击面

日期：2026-11-15
范围：`app/android/` 原生层、Flutter 主路径、发布与更新链路；未覆盖真机 ROM 差异和真实账号。
方法：Android 官方 skills 的 Intent/Permissions 安全清单、ANR 静态风险清单、R8 配置检查；结合代码阅读和可运行测试。

## 结论

没有发现可直接远程利用的高危漏洞。原生边界整体是收紧的：导出组件都有系统签名权限或明确用途，手机桥接同时校验 UID 和每次启动的随机 token，自更新校验 SHA-256 和签名，网络明文只允许 loopback。

本次修复了两处可缩小的攻击面：

1. `MainActivity` 从 `exported=true` 改为 `false`。它没有 intent filter，外部启动没有合法用途；桌面入口仍通过 `activity-alias`（各自 `exported=true`）工作，分享/链接由专用 trampoline 转发。
2. `FileProvider` 的 `external-path` 从整个外部存储收窄到 `Download/DSH-Go/`。该目录之外的文件会先复制到 `cache/artifacts/` 再授予 URI，功能不变。

## 攻击面清单

| 组件/入口 | 现状 | 判断 |
|---|---|---|
| `MainActivity` | 已改为不导出 | 外部应用不能再直接拉起 Flutter 主界面 |
| `LinkTrampolineActivity` | 导出，仅 `dshgo://` 与 `.dshgo`/octet-stream | 需要接收系统文件打开；转发时只加读授权 |
| `ShareActivity` | 导出，`SEND`/`SEND_MULTIPLE` 任意 MIME | 系统分享入口；读取上限、缓存槽位和文件名清理已有 |
| `PhoneA11yService` | 导出，`BIND_ACCESSIBILITY_SERVICE` | 只能由系统绑定 |
| `BackgroundProbeActivity` | 导出，`INJECT_EVENTS` | 系统签名权限保护 |
| `NewChatTileService` | 导出，`BIND_QUICK_SETTINGS_TILE` | 只能由系统绑定 |
| ShizukuProvider | 导出，`INTERACT_ACROSS_USERS_FULL` | Shizuku 官方要求 |
| FileProvider | 不导出，逐 URI 授权 | 已收窄外部根 |
| `PhoneBridge` | abstract unix socket；UID + 每次启动 token；TCP 仅 loopback | 同 UID 的 rootfs 代码可绕过，设计上依赖用户确认 |
| 自更新 | SHA-256 + 同签名校验；安装前再次校验 | 未发现绕过 |
| WebView（伙伴悬浮窗） | JS 开，文件/内容访问关；URL 限本机端口和固定路径；权限请求拒绝 | 桥接仅接收 4 KiB 内的 JSON |
| 网络明文 | 仅 `127.0.0.1`/`localhost` | 其余默认 HTTPS |

## 仍需注意

- **targetSdk 28 是刻意选择**：为了 rootfs 内可执行文件绕过 Android 10+ 的私有目录 exec 限制。代价是无法使用新系统的分区存储、前台服务类型和权限收紧；这不是可以直接“升级 targetSdk”解决的，必须同时改造启动方式。
- `MANAGE_EXTERNAL_STORAGE`、`WRITE_SECURE_SETTINGS`、`REQUEST_INSTALL_PACKAGES` 都是可选能力，默认不授予；保留它们是为了「访问手机文件」、不打扰模式和自更新。上架 Google Play 会被政策限制，本项目不走 Play。
- `LinkTrampolineActivity` 仍接受 `application/octet-stream` 的 `content:`/`file:` 文件并复制到缓存。恶意应用只能让用户看到自己已经能分享的文件，不能把内容回传给发送方；后续可再收紧为 `.dshgo` 扩展名或 `application/vnd.dshgo+json`。
- 伙伴悬浮窗的 JS 桥接只应在受信任的本机页面上启用；当前 URL 校验覆盖 scheme、authority、路径前缀和 userinfo。若未来允许远程模型页，必须重新审计。
- `LaunchThemes.sync` 在主线程写一次 SharedPreferences；量很小，但可在后续改为 `apply()` + 启动时兜底。

## 性能与 ANR

- 大文件 base64/multipart 解码已移到短生命周期 isolate（阈值 256 KiB）；文件窗口、PDF、附件和远程传输块都走这条路。
- 表格只测量每列最长候选文本，并只构建可视列；200 列宽表不再为每个可见行构建 200 个 cell。
- 文件打开时 `content:` URI 的复制移出主线程。
- 聊天流式渲染保留增量修复和缓存；没有引入逐字 blur 的自绘文本。
- 原生 `BroadcastReceiver`/`JobService` 中没有同步网络或大文件 IO；`Thread.sleep` 出现在启动图、配对轮询等后台线程。
- 未发现需要立即修复的 ANR 阻塞点；建议用 `android-profiler` 在真机上抓一次冷启动和长对话 Perfetto，确认首帧和输入延迟。

## 验证

- `flutter analyze`：通过
- `flutter test`（排除字体差导致的 golden）：重点 chat/files/settings 测试通过
- `dart analyze` / `dart test`：`dsh_client` 867 项、`dsh_remote` 499 项通过
- `l10n_merge.py --check`、`guide_sync.py --check`：通过
- APK：release arm64 构建通过（见发布记录）

## 未验证

- 真机安装、桌面 alias 启动、分享/文件打开、Shizuku/ADB、悬浮窗和自更新没有在本环境验证。
- 未跑 Android Lint/Perfetto；本报告是静态审计 + 单元/Widget 测试，不等于设备级结论。
