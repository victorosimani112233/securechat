import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/auth/account_recovery_coordinator.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/calls/call_readiness_service.dart';
import 'package:flutter_securechat/src/features/conversations/conversations_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/security/chat_access_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/conversation_repository.dart';
import 'package:flutter_securechat/src/services/crypto_service.dart';
import 'package:flutter_securechat/src/services/signaling_service.dart';
import 'package:flutter_securechat/src/services/identity_recovery_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-13 R3 madde 5: kurtarma e-postasi olmayan mevcut kullanicilar
/// hesaplarini kaybetmeden once uyarilmali.
void main() {
  const banner = ValueKey('conversation-recovery-reminder');

  Future<void> pump(WidgetTester tester, bool? bound) async {
    final container = AppContainer.testing(
      session: createLoggedInTestSession(),
      conversations: InMemoryConversationRepository(
        conversations: [],
        messages: {},
      ),
      crypto: LocalAeadCryptoService(SecretKey(List.filled(32, 3))),
      signaling: InMemorySignalingService(),
      auth: _RecoveryStatusAuth(_FixedRecoveryStatus(bound)),
      callReadinessRuntime: const AppCallReadinessRuntime(
        service: CallReadinessService(
          platform: NotApplicableCallReadinessPlatform(),
        ),
      ),
      chatAccessRuntime: const AppChatAccessRuntime(
        service: ChatAccessService(
          authenticator: AlwaysAllowDeviceOwnerAuthenticator(),
        ),
      ),
    );
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an account without a recovery email sees the reminder', (
    tester,
  ) async {
    await pump(tester, false);
    expect(find.byKey(banner), findsOneWidget);
    expect(
      find.text(
        lookupAppLocalizations(const Locale('tr')).recovery_reminder_banner,
      ),
      findsOneWidget,
    );
  });

  // QA 2026-10-13 T5 madde 3.
  testWidgets('a rejected device identity shows the recovery banner', (
    tester,
  ) async {
    identityRecoveryNeeded.value = true;
    addTearDown(() => identityRecoveryNeeded.value = false);
    await pump(tester, true);
    expect(
      find.byKey(const ValueKey('conversation-identity-recovery')),
      findsOneWidget,
    );
  });

  for (final bound in [true, null]) {
    testWidgets('no reminder when the status is $bound', (tester) async {
      await pump(tester, bound);
      expect(find.byKey(banner), findsNothing);
    });
  }
}

class _RecoveryStatusAuth implements AuthCoordinator {
  _RecoveryStatusAuth(this.recovery);

  @override
  final AccountRecoveryCoordinator recovery;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedRecoveryStatus implements AccountRecoveryCoordinator {
  _FixedRecoveryStatus(this.bound);

  final bool? bound;

  @override
  Future<bool> getEnrollmentStatus() async {
    final value = bound;
    if (value == null) throw const AuthApiException('network');
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
