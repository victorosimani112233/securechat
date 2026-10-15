# 09 — Mağaza gönderim hazırlığı

**Bağımlılık:** 01-07 · **Tahmin:** ~1 hafta (çoğu bekleme)

## Hazır olanlar

```
APK   elcim-1.0.76-arm64-upload-signed.apk   45.5 MB, imzali, dogrulandi
AAB   app-release.aab                        90.5 MB, audit PASS
keystore  ~/securechat-keys/securechat-upload.keystore  (RSA 4096, PKCS12)
          parola ~/securechat-keys/upload-keystore-password.txt
          SHA-256 83:07:28:5F:CD:A7:AA:AB:57:16:C5:EA:B8:41:19:4C:
                  9E:FF:DD:04:88:F4:F8:55:70:ED:A2:7C:BA:B5:80:D8
site  server_hardened/deploy/site/  — privacy, terms, delete-account, index
      sunucuya kurulu, nginx vhost aktif, ACME yolu test edildi
targetSdk 36 sabitlendi · ITSAppUsesNonExemptEncryption eklendi
```

**Play App Signing ilk yüklemede bu anahtara kilitlenir.** Parolayı parola
yöneticisine al.

## Yapılacaklar

### Hesaplar — lead time var, önce başlat
- Apple Developer Program. Bireysel günler, şirket hesabı D-U-N-S gerektirir
  ve haftalar sürebilir.
- Google Play Console, 25 USD tek seferlik.

### Hukuki içerik
Site sayfalarındaki `<mark>` işaretli her yer bir beyandır: veri sorumlusu
unvanı ve adresi, iletişim e-postası, sunucu ülkesi, tarihler. Sarı uyarı
kutularını (`<div class="fill">`) sil. `terms.html` şablon — sorumluluk
sınırı, uygulanacak hukuk ve uyuşmazlık maddeleri avukat görmeli.

### DNS ve sertifika
```
tereaiqos.online   A      185.22.184.114     DNS only (gri bulut)
www                CNAME  tereaiqos.online   DNS only (gri bulut)
```
Gri bulut **şart**: turuncuda TLS Cloudflare'de sonlanır. Site için zararsız
olur ama aynı hatayı API hostunda yapmak sertifika pinlemesini kırar.
Sonra: `certbot certonly --webroot -w /var/www/certbot -d tereaiqos.online -d www.tereaiqos.online`
ve `/etc/nginx/sites-available/elcim-site` içindeki 443 bloğunun yorumunu kaldır.

Ayrıca canlı `_dmarc` kaydı `rua=mailto:victorosim587@gmail.com` gösteriyor —
o adres sizin değil, DMARC raporları oraya gidiyor. Düzelt.

### Marka ve paket adı — KARAR (2026-10-14), kod değişimi Firebase'i bekliyor
Uygulama adı **ELÇİM**, Android `applicationId` ve iOS bundle ID
**`com.elcim.app`** (alan adı elcim.com kullanıcıya ait).

**Engel:** kullanıcı Firebase konsolunda `com.elcim.app` için yeni Android
ve iOS uygulaması kaydedip `google-services.json` ve
`GoogleService-Info.plist` dosyalarını verecek; o gelmeden kod
değiştirilmez.

Değişecekler (`com.securechat.app` docs dışında 31 dosyada geçiyor):
- `android/app/build.gradle.kts` → `applicationId` (Kotlin `namespace` ve
  paket dizinleri kalabilir)
- iOS `PRODUCT_BUNDLE_IDENTIFIER` (`ios/Runner.xcodeproj/project.pbxproj`,
  üç yapılandırma)
- `lib/src/push/push_service.dart` → `iosBundleId`
- Firebase dosyaları ve `SecureChatFirebaseOptions` uygulama kimlikleri
- `test/firebase_android_configuration_test.dart`,
  `tool/audit_ios_readiness.dart` içindeki bundle denetimi
- `tool/ios_personal_signing.sh`

İç ad olarak kalabilir: `com.securechat.app.background.*` görev adları
(`background_scheduler.dart`, `AppDelegate.swift`, `Info.plist`), Kotlin
paket dizinleri. Sunucu paket adını kullanmıyor.

Yeni `applicationId` ile `versionCode` sıfırdan başlayabilir; 2108 sınırı
yalnız eski paket içindi.

Değişimden sonra cihazda: mesaj bildirimi, arka planda ve kilit ekranında
gelen arama, Telecom `ConnectionService`.

**Hiçbir mağazaya `com.securechat.app` ile yükleme yapılmaz.** İlk yükleme
`com.elcim.app` ile.

**Karar (2026-10-15):** TestFlight için önce **bireysel** Apple Developer
hesabı açılıyor, şirkete sonra geçilecek. Geçiş **aynı üyeliğin** Apple
Developer Support üzerinden kurumsala dönüştürülmesiyle yapılmalı (D-U-N-S
ile); Team ID, uygulama ve bundle ID korunur. Ayrı bir şirket hesabı açılırsa
`com.elcim.app` bireysel hesaba bağlı kalır (transfer App Store'da yayın
şartı ister) ve Team ID değiştiği için keychain'deki E2EE anahtarlarına yeni
imzalı sürüm erişemez.

### Teknik kalemler
- **Gerçek yedek sertifika pini.** Şu anda `app_config.dart`'taki iki pin
  aynı değer; sunucu anahtarı değişirse her kurulum tuğla. Henüz
  dağıtılmamış ikinci bir anahtar çifti üret, pinini ikinci sıraya koy.
  API'yi hostname'e pinlerken Let's Encrypt `--reuse-key` **zorunlu**, yoksa
  90 günlük yenileme pinlemeyi kırar.
- **Sürüm numarası.** `pubspec.yaml` 1.0.76, eski `com.securechat.app`
  build'leri 1.0.108'e kadar çıkmış. Paket `com.elcim.app` olunca bu sınır
  kalkar (yukarıya bak); eski paketle yayın yapılmayacak.
- **Production sunucu profili.** Trust root özel anahtarı sorunu
  **kapandı**: sealed sender kaldırıldı, o anahtarlar artık hiçbir amaca
  hizmet etmiyor ve `PurposeSeparatedSecrets` zorunlu listesinden çıktı.
  Çevrimdışı sealed sender töreni de gerekmiyor. Kalan engel SoftHSM2 +
  postgres TLS. Yine de canlı kutudaki eski secret dosyalarını **silin** —
  internete bakan bir makinenin `/proc/*/environ` içinde yaşadılar.

### Form işi
Play: Data Safety formu (eşlemesi `server_hardened/deploy/site/README.md`
içinde kodla doğrulanmış halde), içerik derecelendirmesi,
`SYSTEM_ALERT_WINDOW` ve pil muafiyeti beyanları (ikisi de **kullanılıyor**,
`MainActivity.kt:224` ve `:270-272` — kaldırma, beyan et).

App Store: App ID, push capability, provisioning, ekran görüntüleri, yaş
derecelendirmesi, ve **inceleyene çalışan bir test hesabı** — kayıt telefon +
e-posta OTP istediği için inceleyenin gerçekten girebileceği bir hesap
gerekiyor. Sık atlanıp ret yiyen detay.

### Konsol alanları
| Alan | Değer |
|---|---|
| Play — Gizlilik politikası | `https://tereaiqos.online/privacy` |
| Play — Hesap silme URL'si | `https://tereaiqos.online/delete-account` |
| App Store — Privacy Policy | `https://tereaiqos.online/privacy` |
| App Store — Support URL | `https://tereaiqos.online/` |

---

## Ortak zemin

Önce [INDEX.md](INDEX.md) oku — mimari kararlar ve herkesi ilgilendiren
tuzaklar orada. Özellikle: vodozemac base64'ü padding'siz üretir, one-time
key'ler Account pickle'ının içinde durur, her encrypt/decrypt sonrası
yeniden pickle gerekir, ve Famedly'nin AGPL Dart binding'ine bakılmaz.

## Bitirme ölçütü

```bash
cd /home/user497/securechat/flutter_securechat
export PATH="/home/user497/flutter/bin:$PATH"
flutter analyze --no-pub     # temiz olmali
flutter test --no-pub        # tamami gecmeli
```
