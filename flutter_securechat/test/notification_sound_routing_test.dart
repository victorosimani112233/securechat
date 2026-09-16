import 'package:flutter_securechat/src/incoming/incoming_message_handler.dart';
import 'package:flutter_securechat/src/notifications/message_notification_service.dart';
import 'package:flutter_securechat/src/settings/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hangi sesin calinacagina karar veren kurallar.
void main() {
  test('eski kayitlardaki "default" degeri kaybolmaz', () {
    // Ses secenegi iki degerden on ikiye cikti. Eski kurulumlarda saklanan
    // 'default' taninmazsa kullanici ayarini kaybederdi.
    expect(
      NotificationSoundPreference.fromStorage('default'),
      NotificationSoundPreference.system,
    );
    expect(
      NotificationSoundPreference.fromStorage('silent'),
      NotificationSoundPreference.silent,
    );
    expect(
      NotificationSoundPreference.fromStorage('chime'),
      NotificationSoundPreference.chime,
    );
    // Kaldirilmis ya da bozuk bir deger sessizce varsayilana dusmeli;
    // bildirim hic calmamaktansa varsayilan sesle calsin.
    expect(
      NotificationSoundPreference.fromStorage('kaldirilmis-ses'),
      NotificationSoundPreference.system,
    );
  });

  test('her ses secenegi iki platformda da ayni dosyayi gosterir', () {
    for (final option in NotificationSoundPreference.values) {
      final asset = option.asset;
      if (asset == null) {
        // Yalniz bu ikisi dosyasiz olmali.
        expect(
          option,
          anyOf(
            NotificationSoundPreference.silent,
            NotificationSoundPreference.system,
          ),
        );
        continue;
      }
      expect(asset, startsWith('elcim_'));
    }
  });

  test('her ses AYRI kanala gider', () {
    // Android 8'den beri bir kanalin sesi olusturulduktan SONRA kodla
    // degistirilemiyor. Sesler ayni kanali paylassaydi secim ilk sesten
    // sonra hicbir ise yaramazdi.
    final channels = <String>{};
    for (final option in NotificationSoundPreference.values) {
      if (option == NotificationSoundPreference.silent) continue;
      channels.add(
        PluginLocalNotificationPresenter.channelForSound(option.asset),
      );
    }
    expect(
      channels.length,
      NotificationSoundPreference.values.length - 1,
      reason: 'her ses kendi kanalini kullanmali',
    );
  });

  test('sohbete ozel ses olayda tasiniyor', () {
    // Sohbete ozel ses uygulama genelindeki ayari ezer; bunun icin olayin
    // secimi bildirim katmanina tasimasi gerekiyor.
    final event = IncomingMessageEvent(
      messageId: 'm1',
      conversationId: 'c1',
      title: 'Ayse',
      preview: 'merhaba',
      timestamp: DateTime.utc(2026),
      isMuted: false,
      isMention: false,
      customSound: 'bell',
    );
    expect(event.customSound, 'bell');
    expect(
      NotificationSoundPreference.fromStorage(event.customSound!).asset,
      'elcim_bell',
    );
  });
}
