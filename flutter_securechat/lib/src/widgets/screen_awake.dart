import '../platform/native_bridge.dart';

/// Uygulama penceresi acikken ekranin kararmasini engeller (goruntulu
/// arama). Cihazin ekran zaman asimi ayari degismez.
abstract final class ScreenAwake {
  static Future<void> set(bool on) => const NativeBridge().setKeepScreenOn(on);
}
