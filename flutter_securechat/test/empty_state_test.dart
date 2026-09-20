import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/widgets/azure_empty_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bos durum bileseni hem SINIRLI (Scaffold govdesi) hem SINIRSIZ (ListView
/// icinde) baglamda kullaniliyor.
///
/// Regresyon: sinirli baglamda %200 metin olceginde icerik ekrani 420 px
/// asiyordu — arama gecmisi bos oldugunda ekran kiriliyordu.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget body, {
    double scale = 2,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pumpAndSettle();
  }

  const state = AzureEmptyState(
    icon: Icons.call_outlined,
    title: 'Henüz arama yok',
    message:
        'Yaptığınız ve gelen aramalar burada listelenir. '
        'Arama içeriği hiçbir zaman kaydedilmez.',
  );

  testWidgets('sinirli yukseklikte tasma uretmez', (tester) async {
    await pump(tester, state);
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('liste icinde kaydirma sarmalayicisi eklemez', (tester) async {
    await pump(tester, ListView(children: const [state]));
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(AzureEmptyState),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
      reason: 'ic ice dikey kaydirma olmamali',
    );
  });
}
