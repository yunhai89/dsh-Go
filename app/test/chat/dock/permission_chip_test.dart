// 「完全权限」 on a phone: it rides the bar the dock already shows (todo, goal,
// the run's strip) instead of taking a row of its own above the composer.

import 'package:dsh_app/state/chat_state.dart';
import 'package:dsh_app/state/session_modes.dart';
import 'package:dsh_app/ui/chat/chat_screen.dart';
import 'package:dsh_app/ui/chat/dock/todo_bar.dart';
import 'package:dsh_app/ui/chat/widgets/permission_pill.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';

void main() {
  testWidgets('rides the todo bar instead of a row of its own', (tester) async {
    SharedPreferences.setMockInitialValues({});
    usePhoneView(tester);
    final harness = ChatHarness(
      session: 's1',
      states: {
        's1': const ChatState(
          loading: false,
          todos: [TodoItem('找到重复提交的原因', 'completed'), TodoItem('补一个连点测试', 'completed')],
        ),
      },
      extra: [sessionModesProvider.overrideWith((ref, id) => const SessionModes(preset: 'danger-full-access'))],
    );
    await tester.pumpWidget(testApp(const ChatScreen(), overrides: harness.overrides));
    await pumpFrames(tester, 10);

    // The chip, not the standalone pill: no row above the composer.
    expect(find.byType(PermissionPill), findsNothing);
    final chip = find.byType(StripRiskChip);
    expect(chip, findsOneWidget);

    // The same row as the todo bar, to its right.
    final bar = tester.getRect(find.byType(TodoBar));
    final rect = tester.getRect(chip);
    expect(rect.top, moreOrLessEquals(bar.top, epsilon: 1));
    expect(rect.left, greaterThanOrEqualTo(bar.right));
  });

  testWidgets('falls back to the capsule row with no dock bar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    usePhoneView(tester);
    final harness = ChatHarness(
      session: 's1',
      states: {'s1': const ChatState(loading: false)},
      extra: [sessionModesProvider.overrideWith((ref, id) => const SessionModes(preset: 'danger-full-access'))],
    );
    await tester.pumpWidget(testApp(const ChatScreen(), overrides: harness.overrides));
    await pumpFrames(tester, 10);

    expect(find.byType(StripRiskChip), findsNothing);
    expect(find.byType(PermissionPill), findsOneWidget);
  });
}
