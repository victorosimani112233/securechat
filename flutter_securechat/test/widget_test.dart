import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_securechat/src/app.dart';
import 'package:flutter_securechat/src/widgets/azure_backdrop.dart';

import 'support/test_app_container.dart';

void main() {
  testWidgets('shows main secure chat shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AzureBrandTitle), findsOneWidget);
    expect(find.text('Ayse Demir'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
  });

  testWidgets('opens chat and sends a demo message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      SecureChatFlutterApp(container: createWidgetTestContainer()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ayse Demir').first);
    await tester.pumpAndSettle();
    expect(find.text('Uçtan uca şifreli'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Flutter testi');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Flutter testi'), findsOneWidget);
  });
}
