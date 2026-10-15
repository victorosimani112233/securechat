import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/contacts/contact_service.dart';
import 'package:flutter_securechat/src/features/auth/profile_completion_screen.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// QA 2026-10-13 O5: e-postayla kurtarilan hesapta ad ve numara bos
/// kaliyordu; numara paylasimi ve rehberde kendini bulma calismiyordu.
void main() {
  test(
    'only a logged-in session without name or number is sent to profile',
    () {
      final complete = createLoggedInTestSession();
      expect(homeRouteFor(complete), '/');
      expect(
        homeRouteFor(createLoggedInTestSession()..phoneNumber = ''),
        '/profile',
      );
      expect(
        homeRouteFor(createLoggedInTestSession()..displayName = '  '),
        '/profile',
      );
      expect(homeRouteFor(SessionStore(displayName: '', phoneNumber: '')), '/');
    },
  );

  Future<AppContainer> pump(
    WidgetTester tester,
    Future<OwnPhoneStatus> Function(String phone) status,
  ) async {
    final container = createWidgetTestContainer();
    container.session
      ..displayName = ''
      ..phoneNumber = '';
    await tester.pumpWidget(
      AppContainerScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routes: {'/': (_) => const Scaffold(body: Text('home'))},
          initialRoute: '/profile',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => ProfileCompletionScreen(phoneStatus: status),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('profile-complete-name')),
      'Ayşe',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-complete-phone')),
      '5551234567',
    );
    await tester.tap(find.byKey(const ValueKey('profile-complete-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('a number registered to this account is saved', (tester) async {
    final checked = <String>[];
    final container = await pump(tester, (phone) async {
      checked.add(phone);
      return OwnPhoneStatus.matches;
    });
    await fill(tester);
    expect(checked, ['+905551234567']);
    expect(container.session.displayName, 'Ayşe');
    expect(container.session.phoneNumber, '+905551234567');
    expect(find.text('home'), findsOneWidget);
  });

  for (final (status, message) in [
    (OwnPhoneStatus.notRegistered, 'Bu numara hesabınla eşleşmiyor'),
    (OwnPhoneStatus.otherAccount, 'Bu numara başka bir hesaba ait.'),
  ]) {
    testWidgets('$status keeps the profile empty and explains', (tester) async {
      final container = await pump(tester, (_) async => status);
      await fill(tester);
      expect(find.textContaining(message), findsOneWidget);
      expect(container.session.displayName, '');
      expect(container.session.phoneNumber, '');
      expect(find.text('home'), findsNothing);
    });
  }

  testWidgets('a failed check asks to retry instead of saving', (tester) async {
    final container = await pump(
      tester,
      (_) async => throw StateError('offline'),
    );
    await fill(tester);
    expect(
      find.byKey(const ValueKey('profile-complete-error')),
      findsOneWidget,
    );
    expect(container.session.phoneNumber, '');
  });

  testWidgets('invalid input never reaches the directory', (tester) async {
    var calls = 0;
    await pump(tester, (_) async {
      calls++;
      return OwnPhoneStatus.matches;
    });
    await tester.enterText(
      find.byKey(const ValueKey('profile-complete-phone')),
      '555',
    );
    await tester.tap(find.byKey(const ValueKey('profile-complete-save')));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('not now goes home without saving', (tester) async {
    final container = await pump(tester, (_) async => OwnPhoneStatus.matches);
    await tester.tap(find.byKey(const ValueKey('profile-complete-later')));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(container.session.phoneNumber, '');
  });
}
