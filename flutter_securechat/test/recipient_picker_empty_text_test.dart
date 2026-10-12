import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/features/contacts/recipient_picker_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations_tr.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-12 Bulgu 6: kisi secicide bos sonuc "Eslesen sohbet yok"
/// diyordu.
void main() {
  final l10n = AppLocalizationsTr();

  Widget picker({String? emptyText}) => AppContainerScope(
    container: createWidgetTestContainer(),
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RecipientPickerScreen(
        title: 'Yeni grup',
        actionLabel: 'Oluştur',
        emptyText: emptyText,
        choices: Stream.value(const [
          RecipientChoice(id: 'beta', name: 'QaBeta', detail: '+905321000413'),
        ]),
      ),
    ),
  );

  testWidgets('contact picker uses the contact empty text', (tester) async {
    await tester.pumpWidget(picker(emptyText: l10n.recipient_no_results));
    await tester.pumpAndSettle();
    expect(find.text('QaBeta'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(l10n.recipient_no_results), findsOneWidget);
    expect(find.text(l10n.bulk_no_results), findsNothing);
  });

  // QA 2026-10-12 Bulgu 7: tam numara aramasi.
  testWidgets('a full number finds the contact', (tester) async {
    await tester.pumpWidget(picker(emptyText: l10n.recipient_no_results));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0532 100 04 13');
    await tester.pumpAndSettle();
    expect(find.text('QaBeta'), findsOneWidget);
  });

  testWidgets('chat picker keeps its own empty text', (tester) async {
    await tester.pumpWidget(picker());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text(l10n.bulk_no_results), findsOneWidget);
  });
}
