import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/l10n/l10n.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets('archived departed group offers delete and disappears', (
    tester,
  ) async {
    final base = createWidgetTestContainer();
    final repo = InMemoryConversationRepository(
      session: base.session,
      conversations: [
        const Conversation(
          id: 'left',
          peerId: 'left',
          peerName: 'Departed group',
          peerPhone: '',
          isGroup: true,
          isArchived: true,
          groupMembers: ['peer'],
          groupAdmins: ['me'],
        ),
      ],
      messages: {},
    );
    final container = AppContainer.testing(
      session: base.session,
      conversations: repo,
      crypto: base.crypto,
      signaling: base.signaling,
      chatAccessRuntime: base.chatAccessRuntime,
      callReadinessRuntime: base.callReadinessRuntime,
    );
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('conversation-archive-banner')));
    await tester.pumpAndSettle();
    final strings = tester.element(find.text('Departed group')).l10n;
    await tester.longPress(find.text('Departed group'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(strings.conv_delete_chat));
    await tester.tap(find.text(strings.conv_delete_chat));
    await tester.pumpAndSettle();
    expect(find.text(strings.clear_group_history_body), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, strings.conv_delete));
    await tester.pumpAndSettle();
    expect(find.text('Departed group'), findsNothing);
    expect(await repo.watchConversations().first, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final confirm in [false, true]) {
    testWidgets(
      'group clear ${confirm ? 'keeps membership' : 'can be cancelled'}',
      (tester) async {
        final container = createWidgetTestContainer();
        final before =
            (await container.conversations.watchConversations().first)
                .singleWhere((c) => c.id == 'group-ops');
        await tester.pumpWidget(SecureChatFlutterApp(container: container));
        await tester.pumpAndSettle();
        final strings = tester.element(find.text('Operasyon Ekibi').first).l10n;
        await tester.longPress(find.text('Operasyon Ekibi').first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(strings.clear_chat));
        await tester.tap(find.text(strings.clear_chat));
        await tester.pumpAndSettle();
        expect(find.text(strings.clear_group_history_body), findsOneWidget);
        await tester.tap(
          find.widgetWithText(
            confirm ? FilledButton : TextButton,
            confirm ? strings.conv_delete : strings.cancel,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Operasyon Ekibi'), findsOneWidget);
        final after = (await container.conversations.watchConversations().first)
            .singleWhere((c) => c.id == 'group-ops');
        expect(after.isGroup, isTrue);
        expect(after.groupMembers, before.groupMembers);
        if (confirm) {
          expect(after.lastMessage, isNull);
          expect(after.unreadCount, 0);
        } else {
          expect(after.lastMessage, before.lastMessage);
          expect(after.unreadCount, before.unreadCount);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
