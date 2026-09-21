import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_info_screen.dart';
import 'package:flutter_securechat/src/features/groups/group_info_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets('contact info message result reveals an older chat message', (
    tester,
  ) async {
    final now = DateTime.now();
    final container = createWidgetTestContainer(
      messagesFor: (id) => List.generate(
        40,
        (index) => LocalMessage(
          id: 'history-$index',
          conversationId: id,
          senderId: 'me',
          peerId: id,
          content: 'History message $index',
          contentType: MessageContentType.text,
          timestamp: now.subtract(Duration(minutes: 40 - index)),
          status: MessageStatus.delivered,
          isOutgoing: true,
        ),
      ),
    );
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayse Demir').first);
    await tester.pumpAndSettle();
    expect(find.text('History message 0').hitTestable(), findsNothing);
    await tester.tap(find.text('Ayse Demir'));
    await tester.pumpAndSettle();

    Navigator.of(
      tester.element(find.byType(ChatInfoScreen)),
    ).pop(const ChatInfoResult.focusMessage('history-0'));
    await tester.pumpAndSettle();
    expect(find.text('History message 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });

  for (final isGroup in [false, true]) {
    for (final useMenu in [false, true]) {
      testWidgets('${isGroup ? 'group' : 'contact'} info opens from '
          '${useMenu ? 'overflow menu' : 'chat header'} and returns to chat', (
        tester,
      ) async {
        await tester.pumpWidget(
          SecureChatFlutterApp(container: createWidgetTestContainer()),
        );
        await tester.pumpAndSettle();
        final name = isGroup ? 'Operasyon Ekibi' : 'Ayse Demir';
        final id = isGroup ? 'group-ops' : 'peer-ayse';
        await tester.tap(find.text(name).first);
        await tester.pumpAndSettle();

        if (useMenu) {
          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuItem<String> &&
                  widget.value == (isGroup ? 'group_info' : 'chat_info'),
            ),
          );
        } else {
          await tester.tap(find.text(name));
        }
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final page = find.byType(isGroup ? GroupInfoScreen : ChatInfoScreen);
        expect(page, findsOneWidget);
        final context = tester.element(page);
        final settings = ModalRoute.of(context)!.settings;
        expect(settings.name, isGroup ? '/group-info' : '/chat-info');
        expect((settings.arguments as Conversation).id, id);

        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        expect(page, findsNothing);
        expect(find.byKey(const ValueKey('chat-message-list')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      '${isGroup ? 'group' : 'contact'} info lock result closes chat access',
      (tester) async {
        await tester.pumpWidget(
          SecureChatFlutterApp(container: createWidgetTestContainer()),
        );
        await tester.pumpAndSettle();
        final name = isGroup ? 'Operasyon Ekibi' : 'Ayse Demir';
        await tester.tap(find.text(name).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        if (isGroup) {
          Navigator.of(tester.element(find.byType(GroupInfoScreen))).pop(true);
        } else {
          Navigator.of(
            tester.element(find.byType(ChatInfoScreen)),
          ).pop(const ChatInfoResult.lockEnabled());
        }
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat-unlock-action')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('chat-message-list')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
