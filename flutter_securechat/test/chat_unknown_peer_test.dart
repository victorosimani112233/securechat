import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations_tr.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-12 Bulgu 3: rehberde olmayan gonderenin sohbeti.
void main() {
  final l10n = AppLocalizationsTr();
  const uuid = '3b3663e9-3046-4ba9-acd6-dfdaf3fa510c';
  const conversation = Conversation(
    id: uuid,
    peerId: uuid,
    peerName: uuid,
    peerPhone: '',
  );

  Future<void> pump(WidgetTester tester, {required bool known}) async {
    final base = createWidgetTestContainer();
    final container = AppContainer.testing(
      session: base.session,
      conversations: InMemoryConversationRepository(
        conversations: [conversation],
        messages: {conversation.id: <LocalMessage>[]},
      ),
      crypto: base.crypto,
      signaling: base.signaling,
      chatAccessRuntime: base.chatAccessRuntime,
      callReadinessRuntime: base.callReadinessRuntime,
      contacts: _Contacts(known),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            settings: const RouteSettings(arguments: conversation),
            builder: (_) => const ChatScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a stranger chat shows no id and offers to block', (
    tester,
  ) async {
    await pump(tester, known: false);

    expect(find.text(uuid), findsNothing);
    expect(find.text(l10n.unknown_contact), findsWidgets);
    final banner = find.byKey(const ValueKey('chat-unknown-banner'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.text(l10n.safety_block)),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: banner, matching: find.text(l10n.action_close)),
    );
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  testWidgets('a known contact gets no stranger banner', (tester) async {
    await pump(tester, known: true);
    expect(find.byKey(const ValueKey('chat-unknown-banner')), findsNothing);
  });
}

class _Contacts implements ContactService {
  _Contacts(this.known);
  final bool known;

  @override
  Future<bool> isKnownContact(String userId) async => known;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
