# 06 — iOS PushKit ve APNs VoIP

**Bağımlılık:** yok · **Tahmin:** ~1 hafta

## Amaç

Kapalı uygulamaya gelen aramanın çalmasını sağlamak. App Store incelemesi
bunu test ediyor.

## Mevcut durum

`ios/Runner/AppDelegate.swift` CallKit'i kullanıyor (`CXProvider`,
`CXCallController`, `reportNewIncomingCall` satır 676) ama **PushKit yok** —
`grep PKPushRegistry ios/` sıfır isabet. Çağrı bildirimi Dart tarafından
method channel üzerinden tetikleniyor, yani uygulama canlıyken çalışıyor,
kapalıyken çalışmıyor: data-only APNs bildirimi uygulamayı çağrı için
uyandırmıyor.

`UIBackgroundModes` içinde `voip` **var ve kalmalı** — CallKit'in kendisi
onu gerektiriyor. Projenin kendi denetimi bunu zorluyor:
`dart tool/audit_ios_readiness.dart` → "CallKit outgoing calls require
UIBackgroundModes voip". Kaldırmaya çalışma.

## Yapılacaklar

1. `PKPushRegistry` kaydı, `.voIP` tipi. iOS 13+ kuralı: VoIP push alındığında
   **mutlaka** `reportNewIncomingCall` çağrılmalı, yoksa sistem uygulamayı
   cezalandırır ve sonraki push'ları kesir.

2. Apple Developer tarafında VoIP Services sertifikası veya APNs auth key;
   `.voip` token'ı sunucuya kaydedilmeli. Mevcut `POST /api/v1/fcm/register`
   sözleşmesi genişletilebilir (token tipi alanı).

3. Sunucuda APNs VoIP göndericisi. `FcmPushSender.kt` deseni örnek;
   iOS için ayrı bir yol gerekiyor çünkü VoIP push FCM üzerinden gitmiyor.

4. Push payload'ı **içerik taşımamalı** — mevcut gizlilik sözleşmesi bu:
   gönderen, alıcı, mesaj, grup adı veya önizleme yok. Yalnızca uyandırma
   sinyali. `server_hardened/deploy/site/privacy.html` bunu kullanıcıya
   böyle anlatıyor, bozarsan politika yanlış olur.

## Tuzaklar

**iOS 13+ zorunluluğu katı.** VoIP push alıp `reportNewIncomingCall`
çağırmazsan sistem gelecek push'ları engelliyor. Her kod yolunda çağrıldığını
garanti et.

**`ITSAppUsesNonExemptEncryption=true`** eklendi; BIS'e yıllık
self-classification raporu yükümlülüğü var. Bu görevin işi değil ama
mağaza gönderiminde hatırla.

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
