import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/features/auth/auth_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  for (final locale in ['en', 'tr', 'de', 'ar']) {
    testWidgets('existing-account rejection stays inline in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final base = createWidgetTestContainer();
      final auth = _ExistingAccountAuth();
      final container = AppContainer.testing(
        session: base.session,
        conversations: base.conversations,
        crypto: base.crypto,
        signaling: base.signaling,
        chatAccessRuntime: base.chatAccessRuntime,
        callReadinessRuntime: base.callReadinessRuntime,
        auth: auth,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: AppContainerScope(
            container: container,
            child: const AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.login), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Existing User');
      await tester.enterText(fields.at(2), '5551234567');
      final next = find.byKey(const ValueKey('auth-details-continue'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'user@example.com');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final strings = AppLocalizations.of(
        tester.element(find.byType(AuthScreen)),
      );
      expect(find.text(strings.recovery_registration_existing), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-otp')), findsNothing);
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'user@example.com',
      );
      expect(auth.events, ['request', 'verify', 'register']);
      expect(tester.takeException(), isNull);
    });
  }
}

class _ExistingAccountAuth implements AuthCoordinator {
  final events = <String>[];

  @override
  Future<OtpRequestResult> requestOtp(String email) async {
    events.add('request');
    return const OtpRequestResult(OtpRequestStatus.sent);
  }

  @override
  Future<String> verifyOtp(String email, String otp) async {
    events.add('verify');
    expect(otp, '123456');
    return 'verified-grant';
  }

  @override
  Future<void> registerAndLogin({
    required String displayName,
    required String phoneNumber,
    required String registrationToken,
  }) async {
    events.add('register');
    expect(registrationToken, 'verified-grant');
    throw const ExistingAccountLoginRequired();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
