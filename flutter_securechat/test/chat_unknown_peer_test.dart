import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/core/models.dart';
import 'package:flutter_securechat/src/features/chat/chat_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations_tr.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
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

  Future<_Contacts> pump(
    WidgetTester tester, {
    required bool known,
    Conversation conversation = conversation,
  }) async {
    final contacts = _Contacts(known);
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
      contacts: contacts,
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
            settings: RouteSettings(arguments: conversation),
            builder: (_) => const ChatScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return contacts;
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

    // Numara paylasilmamis: rehbere eklenecek bir sey yok, nedeni yazar.
    expect(find.byKey(const ValueKey('chat-unknown-add')), findsNothing);
    expect(find.text(l10n.not_in_contacts_no_number), findsOneWidget);
    // Ad bilinmiyorsa kart basligi tekrarlamaz.
    expect(
      find.descendant(of: banner, matching: find.text(l10n.unknown_contact)),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('chat-unknown-dismiss')));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  // Kullanici istegi 2026-10-14: kart rehbere ekleme secenegi sunar.
  testWidgets('a stranger with a shared number can be added to contacts', (
    tester,
  ) async {
    final contacts = await pump(
      tester,
      known: false,
      conversation: const Conversation(
        id: uuid,
        peerId: uuid,
        peerName: '~Ayse',
        peerPhone: '+905551112233',
      ),
    );
    final banner = find.byKey(const ValueKey('chat-unknown-banner'));
    expect(
      find.descendant(of: banner, matching: find.text('~Ayse · +905551112233')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('chat-unknown-add')));
    await tester.pumpAndSettle();
    expect(contacts.opened, [('+905551112233', '~Ayse')]);
    expect(banner, findsOneWidget);

    // Sistem kisi ekranindan donus: rehber eslenir, kart kalkar.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(contacts.imports, 1);
    expect(banner, findsNothing);
  });

  testWidgets('a known contact gets no stranger banner', (tester) async {
    await pump(tester, known: true);
    expect(find.byKey(const ValueKey('chat-unknown-banner')), findsNothing);
  });
}

class _Contacts implements ContactService {
  _Contacts(this.known);
  bool known;
  int imports = 0;
  final opened = <(String, String)>[];

  @override
  Future<bool> openAddToDeviceContacts({
    required String phone,
    String sharedName = '',
  }) async {
    opened.add((phone, sharedName));
    return true;
  }

  @override
  Future<List<ContactEntity>> importAndDiscover() async {
    imports++;
    known = true;
    return const [];
  }

  @override
  Future<bool> isKnownContact(String userId) async => known;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
