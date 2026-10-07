# 05 — Sunucu sözleşmesi ve AGPL temizliği

**Bağımlılık:** 04 · **Tahmin:** 2-3 gün

## Amaç

Sunucuyu yeni istemci sözleşmesine uyarlamak ve AGPL bağımlılığını kaldırmak.

## AGPL temizliği

`org.signal:libsignal-client` yalnızca üç dosyada:

```
signaling-server/src/main/kotlin/com/securechat/signaling/
  RecoveryRecordCipher.kt
  SealedSenderCertificateIssuer.kt
  tools/SealedSenderOfflineKeygen.kt
```

Hepsi sealed-sender ve imzalama işi. İstemci Signal protokolünden çıktığı
için bunlar da kalkıyor. Bağımlılık `signaling-server/build.gradle.kts:53`
ve `gradle/libs.versions.toml:130`.

`RecoveryRecordCipher` dikkat: hesap kurtarma için Curve/Ed25519 imza
doğrulaması yapıyor olabilir — libsignal yerine izin verici bir kütüphaneye
(`ed25519-dalek` JVM karşılığı veya BouncyCastle) taşınması gerekebilir.
Önce ne kullandığını oku.

## Sözleşme değişimi

```
/api/v1/prekeys/upload     Curve25519 one-time key listesi — buyuk olcude ayakta
/api/v1/prekeys/refresh     ayni
/api/v1/prekeys/status      degismez
/api/v1/users/{id}/prekeys  bundle sekli degisiyor: identity + one-time +
                            fallback (signed prekey yerine)
/api/v2/*                   PQXDH ve sealed sender — KULLANILMIYOR, kaldirilacak
```

**Önemli:** `HttpRoutes.kt:938`'deki `/api/v1/users/{userId}/prekeys`
route'u `requireServicePrincipal` kullanıyor, yani kullanıcı token'ını
kabul etmiyor ve production profilinde istemci bundle çekemiyor. v2 route'u
(`HttpRoutes.kt:1082`) `requirePrincipal` kullanıyor — doğru desen o.
Göç sırasında v1 route'u `requirePrincipal`'a çevrilmeli.

## Tuzaklar

**vodozemac padding'siz base64 üretiyor.** Sunucunun Java tarafı
`Base64.getDecoder()` kullanıyor; padding'siz girdiyi kabul ettiğini
doğrula, etmiyorsa `getMimeDecoder()` veya normalize et. Bu sessiz bir
"geçersiz prekey" kaynağı olur.

**Sözleşme denetim aracı yol-eşleşmesine bakıyor, principal'a bakmıyor.**
`tool/generate_server_contract_audit.dart:156` yalnızca URL dizgisi
karşılaştırıyor; bu yüzden yukarıdaki principal uyuşmazlığını göremiyor ve
`docs/SERVER_CONTRACT_AUDIT.md` "22/22" diyerek yanlış yeşil veriyor
(gerçek route sayısı 33). Bu göç sırasında araca principal karşılaştırması
eklenmeli.

**`modern_prekey_bundles` tablosu boş** — kimse v2 konuşmuyor, migration'da
düşürülebilir.

## Bitirme ölçütü

- `grep -r libsignal server_hardened` → yalnızca tarihsel doküman
- `./gradlew :signaling-server:test :bot-api:test` geçiyor
- Sözleşme üreteci principal farkındalıklı ve çıktısı güncel

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
