import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ayar sayfalari ve bildirim sesi secicisinin degismezleri.
///
/// Bu testler KAYNAK METNI uzerinde calisiyor, calisan widget uzerinde
/// degil. Sebebi: `SettingsScreen` gercek bir `SettingsService` istiyor, o da
/// `ScheduledMessageService` -> DAO -> veritabani zincirini cekiyor. Bu
/// kurallar icin o kurulumu ayaga kaldirmak orantisiz kaliyor.
///
/// Zayif tarafi acik: bicimlendirme degisirse kirilabilir. Buna ragmen deger
/// uretiyor, cunku sinadiklari hatalarin hepsi SESSIZ — ekran yanlis yerde
/// duran, guncellenmeyen ya da dinlenemeyen bir secenek gosteriyor ve
/// hicbir yerde hata olusmuyor.
void main() {
  final settings = File(
    'lib/src/features/settings/settings_screen.dart',
  ).readAsStringSync();
  final picker = File(
    'lib/src/widgets/notification_sound_picker.dart',
  ).readAsStringSync();
  final chatInfo = File(
    'lib/src/features/chat/chat_info_screen.dart',
  ).readAsStringSync();

  String bodyOf(String methodName) {
    final start = settings.indexOf('static Future<void> $methodName(');
    expect(start, isNot(-1), reason: '$methodName bulunamadi');
    final rest = settings.substring(start + 1);
    final next = rest.indexOf('  static ');
    return next == -1 ? rest : rest.substring(0, next);
  }

  test('bildirim sayfasi yalniz ses, onizleme gizlilige ait', () {
    // "Mesaj icerigini goster" kilit ekraninda ne gorunecegini belirliyor:
    // bir gizlilik karari, ses tercihiyle ilgisi yok.
    expect(
      bodyOf('_showNotificationSheet'),
      isNot(contains('settings_show_message_preview')),
    );
    expect(
      bodyOf('_showPrivacySheet'),
      contains('settings_show_message_preview'),
    );
  });

  test('gizlilik sayfasi ayar akisini dinliyor, yerel kopya tutmuyor', () {
    // Yerel kopya iki soruna yol aciyordu: deger ancak kaydetme bittikten
    // sonra degisiyordu, ve kaydetme BASARISIZ olsa bile ekran yeni degeri
    // gosteriyordu.
    final body = bodyOf('_showPrivacySheet');
    expect(body, isNot(contains('StatefulBuilder')));
    expect(body, contains('stream: service.states'));
  });

  test('ses secenekleri dinlenebilir ve varliklar paketli', () {
    // Duymadan secim yapilamaz. Onizlemeyi bildirimi calanin aksine UYGULAMA
    // caliyor, yani platform kaynagina erisemiyor; ayni dosyalarin Flutter
    // varligi olarak da paketlenmesi gerekiyor.
    expect(picker, contains("setAsset('assets/sounds/"));
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('assets/sounds/'),
      reason: 'onizleme dosyalari Flutter varligi olarak paketlenmeli',
    );
    for (final sound in [
      'chime', 'bell', 'tap', 'warm', 'soft',
      'melody', 'flow', 'sparkle', 'beep', 'ding',
    ]) {
      expect(
        File('assets/sounds/elcim_$sound.wav').existsSync(),
        isTrue,
        reason: 'onizleme dosyasi eksik: $sound',
      );
      expect(
        File('ios/Runner/Sounds/elcim_$sound.wav').existsSync(),
        isTrue,
        reason: 'iOS ses dosyasi eksik: $sound',
      );
      expect(
        File('android/app/src/main/res/raw/elcim_$sound.wav').existsSync(),
        isTrue,
        reason: 'Android ses dosyasi eksik: $sound',
      );
    }
  });

  test('ses secicisi iki yerde de AYNI bilesen', () {
    // Ayri ayri yazilsalardi listeler zamanla ayrisirdi: bir yere eklenen
    // ses digerinde gorunmezdi.
    expect(settings, contains('NotificationSoundPicker('));
    expect(chatInfo, contains('NotificationSoundPicker('));
    // 'Uygulama ayarini kullan' yalniz sohbete ozel secimde anlamli.
    expect(chatInfo, contains('allowInherit: true'));
    expect(settings, isNot(contains('allowInherit: true')));
  });

  test('susturulmus sohbette ses satiri gizli', () {
    // Susturma daha guclu bir karar; ikisini ayni anda gostermek celiskili
    // goruntu veriyor.
    expect(chatInfo, contains('if (!c.isMuted)'));
  });
}
