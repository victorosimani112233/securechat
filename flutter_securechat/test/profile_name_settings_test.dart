import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/features/settings/settings_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// Cihaz testi 2026-10-13: profil adi hicbir yerden degistirilemiyordu;
/// e-postayla kurtarilan hesap uygulama adiyla ("Elcim") kaliyordu.
void main() {
  testWidgets('the profile name can be changed from settings', (tester) async {
    final container = createWidgetTestContainer();
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-profile-name')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-profile-name-field')),
      '  Yeni   Ad ',
    );
    await tester.tap(find.byKey(const ValueKey('settings-profile-name-save')));
    await tester.pumpAndSettle();

    expect(container.session.displayName, 'Yeni Ad');
    expect(find.text('Yeni Ad'), findsOneWidget);
  });

  testWidgets('an empty name asks the user to add one', (tester) async {
    final container = createWidgetTestContainer();
    container.session.displayName = '';
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(lookupAppLocalizations(const Locale('tr')).profile_name_add),
      findsOneWidget,
    );
  });
}
