import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// Toplu gonderim ekraninin davranis kurallari.
void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pushNamed('/bulk-message');
    await tester.pumpAndSettle();
  }

  testWidgets('message is entered before searching and selecting recipients', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('bulk-message-input')),
      'Test message',
    );
    await tester.pump();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('recipient-search')), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsWidgets);
  });

  testWidgets('mesaj bos iken gonderim kapali', (tester) async {
    await open(tester);
    final button = find.widgetWithText(FilledButton, 'Gönder');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
      reason: 'alici ve mesaj olmadan gonderilememeli',
    );
    expect(button, findsNothing);
  });

  testWidgets('selected recipient has a removable avatar badge', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('bulk-message-input')),
      'Test',
    );
    await tester.pump();
    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();
    final checkbox = find.byType(CheckboxListTile).first;
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);
    expect(tester.widget<InputChip>(find.byType(InputChip)).avatar, isNotNull);
    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);
  });
}
