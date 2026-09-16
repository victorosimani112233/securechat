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

  test('ayar sayfalari akisi dinliyor, yerel kopya tutmuyor', () {
    // Yerel kopya iki soruna yol aciyordu: deger ancak kaydetme bittikten
    // sonra degisiyordu (dokunusa tepkisiz goruntu), ve kaydetme BASARISIZ
    // olsa bile ekran yeni degeri gosteriyordu.
    //
    // Denetim yalniz AYAR sayfalarini kapsiyor. Dosyadaki diger
    // `StatefulBuilder` kullanimlari (orn. hesap silme onayindaki 'siliniyor'
    // durumu) mesru yerel durumdur ve bu kuralin disindadir.
    final sheets = {
      'gizlilik': bodyOf('_showPrivacySheet'),
      'ses': source.substring(source.indexOf('class _NotificationSoundSheet')),
    };
    for (final entry in sheets.entries) {
      expect(
        entry.value,
        isNot(contains('StatefulBuilder')),
        reason: '${entry.key} sayfasi yerel kopya tutmamali',
      );
      expect(
        entry.value,
        contains(RegExp(r'stream: (widget\.)?service\.states')),
        reason: '${entry.key} sayfasi ayar akisini dinlemeli',
      );
    }
  });

  test('ses secenekleri dinlenebilir', () {
    // Duymadan secim yapilamaz. Onizleme, bildirimi calanin aksine UYGULAMA
    // tarafindan calindigi icin ayni dosyanin Flutter varligi olarak da
    // paketlenmesi gerekiyor.
    expect(source, contains("setAsset('assets/sounds/"));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('assets/sounds/'),
      reason: 'onizleme dosyalari Flutter varligi olarak paketlenmeli',
    );
  });
}
