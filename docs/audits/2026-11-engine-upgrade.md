# 本地引擎升级建议（2026-11）

当前基线：DSH `0.2.2-rc.1`、Node `24.22.1`、Ubuntu Base `26.04.1`、proot `5.1.107.102`、运行时 revision `r16`。

## 优先级 1：先修网络，不换引擎

opencode/Cloudflare 的 `TRANSPORT Connection error.: AggregateError (ETIMEDOUT)` 已在 Node 24 上复现：默认 `autoSelectFamilyAttemptTimeout` 是 250 ms，而到 `opencode.ai` 的 TCP 握手经常在 190–300 ms；默认 8 次请求中会出现 `AggregateError`，改成 5000 ms 后 8/8 成功。

建议把 `--network-family-autoselection-attempt-timeout=5000` 加到本机和 SSH 主机的 `NODE_OPTIONS`：

- 本机：在 `DirectLaunch.prootNodeOptions` 里追加，保留用户已有的 heap / `--dns-result-order=ipv4first`。
- SSH 主机：在 `RemoteDshBootstrap` 的启动脚本里追加，使用 `${NODE_OPTIONS:+$NODE_OPTIONS }...`，不要覆盖用户值；重启 `dsh web` 后生效。
- 不建议 `--no-network-family-autoselection`：它会去掉 IPv6→IPv4 回退，localhost MCP 会变成 `ECONNREFUSED`。

这是当前收益最高、风险最低的一项，应先于任何 DSH/Ubuntu 升级。

## 优先级 2：DSH 0.2.2-rc.3 暂不升级

- npm `latest` 仍是 `0.2.2-rc.1`，也就是当前版本；rc.3 在 `next` 通道。
- rc.3 把 5 个客户端 bundle 改成压缩单行，现有 5 个 UI 补丁（移动端回车、输入触发恢复、预设保存、搜索 key 写回、provider discovery client）无法按行应用。
- mcp-client 重构，`phone-caller` / `phone-run-end` 需要重写补丁，不是换行号能解决。
- 结论：等 rc.3 转正或专门排期移植；不要为了版本号把补丁丢掉。

## 优先级 3：降低 proot 常驻成本

1. **direct-glibc 启动优先**：兼容设备上让 DSH 主进程直接使用 rootfs 的 ld.so 启动，bash/git/python/apt 仍走 proot。已有 `DirectLaunch` 和设置开关，建议默认开启并在失败时回退 proot（保留现有安全模式）。
2. **保持引擎常驻**：避免每次回前台重启 Node；现有 `DshService` + mux 复用已做了一部分，继续用缓存端点跳过远端启动探测。
3. **分层运行时**：启用 `RUNTIME_LAYERS=1`（base + engine），让 DSH/桥接更新只下载 engine 层，避免每次 150 MB rootfs。
4. **冷启动测量**：用 Perfetto/Android profiler 记录「点图标 → 首帧」「发消息 → 首个 token」，先量化再改；当前文件解码和表格已经移出 UI isolate，下一瓶颈更可能在 proot 路径翻译。

## 优先级 4：Ubuntu Base（已升 26.04.1，r16）

- 2026-11 已升到 26.04.1「Resolute Raccoon」（glibc 2.43），base tarball 与 sha256 钉在 `runtime/build-runtime.sh`，依赖锁在 `runtime/locks/ubuntu-resolute-<arch>.json`。
- **换 base 会改 `baseId`**：已装 24.04 运行时的设备不能原地升级，App 会要求「重置引擎」一次（`/root` 保留）。
- 26.04 的 coreutils 换成了 rust-coreutils：`/usr/bin/coreutils` 是一个多调用二进制，`usr/lib/cargo/bin/coreutils/*` 全是指向它的硬链接。`rtbuild.py` 把整棵硬链接树按拷贝展开会多出约 1 GB（rootfs 从 159 MB 涨到 505 MB），现在这类硬链接改写成符号链接，rootfs 回到 159 MB。
- 只有 9 个无关的悬空链接（systemd unit、`pager -> more`），systemd 本就不在运行时里。

## 优先级 5：网络与代理产品化

- 给 SSH 主机增加可选的 `HTTPS_PROXY` / `HTTP_PROXY` 字段，写入启动环境并提示重启；比让用户手改 `~/.dsh/.env` 更可靠。
- 在错误详情里保留当前提示，并增加「主机网络检查」：从主机请求一次 provider 根路径，区分 DNS、连接超时、TLS 和 HTTP 错误。
- 对 TRANSPORT 错误记录脱敏后的 provider host 和连接阶段，不记录 token/URL query。

## 不建议现在做

- 直接追 DSH rc.3：补丁与客户端 bundle 成本高，收益不确定。
- 升级 targetSdk：会破坏 rootfs 内可执行文件路径，必须和启动方式一起改。
- 全局替换 proot：Termux 生态和 l2s 兼容仍是当前最稳的路径。
