import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/features/onboarding/launch_flow.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/onboarding/onboarding_service.dart';
import 'package:flutter_securechat/src/onboarding/permission_service.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-13 T8: izin ekrani sistemde verilmis izinler icin de
/// "Izin ver" gosteriyordu.
void main() {
  Future<_MemoryOnboarding> pump(
    WidgetTester tester,
    Set<AppPermission> granted,
  ) async {
    final onboarding = _MemoryOnboarding();
    final container = createWidgetTestContainer(
      onboardingRuntime: AppOnboardingRuntime(
        service: onboarding,
        permissions: AppPermissionService(_FixedPermissions(granted)),
      ),
    );
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: '/permissions',
          routes: {
            '/': (_) => const Text('next-route'),
            '/permissions': (_) => const PermissionWalkthroughScreen(),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return onboarding;
  }

  testWidgets('already granted permissions show a check, not a button', (
    tester,
  ) async {
    final onboarding = await pump(tester, {
      AppPermission.microphone,
      AppPermission.camera,
    });
    final l10n = lookupAppLocalizations(const Locale('tr'));
    expect(find.text(l10n.grant_permission), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(onboarding.walkthroughSeen, isFalse);
  });

  testWidgets('the walkthrough is skipped when everything is granted', (
    tester,
  ) async {
    final onboarding = await pump(tester, AppPermission.values.toSet());
    expect(find.byType(PermissionWalkthroughScreen), findsNothing);
    expect(find.text('next-route'), findsOneWidget);
    expect(onboarding.walkthroughSeen, isTrue);
  });
}

class _MemoryOnboarding implements OnboardingService {
  var walkthroughSeen = false;

  @override
  Future<bool> isIntroSeen() async => true;

  @override
  Future<bool> isPermissionWalkthroughSeen() async => walkthroughSeen;

  @override
  Future<void> markIntroSeen() async {}

  @override
  Future<void> markPermissionWalkthroughSeen() async => walkthroughSeen = true;
}

class _FixedPermissions implements AppPermissionPlatform {
  _FixedPermissions(this._granted);

  final Set<AppPermission> _granted;

  @override
  Future<Set<AppPermission>> granted() async => _granted;

  @override
  Future<bool> request(AppPermission permission) async => true;
}
