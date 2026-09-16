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
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pushNamed('/bulk-message');
    await tester.pumpAndSettle();
  }

  testWidgets('ozelligin ne yaptigi yazili', (tester) async {
    await open(tester);
    // "Toplu mesaj" adi yaniltici: grup kurdugu sanilabilir. Alicilarin
    // birbirini gormedigi bir gizlilik ayrintisi ve gondermeden once
    // bilinmesi gerekiyor.
    expect(find.text('Herkese ayrı ayrı gider'), findsOneWidget);
    expect(find.textContaining('birbirini görmez'), findsOneWidget);
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

  testWidgets('alici secilince sayac gorunur', (tester) async {
    await open(tester);
    final checkbox = find.byType(CheckboxListTile).first;
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    // Uzun listede kac kisi secildigi listeye bakmadan gorunmeli.
    expect(find.textContaining('seçili'), findsOneWidget);
  });
}
