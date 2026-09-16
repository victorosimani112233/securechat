import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/widgets/azure_backdrop.dart';
import 'package:flutter_securechat/src/widgets/main_shell.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets('main tabs swipe horizontally and stay synchronized with nav', (
    tester,
  ) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('main-horizontal-pager')), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(MainShell))).canPop(),
      isFalse,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.byType(AzureBrandTitle), findsOneWidget);

    await tester.drag(find.byType(Dismissible).first, const Offset(90, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.dragFrom(const Offset(750, 100), const Offset(-700, 0));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.byIcon(Icons.call), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });

  testWidgets('conversation top bar exposes Compose search and action menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('conversation-global-search')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('conversation-search-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('conversation-global-search')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('conversation-more-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Yeni Sohbet'), findsOneWidget);
    expect(find.text('Yeni Grup'), findsOneWidget);
    expect(find.text('Toplu Mesaj'), findsOneWidget);
    expect(find.text('Planlı Mesajlar'), findsOneWidget);
  });

  testWidgets('auth follows Compose glass details then email flow', (
    tester,
  ) async {
    final container = createWidgetTestContainer();
    await container.session.clearAndPersist();
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth-details-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-details-continue')), findsOneWidget);
    expect(find.text('+90'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Cihaz Testi');
    await tester.enterText(fields.at(2), '5550000000');
    await tester.ensureVisible(
      find.byKey(const ValueKey('auth-details-continue')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-details-continue')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth-email-step-icon')), findsOneWidget);
    expect(find.byType(AzureGlassPanel), findsOneWidget);
  });

  test('Compose design assets and Flutter painters stay explicitly mapped', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final backdrop = File(
      'lib/src/widgets/azure_backdrop.dart',
    ).readAsStringSync();
    final shell = File('lib/src/widgets/main_shell.dart').readAsStringSync();

    expect(pubspec, contains('family: SpaceGrotesk'));
    expect(pubspec, contains('family: JetBrainsMono'));
    expect(backdrop, contains('class AzureDoodlePainter'));
    expect(backdrop, contains('class AzureGlassPanel'));
    expect(shell, contains('PageView.builder'));
    expect(shell, isNot(contains('IndexedStack')));
  });
}
