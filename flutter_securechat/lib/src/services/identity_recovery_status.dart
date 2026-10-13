import 'package:flutter/foundation.dart';

/// Sunucu bu cihazin Olm kimligini hesaba ait saymiyor; cihaz mesaj alamaz
/// ve kullanici e-postayla kurtarmaya yonlendirilmeli (QA 2026-10-13 T5
/// madde 3).
///
/// Anahtar yayincisi (kripto katmani) yazar, sohbet listesi dinler. Arayuz
/// kripto katmanini dogrudan import etmesin diye ayri dosyada durur.
final identityRecoveryNeeded = ValueNotifier<bool>(false);
