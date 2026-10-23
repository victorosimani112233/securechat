import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/auth/account_recovery_coordinator.dart';
import 'package:flutter_securechat/src/auth/registration_lock.dart';
import 'package:flutter_securechat/src/features/settings/registration_lock_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  test(
    'PIN proofs are bound to the account and never contain the PIN',
    () async {
      expect(validRegistrationLockPin('12345'), isFalse);
      expect(validRegistrationLockPin('123456'), isTrue);
      expect(validRegistrationLockPin('12345a'), isFalse);
      final a = await registrationLockProof(pin: '123456', userId: 'user-a');
      expect(a, await registrationLockProof(pin: '123456', userId: 'user-a'));
      expect(a, isNot(await registrationLockProof(pin: '123456', userId: 'b')));
      expect(a, isNot(contains('123456')));
      await expectLater(
        registrationLockProof(pin: '12', userId: 'user-a'),
        throwsArgumentError,
      );
    },
  );

  Future<AppLocalizations> pump(WidgetTester tester, _Settings settings) async {
    await tester.pumpWidget(
      AppContainerScope(
        container: createWidgetTestContainer(),
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RegistrationLockScreen(settings: settings),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(RegistrationLockScreen)),
    );
  }

  testWidgets('turning the lock on asks for the PIN twice', (tester) async {
    final settings = _Settings(enabled: false);
    final l10n = await pump(tester, settings);
    expect(find.text(l10n.registration_lock_off), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('registration-lock-pin')),
      '123456',
    );
    await tester.enterText(
      find.byKey(const ValueKey('registration-lock-pin-repeat')),
      '654321',
    );
    await tester.tap(find.byKey(const ValueKey('registration-lock-enable')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.registration_lock_pin_mismatch), findsOneWidget);
    expect(settings.enabledWith, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('registration-lock-pin-repeat')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('registration-lock-enable')));
    await tester.pumpAndSettle();
    expect(settings.enabledWith, '123456');
    expect(find.text(l10n.registration_lock_on), findsOneWidget);
    expect(find.byKey(const ValueKey('registration-lock-disable')), findsOne);
  });

  testWidgets('turning the lock off asks for confirmation', (tester) async {
    final settings = _Settings(enabled: true);
    final l10n = await pump(tester, settings);
    await tester.tap(find.byKey(const ValueKey('registration-lock-disable')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.registration_lock_disable_confirm), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('registration-lock-disable-confirm')),
    );
    await tester.pumpAndSettle();
    expect(settings.disabled, isTrue);
    expect(find.text(l10n.registration_lock_off), findsOneWidget);
  });
}

class _Settings implements RegistrationLockSettings {
  _Settings({required this.enabled});
  bool enabled;
  String? enabledWith;
  bool disabled = false;

  @override
  Future<bool> registrationLockEnabled() async => enabled;

  @override
  Future<void> enableRegistrationLock(String pin) async {
    enabledWith = pin;
    enabled = true;
  }

  @override
  Future<void> disableRegistrationLock() async {
    disabled = true;
    enabled = false;
  }
}
