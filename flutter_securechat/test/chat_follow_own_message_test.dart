import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-12 Bulgu 10: yukaridayken gonderen kendi mesajina inmiyor,
/// "en yeni" rozeti kendi mesajlarini sayiyordu.
void main() {
  List<LocalMessage> history(String conversationId) => [
    for (var i = 0; i < 60; i++)
      LocalMessage(
        id: 'h$i',
        conversationId: conversationId,
        senderId: conversationId,
        peerId: conversationId,
        content: 'Eski mesaj $i',
        contentType: MessageContentType.text,
        timestamp: DateTime.now().subtract(Duration(minutes: 120 - i)),
        status: MessageStatus.delivered,
        isOutgoing: false,
      ),
  ];

  Future<(InMemoryConversationRepository, ScrollPosition)> pumpScrolledUp(
    WidgetTester tester,
  ) async {
    final container = createWidgetTestContainer(messagesFor: history);
    final repository =
        container.conversations as InMemoryConversationRepository;
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('chat-message-list'));
    await tester.drag(list, const Offset(0, 2500));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.pixels, lessThan(position.maxScrollExtent - 200));
    return (repository, position);
  }

  testWidgets('sending while scrolled up jumps to the own message', (
    tester,
  ) async {
    final (repository, position) = await pumpScrolledUp(tester);

    unawaited(repository.sendText('peer-ayse', 'Kendi mesajım'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(position.pixels, closeTo(position.maxScrollExtent, 1));
    expect(find.text('Kendi mesajım'), findsOneWidget);
  });
}
