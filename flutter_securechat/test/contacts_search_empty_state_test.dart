import 'package:flutter/material.dart';
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
  List<ContactEntity> contacts,
) async {
  final base = createWidgetTestContainer();
  addTearDown(base.signaling.dispose);
  final container = AppContainer.testing(
    session: base.session,
    conversations: base.conversations,
    crypto: base.crypto,
    signaling: base.signaling,
    contacts: _Contacts(contacts),
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
  _Contacts(this.contacts);
  final List<ContactEntity> contacts;

  @override
  Stream<List<ContactEntity>> watchRegistered() => Stream.value(contacts);

  @override
  Future<List<ContactEntity>> importAndDiscover() async => contacts;
}
