import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ayarlar alt sayfalarinin iki degismezi.
///
/// Bu test KAYNAK METNI uzerinde calisiyor, calisan widget uzerinde degil.
/// Sebebi: `SettingsScreen` gercek bir `SettingsService` istiyor, o da
/// `ScheduledMessageService` -> DAO -> veritabani zincirini cekiyor. Bu
/// iki kural icin o kurulumu ayaga kaldirmak orantisiz kaliyor.
///
/// Zayif tarafi acik: bicimlendirme degisirse kirilabilir. Buna ragmen
/// deger uretiyor, cunku sinadigi iki hata da SESSIZ: ekran yanlis yerde
/// duran ya da guncellenmeyen bir anahtar gosteriyor, hicbir yerde hata
/// olusmuyor.
void main() {
  final source = File(
    'lib/src/features/settings/settings_screen.dart',
  ).readAsStringSync();

  String bodyOf(String methodName) {
    final start = source.indexOf('static Future<void> $methodName(');
    expect(start, isNot(-1), reason: '$methodName bulunamadi');
    final rest = source.substring(start + 1);
    final next = rest.indexOf('  static ');
    return next == -1 ? rest : rest.substring(0, next);
  }

  test('bildirim sayfasi yalniz ses, onizleme gizlilige ait', () {
    // "Mesaj icerigini goster" kilit ekraninda ne gorunecegini belirliyor:
    // bir gizlilik karari, ses tercihiyle ilgisi yok. Bildirim sayfasinda
    // duruyordu.
    expect(
      bodyOf('_showNotificationSheet'),
      isNot(contains('settings_show_message_preview')),
      reason: 'onizleme anahtari bildirim SESI sayfasinda olmamali',
    );
    expect(
      bodyOf('_showPrivacySheet'),
      contains('settings_show_message_preview'),
      reason: 'onizleme anahtari gizlilik sayfasinda olmali',
    );
  });

  test('sayfalar ayar akisini dinliyor, yerel kopya tutmuyor', () {
    // Yerel kopya iki soruna yol aciyordu: deger ancak kaydetme bittikten
    // sonra degisiyordu (dokunusa tepkisiz goruntu), ve kaydetme BASARISIZ
    // olsa bile ekran yeni degeri gosteriyordu.
    for (final sheet in ['_showNotificationSheet', '_showPrivacySheet']) {
      final body = bodyOf(sheet);
      expect(
        body,
        contains('stream: service.states'),
        reason: '$sheet ayar akisini dinlemeli',
      );
      expect(
        body,
        isNot(contains('StatefulBuilder')),
        reason: '$sheet yerel kopya tutmamali',
      );
    }
  });
}
