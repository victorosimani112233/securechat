import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets('Chats badge totals messages and updates on other tabs', (
    tester,
  ) async {
    final repository = InMemoryConversationRepository(
      conversations: [
        _conversation('alice', unreadCount: 2),
        _conversation(
          'group',
          unreadCount: 3,
          isGroup: true,
        ).copyWith(isMuted: true, isArchived: true),
        _conversation('manual', unreadCount: 0).copyWith(manuallyUnread: true),
      ],
      messages: {},
    );
    await _pumpApp(tester, repository);
    _expectBadge(tester, 5);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    _expectBadge(tester, 5);

    await repository.markConversationRead('alice');
    await tester.pumpAndSettle();
    _expectBadge(tester, 3);

    await repository.deleteConversation('group');
    await tester.pumpAndSettle();
    _expectBadge(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chats badge retains the exact total above 999', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = InMemoryConversationRepository(
      conversations: [_conversation('alice', unreadCount: 1200)],
      messages: {},
    );
    await _pumpApp(tester, repository);
    _expectBadge(tester, 1200);
    expect(tester.takeException(), isNull);
  });
}

Conversation _conversation(
  String id, {
  required int unreadCount,
  bool isGroup = false,
}) => Conversation(
  id: id,
  peerId: id,
  peerName: id,
  peerPhone: '',
  unreadCount: unreadCount,
  isGroup: isGroup,
);

Future<void> _pumpApp(
  WidgetTester tester,
  ConversationRepository repository,
) async {
  final base = createWidgetTestContainer();
  final container = AppContainer.testing(
    session: base.session,
    conversations: repository,
    crypto: base.crypto,
    signaling: base.signaling,
    chatAccessRuntime: base.chatAccessRuntime,
    callReadinessRuntime: base.callReadinessRuntime,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(SecureChatFlutterApp(container: container));
  await tester.pumpAndSettle();
}

void _expectBadge(WidgetTester tester, int count) {
  final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
  final chats = navigation.destinations.first as NavigationDestination;
  for (final icon in [chats.icon, chats.selectedIcon!]) {
    final badge = icon as Badge;
    expect(badge.isLabelVisible, count > 0);
    expect((badge.label! as Text).data, '$count');
  }
}
