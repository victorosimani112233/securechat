# 08 — CI kurulumu

**Bağımlılık:** yok · **Tahmin:** 1-2 gün

## Amaç

Ürünün otomatik testini bir yerde koşturmak. Şu anda hiçbir yerde koşmuyor.

## Mevcut durum

`.github/workflows/android-pr.yml` kök dizindeki **eski Kotlin** uygulamasını
derliyor (`./gradlew :app:compileDevDebugKotlin`). Flutter testleri ve
`server_hardened` testleri hiçbir workflow'da yok. `codemagic.yaml` vardı
ama bırakıldı ve içindeki endpoint hâlâ kapatılmış sunucuyu gösteriyor
(`SECURECHAT_API_BASE_URL: "https://94.73.180.226"`) — **sil**, ölü
yapılandırma var olmayan bir kapıyı varmış gibi gösteriyor.

Test varlığı: 167 Flutter test dosyası (1206 test), 62 sunucu test dosyası,
5 Rust testi, 14 Dart FFI testi.

## Yapılacaklar

Tek workflow, Linux runner:

```yaml
- flutter analyze --no-pub
- flutter test --no-pub
- cd native/securechat_crypto && cargo test
- cd server_hardened && ./gradlew :signaling-server:test :bot-api:test
- dart tool/generate_server_contract_audit.dart   # cikti degisirse FAIL
- dart tool/audit_ios_readiness.dart
```

Sözleşme üreteci önemli: şu anda elle koşuluyor ve
`docs/SERVER_CONTRACT_AUDIT.md` eskimiş durumda ("22/22" diyor, gerçek route
sayısı 33). CI'da koşup çıktı değiştiyse build'i düşürmeli.

iOS derlemesi Linux'ta koşmaz; ayrı ve elle tetiklenen iş olarak bırak.

## Tuzak

**Testlerin %30'u davranış değil kaynak metni ölçüyor.** 162 dosyanın 49'u
`readAsStringSync` ile kaynak içeriğini assert ediyor. Bunlar lint kuralı;
yapısal kontrolleri ayrı bir job'a al ve test sayısından ayrı raporla, yoksa
"1206 test geçiyor" sayısı davranış kapsaması hakkında yanlış güven verir.

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
