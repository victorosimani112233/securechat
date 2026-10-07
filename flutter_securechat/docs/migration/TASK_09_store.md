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

### Teknik kalemler
- **Gerçek yedek sertifika pini.** Şu anda `app_config.dart`'taki iki pin
  aynı değer; sunucu anahtarı değişirse her kurulum tuğla. Henüz
  dağıtılmamış ikinci bir anahtar çifti üret, pinini ikinci sıraya koy.
  API'yi hostname'e pinlerken Let's Encrypt `--reuse-key` **zorunlu**, yoksa
  90 günlük yenileme pinlemeyi kırar.
- **Sürüm numarası.** `pubspec.yaml` 1.0.76, eski build'ler 1.0.108'e kadar
  çıkmış. Yukarı al.
- **Production sunucu profili.** Trust root özel anahtarı hâlâ ortamda
  (`ProductionDeploymentPolicy.kt:85` bunu production'da reddediyor).
  Geçişte anahtarları **taşıma, yenilerini üret** — hepsi internete bakan bir
  makinenin `/proc/*/environ` içinde yaşadı. SoftHSM2 + postgres TLS +
  çevrimdışı sealed sender töreni gerekiyor.

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
