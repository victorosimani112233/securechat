import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/auth/account_recovery_coordinator.dart';
import 'package:flutter_securechat/src/auth/auth_api.dart';
import 'package:flutter_securechat/src/auth/auth_coordinator.dart';
import 'package:flutter_securechat/src/features/auth/auth_screen.dart';
import 'package:flutter_securechat/src/features/auth/recovery_enrollment_screen.dart';
import 'package:flutter_securechat/src/features/auth/recovery_login_screen.dart';
import 'package:flutter_securechat/src/features/settings/settings_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        routes: {'/': (_) => const Scaffold(body: Text('signed-in-home'))},
        initialRoute: '/recovery',
        onGenerateRoute: (settings) =>
            MaterialPageRoute<void>(settings: settings, builder: (_) => screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final keyed = find.byKey(ValueKey(key));
    final finder = key == 'recovery-accept'
        ? find.descendant(of: keyed, matching: find.byType(Checkbox))
        : keyed;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> request(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('recovery-email')),
      'person@example.com',
    );
    await tapKey(tester, 'recovery-submit');
  }

  Future<void> verify(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('recovery-code')),
      '123456',
    );
    await tapKey(tester, 'recovery-submit');
  }

  testWidgets('login validates email and six digits before calling service', (
    tester,
  ) async {
    final recovery = _Recovery();
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await tapKey(tester, 'recovery-submit');
    expect(recovery.requests, 0);
    await request(tester);
    expect(recovery.requests, 1);
    expect(find.textContaining('If this request is eligible'), findsOneWidget);
    expect(find.text('person@example.com'), findsNothing);
    await tester.enterText(find.byType(TextField), '12345');
    await tapKey(tester, 'recovery-submit');
    expect(recovery.verifications, 0);
    await verify(tester);
    expect(recovery.verifications, 1);
    expect(recovery.completions, 0);
    expect(
      find.textContaining('This login creates a new Signal identity'),
      findsOneWidget,
    );
    expect(find.textContaining('Previous account sessions'), findsOneWidget);
    expect(find.textContaining('existing backup'), findsOneWidget);
    expect(find.textContaining('private-user-id'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('recovery-complete')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'recovery-accept');
    await tapKey(tester, 'recovery-complete');
    expect(recovery.completions, 1);
    expect(recovery.acceptedReplacement, isTrue);
    expect(find.text('signed-in-home'), findsOneWidget);
  });

  testWidgets('completion failure retries only the pending login', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..completionError = const AuthApiException.network();
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await request(tester);
    await verify(tester);
    await tapKey(tester, 'recovery-accept');
    await tapKey(tester, 'recovery-complete');
    expect(find.byKey(const ValueKey('recovery-resume')), findsOneWidget);
    expect(find.byType(RecoveryLoginScreen), findsOneWidget);
    expect(recovery.completions, 1);
    recovery.resumeError = const AuthApiException.network();
    await tapKey(tester, 'recovery-resume');
    expect(recovery.completions, 1);
    expect(recovery.resumes, 1);
    recovery.resumeError = null;
    await tapKey(tester, 'recovery-resume');
    expect(recovery.resumes, 2);
    expect(recovery.completions, 1);
    expect(find.text('signed-in-home'), findsOneWidget);
  });

  testWidgets('restart resumes persisted approval without requesting a code', (
    tester,
  ) async {
    final recovery = _Recovery()..pending = true;
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    expect(recovery.resumes, 1);
    expect(recovery.requests, 0);
    expect(recovery.completions, 0);
    expect(find.text('signed-in-home'), findsOneWidget);
  });

  testWidgets('missing pending completion never starts another identity', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..pending = true
      ..resumeResult = false;
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await tapKey(tester, 'recovery-resume');
    expect(recovery.resumes, 2);
    expect(recovery.completions, 0);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('recovery-error')), findsOneWidget);
  });

  testWidgets('pending status failure does not offer a fresh login', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..statusError = const AuthApiException.network();
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('recovery-error')), findsOneWidget);
    expect(recovery.requests, 0);
  });

  testWidgets('request failures stay on email and never expose raw errors', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..requestError = const AuthApiException(
        'private-user-id server trace',
        statusCode: 500,
      );
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await request(tester);
    expect(find.byKey(const ValueKey('recovery-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-code')), findsNothing);
    expect(find.textContaining('private-user-id'), findsNothing);
    expect(find.byKey(const ValueKey('recovery-error')), findsOneWidget);
  });

  testWidgets('pending error switches from preauth to safe retry actions', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..requestError = const AuthApiException('recovery_pending');
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await request(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('recovery-resume')), findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-restart')), findsOneWidget);
    expect(find.text('recovery_pending'), findsNothing);
    expect(recovery.completions, 0);
  });

  testWidgets('no replacement approval passes false only after consent', (
    tester,
  ) async {
    final recovery = _Recovery()..replaceIdentity = false;
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await request(tester);
    await verify(tester);
    expect(find.textContaining('new Signal identity'), findsNothing);
    expect(recovery.completions, 0);
    await tapKey(tester, 'recovery-accept');
    await tapKey(tester, 'recovery-complete');
    expect(recovery.acceptedReplacement, isFalse);
  });

  for (final error in [
    const AuthApiException('recovery_expired'),
    const AuthApiException('private-server-details', statusCode: 429),
    const AuthApiException('private-server-details', statusCode: 401),
  ]) {
    testWidgets(
      'verification failure is localized: ${error.statusCode ?? 'expired'}',
      (tester) async {
        final recovery = _Recovery()..verificationError = error;
        await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
        await request(tester);
        await verify(tester);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(RecoveryLoginScreen)),
        );
        final expected = error.statusCode == 429
            ? l10n.recovery_error_rate_limit
            : error.statusCode == 401
            ? l10n.recovery_error_rejected
            : l10n.recovery_error_expired;
        expect(find.text(expected), findsOneWidget);
        expect(find.textContaining('private-server-details'), findsNothing);
        expect(find.byKey(const ValueKey('recovery-code')), findsOneWidget);
        expect(find.byKey(const ValueKey('recovery-complete')), findsNothing);
        expect(recovery.completions, 0);
      },
    );
  }

  testWidgets('busy request blocks duplicate submission and back navigation', (
    tester,
  ) async {
    final recovery = _Recovery()..requestGate = Completer<RecoveryChallenge>();
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await tester.enterText(find.byType(TextField), 'person@example.com');
    await tester.tap(find.byKey(const ValueKey('recovery-submit')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('recovery-submit')))
          .onPressed,
      isNull,
    );
    final context = tester.element(find.byType(RecoveryLoginScreen));
    await Navigator.of(context).maybePop();
    await tester.pump();
    expect(find.byType(RecoveryLoginScreen), findsOneWidget);
    expect(recovery.requests, 1);
    recovery.requestGate!.complete(recovery.challenge);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recovery-code')), findsOneWidget);
  });

  testWidgets('restart requires confirmation and a fresh explicit approval', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..pending = true
      ..resumeResult = false;
    await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
    await tapKey(tester, 'recovery-restart');
    expect(find.textContaining('may already have changed'), findsOneWidget);
    expect(recovery.restarts, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(recovery.restarts, 0);
    expect(find.byKey(const ValueKey('recovery-resume')), findsOneWidget);
    await tapKey(tester, 'recovery-restart');
    await tapKey(tester, 'recovery-restart-confirm');
    expect(recovery.restarts, 1);
    expect(find.byKey(const ValueKey('recovery-email')), findsOneWidget);
    await request(tester);
    await verify(tester);
    expect(recovery.completions, 0);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('recovery-accept')),
          )
          .value,
      isFalse,
    );
    await tapKey(tester, 'recovery-accept');
    await tapKey(tester, 'recovery-complete');
    expect(recovery.completions, 1);
  });

  testWidgets(
    'restart refusal retains pending state and never exposes credentials',
    (tester) async {
      final recovery = _Recovery()
        ..pending = true
        ..resumeResult = false
        ..restartError = const AuthApiException(
          'private-capability',
          statusCode: 409,
        );
      await pumpScreen(tester, RecoveryLoginScreen(coordinator: recovery));
      await tapKey(tester, 'recovery-restart');
      await tapKey(tester, 'recovery-restart-confirm');
      expect(recovery.restarts, 1);
      expect(find.byKey(const ValueKey('recovery-resume')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('private-capability'), findsNothing);
      expect(find.byKey(const ValueKey('recovery-error')), findsOneWidget);
    },
  );

  testWidgets('bound enrollment hides address and all editing controls', (
    tester,
  ) async {
    final recovery = _Recovery()..bound = true;
    await pumpScreen(tester, RecoveryEnrollmentScreen(coordinator: recovery));
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('A recovery email is verified'), findsOneWidget);
    expect(find.textContaining('person@example.com'), findsNothing);
    expect(recovery.requests, 0);
  });

  testWidgets('enrollment binds only after successful verification', (
    tester,
  ) async {
    final recovery = _Recovery();
    await pumpScreen(tester, RecoveryEnrollmentScreen(coordinator: recovery));
    await request(tester);
    expect(recovery.bound, isFalse);
    await verify(tester);
    expect(recovery.bound, isTrue);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('A recovery email is verified'), findsOneWidget);
  });

  testWidgets('enrollment verification error rechecks server before retry', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..verificationError = const AuthApiException.network();
    await pumpScreen(tester, RecoveryEnrollmentScreen(coordinator: recovery));
    await request(tester);
    await verify(tester);
    expect(find.textContaining('A recovery email is verified'), findsNothing);
    expect(find.byKey(const ValueKey('recovery-status-retry')), findsOneWidget);
    recovery.bound = true;
    await tapKey(tester, 'recovery-status-retry');
    expect(find.textContaining('A recovery email is verified'), findsOneWidget);
    expect(recovery.verifications, 1);
  });

  testWidgets('enrollment status error never enables first binding', (
    tester,
  ) async {
    final recovery = _Recovery()
      ..statusError = const AuthApiException.network();
    await pumpScreen(tester, RecoveryEnrollmentScreen(coordinator: recovery));
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('recovery-error')), findsOneWidget);
  });

  for (final locale in ['en', 'tr', 'de', 'ar']) {
    testWidgets('enrollment and restart dialog fit small screen in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final enrollment = _Recovery();
      await pumpScreen(
        tester,
        RecoveryEnrollmentScreen(coordinator: enrollment),
        locale: locale,
        scale: 2,
      );
      await request(tester);
      await verify(tester);
      expect(enrollment.bound, isTrue);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final login = _Recovery()
        ..pending = true
        ..resumeResult = false;
      await pumpScreen(
        tester,
        RecoveryLoginScreen(coordinator: login),
        locale: locale,
        scale: 2,
      );
      await tapKey(tester, 'recovery-restart');
      await tapKey(tester, 'recovery-restart-confirm');
      expect(login.restarts, 1);
      expect(find.byKey(const ValueKey('recovery-email')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'recovery forms and approval fit small keyboard view in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await pumpScreen(
          tester,
          RecoveryLoginScreen(coordinator: _Recovery()),
          locale: locale,
          scale: 2,
        );
        await request(tester);
        await verify(tester);
        await tapKey(tester, 'recovery-accept');
        await tapKey(tester, 'recovery-complete');
        expect(find.text('signed-in-home'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final settings in [false, true]) {
    testWidgets(
      '${settings ? 'settings' : 'auth'} opens recovery with MaterialPageRoute',
      (tester) async {
        final base = createWidgetTestContainer();
        final container = AppContainer.testing(
          session: base.session,
          conversations: base.conversations,
          crypto: base.crypto,
          signaling: base.signaling,
          chatAccessRuntime: base.chatAccessRuntime,
          callReadinessRuntime: base.callReadinessRuntime,
          auth: _Auth(_Recovery()),
        );
        await tester.pumpWidget(
          AppContainerScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: settings ? const SettingsScreen() : const AuthScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final target = settings
            ? find.text('Recovery email')
            : find.byKey(const ValueKey('auth-existing-account'));
        if (settings) {
          await tester.scrollUntilVisible(target, 180);
        } else {
          await tester.ensureVisible(target);
        }
        await tester.tap(target);
        await tester.pumpAndSettle();
        final screen = find.byType(
          settings ? RecoveryEnrollmentScreen : RecoveryLoginScreen,
        );
        expect(screen, findsOneWidget);
        expect(
          ModalRoute.of(tester.element(screen)),
          isA<MaterialPageRoute<void>>(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Auth implements AuthCoordinator {
  _Auth(this.recovery);
  @override
  final AccountRecoveryCoordinator recovery;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recovery implements AccountRecoveryCoordinator {
  bool bound = false;
  bool pending = false;
  bool resumeResult = true;
  bool replaceIdentity = true;
  bool? acceptedReplacement;
  int requests = 0;
  int verifications = 0;
  int completions = 0;
  int resumes = 0;
  int restarts = 0;
  Object? restartError;
  Object? statusError;
  Object? requestError;
  Object? verificationError;
  Object? completionError;
  Object? resumeError;
  Completer<RecoveryChallenge>? requestGate;
  final challenge = RecoveryChallenge(
    id: 'opaque-challenge',
    email: 'person@example.com',
    expiresAt: DateTime.utc(2099),
  );

  @override
  Future<bool> getEnrollmentStatus() async {
    if (statusError != null) throw statusError!;
    return bound;
  }

  @override
  Future<bool> hasPendingLogin() async {
    if (statusError != null) throw statusError!;
    return pending;
  }

  @override
  Future<RecoveryChallenge> requestLogin(String email) async {
    expect(email, 'person@example.com');
    requests++;
    if (requestError != null) throw requestError!;
    return requestGate == null ? challenge : await requestGate!.future;
  }

  @override
  Future<RecoveryChallenge> requestEnrollment(String email) =>
      requestLogin(email);

  @override
  Future<RecoveryLoginApproval> verifyLogin(
    RecoveryChallenge challenge,
    String code,
  ) async {
    expect(identical(challenge, this.challenge), isTrue);
    expect(code, '123456');
    verifications++;
    if (verificationError != null) throw verificationError!;
    return RecoveryLoginApproval(
      userId: 'private-user-id',
      requiresIdentityReplacement: replaceIdentity,
      capability: 'private-capability',
      identityPublicKey: 'private-key',
      expiresAt: DateTime.utc(2099),
    );
  }

  @override
  Future<void> verifyEnrollment(
    RecoveryChallenge challenge,
    String code,
  ) async {
    await verifyLogin(challenge, code);
    bound = true;
  }

  @override
  Future<void> completeLogin(
    RecoveryLoginApproval approval, {
    required bool acceptIdentityReplacement,
  }) async {
    completions++;
    acceptedReplacement = acceptIdentityReplacement;
    pending = true;
    if (completionError != null) throw completionError!;
  }

  @override
  Future<bool> resumePendingLogin() async {
    resumes++;
    if (resumeError != null) throw resumeError!;
    return resumeResult;
  }

  @override
  Future<void> restartPendingLogin() async {
    restarts++;
    if (restartError != null) throw restartError!;
    pending = false;
  }
}
