import 'package:flutter/material.dart';
import 'package:flutter_securechat/src/theme/secure_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acilir yuzeyler uygulamanin temasina bagli kalmali.
///
/// Diyaloglar, alt sayfalar ve menuler varsayilan Material gorunumunde
/// kaliyordu ve arka planda kayan desenin uzerinde uygulamadan kopuk
/// duruyordu. Buradaki kurallar tek tek o kopuklugu ureten sebepler.
void main() {
  for (final entry in {
    'acik': SecureChatTheme.light(),
    'koyu': SecureChatTheme.dark(),
  }.entries) {
    final label = entry.key;
    final theme = entry.value;

    test('$label tema: acilir yuzeyler OPAK', () {
      // Yari saydam bir diyalog altindaki hareketli deseni gosterir ve
      // metin okunmaz hale gelir. Arka plan animasyonlu oldugu icin bu
      // duragan bir arka planda oldugundan daha rahatsiz edici.
      for (final entry in {
        'dialogTheme': theme.dialogTheme.backgroundColor,
        'bottomSheetTheme': theme.bottomSheetTheme.backgroundColor,
        'bottomSheetTheme.modal': theme.bottomSheetTheme.modalBackgroundColor,
        'popupMenuTheme': theme.popupMenuTheme.color,
        'timePickerTheme': theme.timePickerTheme.backgroundColor,
        'datePickerTheme': theme.datePickerTheme.backgroundColor,
      }.entries) {
        expect(entry.value, isNotNull, reason: '${entry.key} rengi tanimsiz');
        expect(
          entry.value!.a,
          1.0,
          reason: '${entry.key} opak olmali',
        );
      }
    });

    test('$label tema: Material 3 renk tonlamasi kapali', () {
      // M3 yuzeyleri yukseklige gore birincil renkle tonluyor; bu, secilmis
      // paleti kaydiriyor ve acilir yuzeyleri uygulamanin geri kalanindan
      // farkli bir tona sokuyor.
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
      expect(theme.popupMenuTheme.surfaceTintColor, Colors.transparent);
      expect(theme.datePickerTheme.surfaceTintColor, Colors.transparent);
    });

    test('$label tema: acilir yuzeyler yuvarlatilmis ve cerceveli', () {
      for (final entry in {
        'dialogTheme': theme.dialogTheme.shape,
        'bottomSheetTheme': theme.bottomSheetTheme.shape,
        'popupMenuTheme': theme.popupMenuTheme.shape,
      }.entries) {
        expect(
          entry.value,
          isA<RoundedRectangleBorder>(),
          reason: '${entry.key} kare kose birakmamali',
        );
      }
      // Alt sayfa disinda cerceve de olmali: desenin uzerinde yuzeyin nerede
      // bittigi belli olsun.
      for (final shape in [theme.dialogTheme.shape, theme.popupMenuTheme.shape]) {
        expect(
          (shape! as RoundedRectangleBorder).side.style,
          BorderStyle.solid,
        );
      }
    });
  }
}
