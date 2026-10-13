import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/crypto/vodozemac/olm_pre_key_publisher.dart';
import 'package:flutter_securechat/src/features/auth/auth_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
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
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
