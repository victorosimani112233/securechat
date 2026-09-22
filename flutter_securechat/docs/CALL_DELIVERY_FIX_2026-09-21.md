# Arka Plan Arama Teslimi ve iOS Arama Baslatma

## Sonraki JAR incelemesiyle guncelleme

Kullanicinin aktif sunucudan paylastigi JAR, GitHub referansiyla ayni degil:
ayni-token anahtar koruma duzeltmesi JAR'da zaten mevcut. Asagidaki anahtar
silme bulgusu yerel referans koda aittir; aktif JAR'in kanitlanmis ariza
nedeni olarak alinmamali. Arka plan arama yetenek ayrimi ve ayri kontrol
push siniri ise JAR'da bulunmuyor. Hash ve bytecode karsilastirmasi:
[ACTIVE_SERVER_JAR_REVIEW_2026-09-21.md](ACTIVE_SERVER_JAR_REVIEW_2026-09-21.md).

## Kapsam ve kanit

- Kullanici, iPhone ile Samsung arasinda mesajlarin iki yonde gittigini
  dogruladi. iPhone'da arama ekrani aciliyor, ardindan "Baglanti kurulamadi"
  gorunuyor. Bu yazi tek basina hata asamasini gostermiyor.
- Bagli Samsung'da FCM alicisi calisiyor; `wake_no_hint` kayitlari goruldu.
  Bu, ilgili push'ta sifreli `k` ipucunun bulunmadigini gosterir. Her birinin
  bir aramaya ait oldugu veya hangi sunucu kusurundan kaynaklandigi kanitlanmadi.
- Asagidaki kusurlar kaynak kodu ve yerel regresyon testleriyle dogrulandi.
  Uzak sunucuya erisilmedi, deployment/restart yapilmadi.
- Mevcut Android build adresi/pinleri ve Codemagic ayarlari degistirilmedi.
  Ayarlardaki adres farki, calisan iki yonlu mesajlasma karsisinda bu ariza
  icin kok neden olarak kabul edilmedi.

## Nerede ne degisti ve neden

| Dosya/modul | Degisiklik ve gerekce |
| --- | --- |
| `lib/src/services/signaling_service.dart` | WebSocket, `X-SecureChat-Call-Capable` basligini gonderir. Varsayilan `true`; yeniden baglanmada da ayni deger korunur. |
| `lib/src/background/background_tasks.dart` | UI ve CallManager bulunmayan mesaj isleyicisi `callCapable: false` kullanir. Arama teklifini alip hic islememesi engellenir. |
| `server_hardened/signaling-server/.../ConnectionManager.kt`, `WebSocketRoutes.kt`, `MessageTypes.kt` | Mesaj odakli baglantiya arama kurulum/kontrol paketleri teslim edilmez; mevcut sinirli kuyruk/push yolu kullanilir. Arka plan baglantisi on plani dusuremez; kapanisi aktif aramalari temizlemez. Eski istemciler icin baslik yoksa `true` kabul edilir. |
| `server_hardened/signaling-server/.../FcmTokenStore.kt` | Ayni token anahtarsiz yeniden kaydedildiginde mevcut, suresi dolmamis ipucu anahtari korunur. Farkli token eski anahtari devralmaz. Token ve anahtar tek tutarli kopyadan okunur. |
| `server_hardened/signaling-server/.../FcmPushSender.kt` | Arama kontrolu icin gonderilen `m` ipucu, hemen ardindan gelen `c` arama ipucunu hiz sinirina takmaz. Tani kaydina yalniz `hint=true/false` eklenir. |
| `android/app/src/main/kotlin/com/securechat/app/SecureChatNativeCallController.kt` | Telecom kaydi istisna firlatsa da mevcut yerel arama bildirimi denenir. |
| `android/app/src/main/kotlin/com/securechat/app/SecureChatCallNotificationManager.kt` | Bildirim izni/kapali bildirimler ve bildirimin API'ye verilmesi icin kimlik icermeyen kayitlar eklenir. API basarisi ekranda gorunme kaniti degildir. |
| `ios/Runner/Info.plist` | Eksik `UIBackgroundModes/voip` eklenir. Apple, bu eksikligi CallKit `unentitled` hatasinin yaygin nedeni olarak belgeler. |
| `ios/Runner/AppDelegate.swift` | Reddedilmis CallKit baslatma isteginin UUID kaydi temizlenir; sonraki kapatma/yeniden deneme sahte aktif cagriya takilmaz. Zaten bitmis cagriyi kapatma idempotenttir. CallKit ses etkinlestirme olaylari WebRTC'ye aktarilir; ses kategorisi/modu CallKit etkinlestirmesinden once ayarlanir. |
| `lib/src/media/call_manager.dart` | Baslatma hatasi mevcut yerel gizlilik korumali tani kaydinda `native-registration`, `signaling-readiness`, `ice-configuration`, `media-offer`, `offer-send` asamalarina ayrilir. Yeni SDP/token/telefon logu eklenmez. |
| `tool/audit_ios_readiness.dart` | Arama sesi Dart kanali da taranir; Swift icindeki ilgisiz `case` etiketleri kanal metodu sayilmaz. Denetim atlanmadan yanlis pozitifler giderilir. |

Sunucu dosyalarindaki `...`, `src/main/kotlin/com/securechat/signaling`
dizinidir. Eski Kotlin Android uygulamasi degistirilmedi. PostgreSQL migrasyonu,
yeni tablo, push icinde acik arama turu/kimligi veya E2EE protokol degisikligi yok.

## Dogrulama

- Son kaynakla `flutter test --no-pub --reporter expanded`: **496 test gecti**.
- Etkilenen sunucu sinirlari: **159 test gecti, 0 hata, 0 atlanan test**.
  PostgreSQL/Redis Docker entegrasyonlari, gercek Firebase SDK mesajinin agsiz
  yakalanip ipucunun cozulmesi ve yedi arka plan arama regresyonu dahil.
- `audit_ios_readiness.dart`, `audit_codemagic_privacy.dart`: **PASS**.
- `git diff --check`: temiz.
- Android release build: **123.3 MB**, basarili. Mevcut cihaz kurulumuyla
  ayni test sertifikasi kullanilarak APK imzasi dogrulandi; Samsung SM-S731B'ye
  `adb install -r` ile veriler silinmeden kuruldu. Activity acilisi `Status: ok`;
  15:01:38'de istemci `PUSH-REGISTRATION hint_submitted` kaydi goruldu. Bu kayit,
  uzak sunucunun dogru anahtarla arama push'u gonderdigini tek basina kanitlamaz.
  Artefakt: `build/app/outputs/flutter-apk/app-release-device-test-signed.apk`.
  Bu test imzali APK, uretim imzali dagitim artefakti degildir.
- `flutter analyze --no-pub` ve `dart analyze` analiz sunucusunun
  `Too many open files, errno = 24` hatasiyla basarisiz oldu. Kod sorunu
  bildirmemesi temiz analiz sonucu sayilmiyor. Diger uygulamalar kapatilmadi
  ve makinenin global limitleri degistirilmedi.
- iOS XCTest vakalari eklendi; Linux'ta Xcode/gercek iPhone derlemesi ve
  fiziksel ses/goruntu dogrulamasi yapilamadi. Statik PASS bunlarin yerine gecmez.

## Uygulama sirasi

1. Sunucuda disarida yapilmis degisiklikleri koruyarak hardened signaling
   duzeltmelerini calisan artefakta dahil et. Yalniz kaynak dosyasini kopyalamak
   yeterli degil. Ayrinti: [sunucu yoneticisi kontrol listesi](../server_hardened/signaling-server/docs/ANDROID_CALL_PUSH_VERIFICATION.md).
2. Yeni Android build'i kur; uygulamayi bir kez acarak push tokeni ve ipucu
   anahtarinin kaydini yenile. Sunucu ve istemci birlikte guncellenmeli.
3. iOS icin Codemagic'te yeni build al ve iPhone'a kur. Eski IPA bu degisiklikleri
   icermez. Sesli ve goruntulu arama, izin reddi ve tekrar denemeyi kontrol et.
4. Android'de uygulama on planda, normal arka planda ve process kapaliyken ayri
   denemeler yap. Ayarlardan "Zorla durdur" normal process kapanisi degildir.
   Arama devam ederken cevaplama, reddetme, arayanin vazgecmesi ve tekrar arama
   sonuclarini da kaydet. Mevcut eski istemciyle yapilan deneme yeni duzeltmeyi
   dogrulamaz.

## Acik sinirlar

- Bu oturumda yeni istemci + guncel uzak sunucuyla uc uca canli arama sonucu
  alinmadi. Uzak kayip ipucunun kesin nedeni henuz teyit edilmedi.
- Arama paketi, arama destekleyen baglantiya gonderildiginde kuyruktan cikar;
  ayrica CallManager ACK protokolu eklenmedi. Teklifin mevcut 30 saniyelik yas
  siniri ve kuyruk sinirlari uzatilmadi.
- Token onbellegi process bazlidir; bu duzeltme coklu sunucu cache esitlemesi
  veya coklu cihaz destegi getirmez.
- Grup SFU medya anahtarinin arka planda cozulup on plandaki CallManager'a
  aktarilmasi bu testlerle uc uca dogrulanmadi. Arama zarflarini korumak,
  sifreli grup medya anahtari aktariminin da dogrulandigi anlamina gelmez.
- `voip` satiri **PushKit uygulamasi degildir**. Projede iOS sonlandirilmis
  uygulama icin PushKit + VoIP APNs hattinin eksikligi devam ediyor. Normal
  FCM/background push ile bu durumda garantili gelen arama iddia edilmiyor.
- Calisan mesajlasma, WebRTC medya baglantisinin da calistigini kanitlamaz.
  ICE/TURN erisimi ve mikrofon/kamera izinleri cihazda ayrica dogrulanmali.

## Platform kaynaklari

- [Apple: CallKit unentitled ve eksik voip modu](https://developer.apple.com/documentation/callkit/cxerrorcoderequesttransactionerror-swift.struct/code/unentitled)
- [Apple: PushKit VoIP bildirimlerini isleme](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit)
- [Firebase: Flutter arka plan mesaj sinirlari](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages)
