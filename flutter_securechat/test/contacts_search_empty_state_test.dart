import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/features/contacts/contacts_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/storage/storage_entities.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets(
    'unmatched contacts search shows no results, not permission advice',
    (tester) async {
      final l10n = await _openContacts(tester, [
        for (final number in [100, 102])
          ContactEntity(
            id: 'peer-$number',
            displayName: 'QA$number',
            phoneNumber: '+90532000$number',
            phoneHash: 'test-$number',
            isRegistered: true,
          ),
      ]);
      expect(find.text('QA100'), findsOneWidget);
      expect(find.text('QA102'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'QA101');
      await tester.pumpAndSettle();
      expect(find.text(l10n.conversations_no_results), findsOneWidget);
      expect(find.text(l10n.conversations_no_results_body), findsOneWidget);
      expect(find.text(l10n.no_registered_contacts), findsNothing);
      expect(find.text(l10n.contacts_empty_body), findsNothing);
      expect(find.text('QA100'), findsNothing);
      expect(find.text('QA102'), findsNothing);

      await tester.enterText(find.byType(TextField), 'QA100');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'QA100'), findsOneWidget);
      expect(find.text('QA102'), findsNothing);
      expect(find.text(l10n.conversations_no_results), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('QA100'), findsOneWidget);
      expect(find.text('QA102'), findsOneWidget);
      expect(find.text(l10n.conversations_no_results), findsNothing);
      expect(find.text(l10n.no_registered_contacts), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('contacts without ELÇİM are listed with an invite action', (
    tester,
  ) async {
    final l10n = await _openContacts(
      tester,
      const [
        ContactEntity(
          id: 'peer-100',
          displayName: 'QA100',
          phoneNumber: '+905320000100',
          phoneHash: 'test-100',
          isRegistered: true,
        ),
      ],
      invitable: const [
        DeviceContact(displayName: 'Zeynep', phoneNumber: '+90 533 111 22 33'),
      ],
    );

    expect(find.text(l10n.contacts_on_elcim_section(1)), findsOneWidget);
    expect(find.text(l10n.contacts_invite_section(1)), findsOneWidget);
    expect(find.text('Zeynep'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Zeyn');
    await tester.pumpAndSettle();
    expect(find.text('QA100'), findsNothing);
    expect(find.text('Zeynep'), findsOneWidget);
    expect(find.text(l10n.conversations_no_results), findsNothing);

    await tester.tap(find.text(l10n.contacts_invite_short));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invite-via-sms')), findsOneWidget);
    expect(find.byKey(const Key('invite-via-share')), findsOneWidget);

    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.securechat/native'),
      (call) async {
        calls.add(call);
        // SMS ekrani acilamazsa paylasim ekranina dusulur.
        return call.method == 'shareInviteText';
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.securechat/native'),
        null,
      ),
    );
    await tester.tap(find.byKey(const Key('invite-via-sms')));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), [
      'composeInviteSms',
      'shareInviteText',
    ]);
    final sms = calls.first.arguments as Map;
    expect(sms['phone'], '+90 533 111 22 33');
    expect(sms['body'], contains('ELÇİM'));
    expect(find.text(l10n.invite_copied), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contacts are grouped by letter and the index jumps to them', (
    tester,
  ) async {
    final names = [
      for (final letter in ['A', 'B', 'Ç', 'D', 'E', 'G', 'K', 'M', 'Ş', 'Z'])
        for (var i = 1; i <= 3; i++) '$letter$i kişi',
    ];
    final l10n = await _openContacts(
      tester,
      [
        for (final (index, name) in names.reversed.indexed)
          ContactEntity(
            id: 'peer-$index',
            displayName: name,
            phoneNumber: '+9053200001${index.toString().padLeft(2, '0')}',
            phoneHash: 'test-$index',
            isRegistered: true,
          ),
      ],
      invitable: const [
        DeviceContact(displayName: 'Yusuf', phoneNumber: '+90 533 000 00 02'),
        DeviceContact(displayName: 'Ayla', phoneNumber: '+90 533 000 00 01'),
      ],
    );
    // Davet bolumunun aciklamasi gosterilmez.
    expect(find.text(l10n.contacts_invite_section_body), findsNothing);
    final rail = find.byKey(const Key('contacts-index-rail'));
    expect(rail, findsOneWidget);
    for (final letter in ['A', 'Ç', 'Ş', 'Y', 'Z']) {
      expect(find.byKey(ValueKey('contacts-index-$letter')), findsOneWidget);
    }
    // Liste Turkce alfabe sirasinda: C'den sonra Ç, S'den sonra Ş.
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('A1 kişi'), lessThan(top('B1 kişi')));
    expect(top('B3 kişi'), lessThan(top('Ç1 kişi')));
    expect(top('M3 kişi'), lessThan(top('Ş1 kişi')));
    expect(top('Ş3 kişi'), lessThan(top('Z1 kişi')));
    // Davet listesi ayri ve kendi icinde alfabetik.
    expect(top('Z3 kişi'), lessThan(top('Ayla')));
    expect(top('Ayla'), lessThan(top('Yusuf')));

    final scroll = find.byKey(const Key('contacts-scroll'));
    expect(find.text('Z1 kişi').hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('contacts-index-Z')));
    await tester.pumpAndSettle();
    expect(find.text('Z1 kişi').hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Z1 kişi')).dy,
      lessThan(tester.getCenter(scroll).dy),
    );

    // Arama sirasinda harf cubugu gizlenir.
    await tester.enterText(find.byType(TextField), 'kişi');
    await tester.pumpAndSettle();
    expect(rail, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty contacts directory retains its existing empty state', (
    tester,
  ) async {
    final l10n = await _openContacts(tester, const []);
    expect(find.text(l10n.no_registered_contacts), findsOneWidget);
    expect(find.text(l10n.contacts_empty_body), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'QA101');
    await tester.pumpAndSettle();
    expect(find.text(l10n.no_registered_contacts), findsOneWidget);
    expect(find.text(l10n.contacts_empty_body), findsOneWidget);
    expect(find.text(l10n.conversations_no_results), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<AppLocalizations> _openContacts(
  WidgetTester tester,
  List<ContactEntity> contacts, {
  List<DeviceContact> invitable = const [],
}) async {
  final base = createWidgetTestContainer();
  addTearDown(base.signaling.dispose);
  final container = AppContainer.testing(
    session: base.session,
    conversations: base.conversations,
    crypto: base.crypto,
    signaling: base.signaling,
    contacts: _Contacts(contacts, invitable),
    chatAccessRuntime: base.chatAccessRuntime,
    callReadinessRuntime: base.callReadinessRuntime,
  );
  await tester.pumpWidget(
    AppContainerScope(
      container: container,
      child: MaterialApp(
        theme: SecureChatTheme.light(),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ContactsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(ContactsScreen)));
}

class _Contacts extends Fake implements ContactService {
  _Contacts(this.contacts, [this.invitable = const []]);
  final List<ContactEntity> contacts;
  final List<DeviceContact> invitable;

  @override
  Future<List<DeviceContact>> loadInvitableContacts() async => invitable;

  @override
  Stream<List<ContactEntity>> watchRegistered() => Stream.value(contacts);

  @override
  Future<List<ContactEntity>> importAndDiscover({bool force = false}) async =>
      contacts;
}
