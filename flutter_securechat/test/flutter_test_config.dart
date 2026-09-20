import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget testlerinde "animasyonlari azalt" erisilebilirlik bayragi acik olur.
///
/// Neden: arka plan deseni surekli kayar (`AzureBackdrop`). Sonsuz bir
/// animasyon varken `pumpAndSettle` hicbir zaman oturmaz, zaman asimina
/// ugrar. Bayrak acikken desen durur — kaybolmaz — ve testler oturabilir.
/// Uretimde de ayni bayrak ayni davranisi verir; testler ozel bir yol
/// kullanmiyor.
///
/// Binding ZORLA kurulmaz. `TestWidgetsFlutterBinding` kurulunca tum HTTP
/// istekleri 400 donduruluyor; kendi `HttpOverrides` kurgusuyla calisan saf
/// Dart testleri (orn. `auth_flow_test`) bu yuzden kiriliyordu. Bu yuzden
/// yalnizca binding ZATEN varsa bayrak yazilir.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    _existingTestBinding()?.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });
  await testMain();
}

TestWidgetsFlutterBinding? _existingTestBinding() {
  try {
    final binding = WidgetsBinding.instance;
    return binding is TestWidgetsFlutterBinding ? binding : null;
  } catch (_) {
    // Henuz binding yok: dosyada widget testi bulunmuyor demektir.
    return null;
  }
}
