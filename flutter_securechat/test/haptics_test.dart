import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/widgets/haptics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('haptic adapter maps light and long-press feedback', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await SecureChatHaptics.light();
    await SecureChatHaptics.longPress();

    expect(calls.map((call) => call.arguments), [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  test('Kotlin haptic interaction points are wired in Flutter', () {
    final chat = File(
      'lib/src/features/chat/chat_screen.dart',
    ).readAsStringSync();
    final conversations = File(
      'lib/src/features/conversations/conversations_screen.dart',
    ).readAsStringSync();
    final calls = File(
      'lib/src/features/calls/call_screen.dart',
    ).readAsStringSync();

    expect(chat, contains('SecureChatHaptics.light()'));
    expect(chat, contains('SecureChatHaptics.longPress()'));
    expect(conversations, contains('SecureChatHaptics.light()'));
    expect(conversations, contains('DismissDirection.startToEnd: .5'));
    expect(calls, contains('SecureChatHaptics.longPress()'));
  });
}
