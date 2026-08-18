import 'package:flutter/services.dart';

abstract final class SecureChatHaptics {
  static Future<void> light() => HapticFeedback.selectionClick();

  static Future<void> longPress() => HapticFeedback.mediumImpact();
}
