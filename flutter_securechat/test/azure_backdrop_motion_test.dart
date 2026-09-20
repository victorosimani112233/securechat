import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/services/app_container.dart';
import 'package:flutter_securechat/src/widgets/azure_backdrop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app_container.dart';

/// Arka plan deseni acilip kapatilabilir KALMALI ve acikken hareket etmeli.
///
/// Genel test yapilandirmasi (`flutter_test_config.dart`) "animasyonlari
/// azalt" bayragini acik tutar; sonsuz bir animasyon `pumpAndSettle`'in
/// oturmasini engeller. Bu yuzden kayma burada bayrak acik acik kapatilarak
/// ve `pump(sure)` ile dogrulanir.
///
/// Ayarin kendisi (`useDoodleBackground` kalicilgi) `settings_module_test`
/// icinde dogrulanir; burada yalnizca cizim katmani ele alinir.
void main() {
  Finder doodleLayer() => find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is AzureDoodlePainter,
  );

  double driftX(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find
          .ancestor(of: doodleLayer(), matching: find.byType(Transform))
          .first,
    );
    return transform.transform.getTranslation().x;
  }

  Future<void> pumpBackdrop(WidgetTester tester) async {
    await tester.pumpWidget(
      AppContainerScope(
        container: createWidgetTestContainer(),
        child: const MaterialApp(
          home: AzureBackdrop(child: SizedBox.expand()),
        ),
      ),
    );
  }

  testWidgets('desen yavasca kayar', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    // Genel yapilandirmanin bayragini GERI KOY; temizlemek sonraki testleri
    // animasyonlu birakir ve `pumpAndSettle` zaman asimina ugrar.
    addTearDown(() {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
    });

    await pumpBackdrop(tester);
    await tester.pump();
    final start = driftX(tester);

    await tester.pump(const Duration(seconds: 10));
    final later = driftX(tester);
    expect(later, greaterThan(start), reason: 'desen hareket etmeli');

    // Bir tam tile sonunda desen kendisiyle ortusur: dikis gorunmez.
    await tester.pump(const Duration(seconds: 35));
    expect(driftX(tester), lessThan(AzureDoodlePainter.tile + 1));
  });

  testWidgets('animasyonlar azaltilinca desen durur ama kaybolmaz', (
    tester,
  ) async {
    await pumpBackdrop(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(doodleLayer(), findsOneWidget, reason: 'desen gorunur kalmali');
    expect(driftX(tester), 0, reason: 'hareket durmali');
  });

}
