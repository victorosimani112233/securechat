import 'dart:async';

/// Ayni nesne kalan ama her dinleyicide kaynagi yeniden acan akis.
///
/// Ekranlar akislarini bir kez kurup saklar; `build` icinde her seferinde
/// yeni akis vermek her setState'te aboneligi yeniler ve kaynagin
/// projeksiyonunu bastan calistirir. Agac yeniden kurulunca StreamBuilder
/// saklanan akisi tekrar dinleyebilir; tek dinleyicili kaynaklar (async*
/// getter'lar, bellek deposu) ikinci dinlemede hata verirdi.
Stream<T> relistenable<T>(Stream<T> Function() open) =>
    Stream<T>.multi((controller) {
      final subscription = open().listen(
        controller.addSync,
        onError: controller.addErrorSync,
        onDone: controller.closeSync,
      );
      controller
        ..onCancel = subscription.cancel
        ..onPause = subscription.pause
        ..onResume = subscription.resume;
    });
