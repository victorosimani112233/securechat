# On planda diger sohbetlerin mesaj bildirimi

## Neden

`MessageNotificationCoordinator._onMessage`, acik sohbetin mesajini zaten
ayrica bastiriyordu. Ancak kalan tum mesajlari da `_isForeground` nedeniyle
`silent` olarak isaretliyordu. Sunucu degil, yerel bildirim katmani
bu mesajlari dusuk oncelikli sessiz kanala yonlendiriyordu. Bu durumda normal
ust bildirim bekleyen kullanici mesaj geldigini fark etmeyebiliyordu.

## Degisiklik

- `lib/src/notifications/message_notification_service.dart`: genel on-plan
  sessizlestirmesi kaldirildi. Kullanici A sohbetindeyken B'den gelen mesaj
  normal bildirim kanalini kullanir; A'nin mesajlari bastirilmaya devam eder.
- Sohbet sessize alma, mention istisnasi, uygulama/sohbete ozel ses secimi ve
  bildirim icerigi gizleme tercihleri degistirilmedi. Kanal kimlikleri ve
  sistemdeki kullanici ayarlari yeniden yaratilip sifirlanmadi.
- `test/message_notification_module_test.dart`: sohbet degistirme, sohbet
  listesinde bildirim, gizli icerik, sessiz/mention/ozel ses davranislari ve
  Android high-priority/iOS banner-sound parametreleri test edildi.

Sunucu, FCM veya veritabani semasi degismedi. Sistem bildirim izni, DND/Odak
modu ve kullanicinin kanala verdigi izinler yine isletim sisteminin
denetimindedir; kod bunlari atlatmaz.

## Dogrulama

- Ilgili bildirim, ses alternatifi ve bildirimden yonlendirme testleri: 14 gecti.
- Tum Flutter testleri: `flutter test --no-pub`, 505 test gecti.
- `git diff --check` temiz.

## Android Kurulumu

- 22 Eylul 2026 10:18:38 (Europe/Istanbul): bagli Samsung SM-S731B'ye
  `1.0.77+77` surumu `adb install -r` ile kuruldu; sonuc `Success`.
- Grup uye kimligi ve on-plan bildirim duzeltmeleri ayni APK'dadir.
- API `https://185.22.184.114`, signaling `wss://185.22.184.114:443` ve mevcut
  iki sertifika pini derleme parametreleriyle korundu. Kaynak `pubspec.yaml`
  surumu degistirilmeden `--build-name` / `--build-number` kullanildi.
- Cihazdaki mevcut test sertifikasi ile ayni imza kullanildi. Uygulama
  kaldirilmadi, verileri temizlenmedi. Bu test imzali APK store dagitimi degildir.
- `am start -W`: `Status: ok`; kurulu surum ve calisan surec dogrulandi.
  Bildirim izni acik, normal ses kanali importance=4, DND kapali. Bu kontroller
  gercek bir karsi cihaz mesajinin ust bildirimini gormenin yerine gecmez.
- APK kaynak tablosunda 10 bildirim sesi ve 3 arama sesi dogrulandi.
  Kaynak kucultme nedeniyle ZIP dosya yollari kisaltilmis olsa da
  `raw/elcim_*` Android kaynak adlari korunuyor.
- APK: `build/app/outputs/flutter-apk/app-release-device-test-signed.apk`
- SHA-256: `6e661eab5a3267427793061f96978cd0c88c6567eb234c571136c1d2ca186d25`
- Bu turda Xcode/IPA derlemesi ve commit/push yapilmadi.
