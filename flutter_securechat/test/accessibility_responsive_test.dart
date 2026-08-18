import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/features/onboarding/launch_flow.dart';
import 'package:flutter_securechat/src/l10n/generated/app_localizations.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_securechat/src/widgets/azure_backdrop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

void main() {
  test('light and dark theme text color pairs meet WCAG AA', () {
    for (final theme in [SecureChatTheme.light(), SecureChatTheme.dark()]) {
      final scheme = theme.colorScheme;
      final pairs = <(Color, Color, String)>[
        (scheme.onSurface, scheme.surface, 'onSurface/surface'),
        (scheme.onPrimary, scheme.primary, 'onPrimary/primary'),
        (scheme.onSecondary, scheme.secondary, 'onSecondary/secondary'),
        (scheme.onError, scheme.error, 'onError/error'),
        (scheme.onSurface, theme.scaffoldBackgroundColor, 'body/scaffold'),
        (scheme.error, theme.scaffoldBackgroundColor, 'error/scaffold'),
      ];
      for (final pair in pairs) {
        expect(
          _contrastRatio(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.brightness.name} ${pair.$3}',
        );
      }
    }
  });

  testWidgets('core shell renders on a small phone at 200 percent text scale', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568), textScale: 2);
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AzureBrandTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayse Demir').first);
    await tester.pumpAndSettle();
    expect(find.text('Uçtan uca şifreli'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('core shell renders Arabic RTL at tablet width', (tester) async {
    await _setViewport(tester, const Size(800, 1280));
    final container = createWidgetTestContainer();
    container.session.languagePreference = 'ar';
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();

    final chats = find.text('الدردشات').first;
    expect(chats, findsOneWidget);
    expect(Directionality.of(tester.element(chats)), TextDirection.rtl);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Ayse Demir').first);
    await tester.pumpAndSettle();
    expect(find.text('مشفّرة من طرف إلى طرف'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'onboarding stays above Android navigation controls on a small phone',
    (tester) async {
      await _setViewport(
        tester,
        const Size(320, 568),
        textScale: 2,
        bottomPadding: 48,
      );
      final container = createWidgetTestContainer();
      await tester.pumpWidget(
        AppContainerScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: SecureChatTheme.light(),
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('onboarding-continue'));
      expect(action, findsOneWidget);
      expect(tester.getBottomLeft(action).dy, lessThanOrEqualTo(568 - 48));
      expect(
        find.byKey(const ValueKey('onboarding-page-indicators')),
        findsOneWidget,
      );
      expect(find.text('Uçtan uca şifreli'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Doğrudan arama'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('onboarding-page-indicator-1')))
            .width,
        24,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('auth form remains scrollable and exposes keyboard actions', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568), textScale: 2);
    final container = createWidgetTestContainer();
    container.session
      ..clear()
      ..languagePreference = 'en';
    await tester.pumpWidget(SecureChatFlutterApp(container: container));
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(3));
    expect(fields[0].textInputAction, TextInputAction.next);
    expect(fields[1].textInputAction, TextInputAction.next);
    expect(fields[2].textInputAction, TextInputAction.done);
    expect(tester.takeException(), isNull);
  });

  testWidgets('critical chat actions expose localized semantics labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Ara'), findsOneWidget);
    expect(find.byTooltip('Daha Fazla'), findsOneWidget);
    expect(find.bySemanticsLabel('Ara'), findsOneWidget);

    await tester.tap(find.text('Ayse Demir').first);
    await tester.pumpAndSettle();
    for (final label in [
      'Sesli ara',
      'Görüntülü ara',
      'Ek ekle',
      'Sesli mesaj kaydet',
    ]) {
      final action = find.bySemanticsLabel(label);
      expect(action, findsOneWidget);
      final size = tester.getSize(action);
      expect(size.width, greaterThanOrEqualTo(48), reason: '$label width');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$label height');
    }
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-composer')),
      'Merhaba',
    );
    await tester.pumpAndSettle();
    final sendAction = find.bySemanticsLabel('Gönder');
    expect(sendAction, findsOneWidget);
    expect(tester.getSize(sendAction).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(sendAction).height, greaterThanOrEqualTo(48));
    expect(find.bySemanticsLabel('Sesli mesaj kaydet'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

double _contrastRatio(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

Future<void> _setViewport(
  WidgetTester tester,
  Size logicalSize, {
  double textScale = 1,
  double bottomPadding = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  tester.view.padding = FakeViewPadding(bottom: bottomPadding);
  tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
