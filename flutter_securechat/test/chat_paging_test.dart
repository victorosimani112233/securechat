import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

const _peer = 'peer-ayse';

/// Uzun sohbet sayfa sayfa acilir; eski sayfa eklenince ekran zıplamaz.
void main() {
  final start = DateTime(2026, 10, 20, 9);

  List<LocalMessage> history({String? replyTo, String? pinned}) => [
    for (var i = 0; i < 250; i++)
      LocalMessage(
        id: 'h$i',
        conversationId: _peer,
        senderId: _peer,
        peerId: _peer,
        content: 'Eski mesaj $i',
        contentType: MessageContentType.text,
        timestamp: start.add(Duration(minutes: i)),
        status: MessageStatus.delivered,
        isOutgoing: false,
        replyToId: i == 249 ? replyTo : null,
        isPinned: 'h$i' == pinned,
        pinnedAt: 'h$i' == pinned ? start : null,
      ),
  ];

  Future<_PagingRepository> pump(
    WidgetTester tester, {
    List<LocalMessage>? messages,
    String? initialMessageId,
  }) async {
    final base = createWidgetTestContainer();
    final repo = _PagingRepository(
      conversations: [
        const Conversation(
          id: _peer,
          peerId: _peer,
          peerName: 'Ayse Demir',
          peerPhone: '',
        ),
      ],
      messages: {_peer: messages ?? history()},
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AppContainerScope(
        container: AppContainer.testing(
          session: base.session,
          conversations: repo,
          crypto: base.crypto,
          signaling: base.signaling,
          chatAccessRuntime: base.chatAccessRuntime,
          callReadinessRuntime: base.callReadinessRuntime,
        ),
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(initialMessageId: initialMessageId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('only the newest page is loaded when the chat opens', (
    tester,
  ) async {
    final repo = await pump(tester);
    expect(repo.limits, [100]);
    expect(find.text('Eski mesaj 249'), findsOneWidget);
    // Ilk sayfa doluyken sifreleme notu sohbetin gercek basinda kalir.
    expect(find.text('Mesajlar uçtan uca şifrelenmiştir.'), findsNothing);
  });

  testWidgets('an older page appears above without moving the screen', (
    tester,
  ) async {
    final repo = await pump(tester);
    final list = find.byKey(const ValueKey('chat-message-list'));
    // Ilk sayfanin en eskisine kadar yukari kaydir.
    await tester.scrollUntilVisible(
      find.text('Eski mesaj 150'),
      -300,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('Eski mesaj 151')).dy;
    // Yaklasinca bir sayfa daha istenmis olmali.
    expect(repo.limits, [100, 200]);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Eski mesaj 151')).dy, before);
    // Eski sayfa yukari dogru eklendi.
    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Eski mesaj 145'), findsOneWidget);
  });

  testWidgets('a reply and a pin outside the page are still shown', (
    tester,
  ) async {
    await pump(
      tester,
      messages: history(replyTo: 'h10', pinned: 'h5'),
    );
    // Yanit alintisi sayfa disindaki mesaji gosterir.
    expect(find.text('Eski mesaj 10'), findsOneWidget);
    // Sabitlenmis mesajin bandi da.
    expect(find.text('Eski mesaj 5'), findsOneWidget);
  });

  testWidgets('opening a message outside the page loads until it is shown', (
    tester,
  ) async {
    final repo = await pump(tester, initialMessageId: 'h3');
    expect(repo.limits.last, greaterThanOrEqualTo(300));
    expect(find.text('Eski mesaj 3'), findsOneWidget);
  });
}

class _PagingRepository extends InMemoryConversationRepository {
  _PagingRepository({required super.conversations, required super.messages});

  final limits = <int>[];

  @override
  Stream<List<LocalMessage>> watchMessages(
    String conversationId, {
    int? limit,
  }) {
    if (limit != null) limits.add(limit);
    return super.watchMessages(conversationId, limit: limit);
  }
}
