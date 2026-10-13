import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_publisher.dart';
import 'package:flutter_securechat/src/features/auth/auth_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_securechat/src/settings/account_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-12 R1: sunucu oturumu reddettiginde uygulama sohbet
/// listesinde kaliyor, yalniz kucuk bir baglanti uyarisi gosteriyordu.
void main() {
  AppContainer containerWith(AuthCoordinator? auth) {
    final base = createWidgetTestContainer();
    return AppContainer.testing(
      session: base.session,
      conversations: base.conversations,
      crypto: base.crypto,
      signaling: base.signaling,
      chatAccessRuntime: base.chatAccessRuntime,
      callReadinessRuntime: base.callReadinessRuntime,
      auth: auth,
    );
  }

  testWidgets('a rejected refresh returns the app to login with a notice', (
    tester,
  ) async {
    final base = createWidgetTestContainer();
    final api = _RejectingRefreshApi();
    final auth = AuthCoordinator(
      api: api,
      session: base.session,
      olmPreKeys: _NoRecoveryIdentity(),
      signaling: base.signaling,
      signalingUrl: 'wss://example.invalid',
    );
    final container = AppContainer.testing(
      session: base.session,
      conversations: base.conversations,
      crypto: base.crypto,
      signaling: base.signaling,
      chatAccessRuntime: base.chatAccessRuntime,
      callReadinessRuntime: base.callReadinessRuntime,
      auth: auth,
    );
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsNothing);
    final userId = base.session.userId;

    await tester.runAsync(auth.refreshAccessToken);
    await tester.pumpAndSettle();

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-session-expired')), findsOneWidget);
    expect(base.session.userId, userId);
    // Geri tusu eski sohbet listesine donmemeli.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
    expect(api.refreshCalls, 1);
  });

  for (final expired in [true, false]) {
    testWidgets('login screen notice is ${expired ? 'shown' : 'hidden'}', (
      tester,
    ) async {
      final container = containerWith(null);
      if (expired) container.session.expireCredentials();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppContainerScope(
            container: container,
            child: const AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Oturumun sona erdi'),
        expired ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  _startOverTests();
  _deviceAccountHintTest();
}

// QA 2026-10-13, B telefonu: oturumu sona ermis cihazda yeni kayit, e-posta
// kodundan sonra "hesap mevcut" ile reddediliyordu; eski hesaba da donulemiyordu.
void _startOverTests() {
  Future<(AppContainer, _RecordingAccountData)> pumpExpired(
    WidgetTester tester,
  ) async {
    final base = createWidgetTestContainer();
    base.session.expireCredentials();
    final accountData = _RecordingAccountData(base.session);
    final container = AppContainer.testing(
      session: base.session,
      conversations: base.conversations,
      crypto: base.crypto,
      signaling: base.signaling,
      chatAccessRuntime: base.chatAccessRuntime,
      callReadinessRuntime: base.callReadinessRuntime,
      accountDataRuntime: AppAccountDataRuntime(service: accountData),
    );
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppContainerScope(
          container: container,
          child: const AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, accountData);
  }

  testWidgets('start over asks first, then removes the old account', (
    tester,
  ) async {
    final (container, accountData) = await pumpExpired(tester);
    final startOver = find.byKey(const ValueKey('auth-session-start-over'));
    expect(startOver, findsOneWidget);

    await tester.tap(startOver);
    await tester.pumpAndSettle();
    await tester.tap(find.text('İptal').last);
    await tester.pumpAndSettle();
    expect(accountData.deletions, 0);
    expect(container.session.userId, isNotNull);

    await tester.tap(startOver);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('auth-session-start-over-confirm')),
    );
    await tester.pumpAndSettle();
    expect(accountData.deletions, 1);
    expect(container.session.userId, isNull);
    expect(find.byKey(const ValueKey('auth-session-expired')), findsNothing);
  });

  testWidgets('registering on an expired device clears it before the code', (
    tester,
  ) async {
    final (container, accountData) = await pumpExpired(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Yeni Kisi');
    await tester.enterText(fields.at(2), '5321000416');
    final next = find.byKey(const ValueKey('auth-details-continue'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();

    // E-posta adimina gecmeden once sorulur.
    expect(find.byKey(const ValueKey('auth-email')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('auth-session-start-over-confirm')),
    );
    await tester.pumpAndSettle();

    expect(accountData.deletions, 1);
    expect(container.session.userId, isNull);
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _deviceAccountHintTest() {
  testWidgets('a device account without a start-over path is named early', (
    tester,
  ) async {
    final base = createWidgetTestContainer();
    // Yedekten geri yuklenmis profil: kimlik var, token yok, oturum
    // "sona erdi" degil.
    base.session.accessToken = null;
    base.session.refreshToken = null;
    final container = AppContainer.testing(
      session: base.session,
      conversations: base.conversations,
      crypto: base.crypto,
      signaling: base.signaling,
      chatAccessRuntime: base.chatAccessRuntime,
      callReadinessRuntime: base.callReadinessRuntime,
    );
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppContainerScope(
          container: container,
          child: const AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Yeni Kisi');
    await tester.enterText(fields.at(2), '5321000416');
    final next = find.byKey(const ValueKey('auth-details-continue'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();

    final strings = AppLocalizations.of(
      tester.element(find.byType(AuthScreen)),
    );
    expect(find.text(strings.registration_device_has_account), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-email')), findsNothing);
  });
}

class _RecordingAccountData implements AccountDataService {
  _RecordingAccountData(this.session);

  final SessionStore session;
  int deletions = 0;

  @override
  Future<void> deleteLocalData() async {
    deletions++;
    await session.clearAndPersist();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RejectingRefreshApi extends AuthApi {
  _RejectingRefreshApi() : super(baseUrl: 'http://unused.invalid');

  int refreshCalls = 0;

  @override
  Future<TokenPair> refresh(String refreshToken) async {
    refreshCalls++;
    throw const AuthApiException('rejected', statusCode: 401);
  }
}

class _NoRecoveryIdentity implements RecoveryIdentity {
  // Cihazda kimlik yok: cihaz anahtari yolu (QA R3 madde 3) denenmez.
  @override
  Future<String?> recoverySigningPublicKey() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
