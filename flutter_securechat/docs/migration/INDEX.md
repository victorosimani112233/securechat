# vodozemac göçü — görev dizini

Her dosya ayrı bir oturumda/agent'ta çalıştırılacak şekilde yazıldı. Hepsi
kendi başına okunabilir; ortak zemin bu dosyada.

## Neden bu göç

İstemci `libsignal_protocol_dart 0.8.2` (**GPL-3.0**) kullanıyor, sunucu
`org.signal:libsignal-client` (**AGPL-3.0**). İkisi de güçlü copyleft. Ürün
kapalı kaynak kalacak ve **iki mağazaya** (App Store + Google Play)
çıkacak. GPL ailesi ile Apple'ın şartları §10 ("alıcıya ek kısıtlama
koyulamaz") üzerinden çakışıyor ve bunu uygulayan taraf Apple değil telif
sahibi. Kaynağı yayınlamak bu çatışmayı çözmüyor.

Çözüm: **vodozemac 0.9 (Apache-2.0)**. Olm (Double Ratchet) + Megolm (grup
ratchet), Least Authority denetimli (Mayıs 2022), Matrix'in tamamında
üretimde. Bedeli: **post-quantum yok**. İzin verici lisansla PQ veren kimse
yok; PQ bir gün şart olursa yol MLS.

Göç ayrıca sunucudan da AGPL'i siliyor: `libsignal-client` yalnızca üç
dosyada ve hepsi sealed-sender/imzalama işi.

## Bitmiş olanlar — bunlara dokunma

| Ne | Nerede | Durum |
|---|---|---|
| Dar C ABI (Account + Session) | `native/securechat_crypto/src/lib.rs` | 5 Rust testi geçiyor |
| Dart FFI katmanı | `lib/src/crypto/vodozemac/securechat_crypto_ffi.dart` | 14 Dart testi geçiyor |
| Feasibility ölçümü | — | Android arm64 `.so` 0.55 MB stripped |

Doğrulama:

```bash
cd native/securechat_crypto && cargo test
cd ../.. && flutter test --no-pub test/vodozemac_ffi_test.dart
```

## Mimari kararlar — gerekçesiz değiştirme

**flutter_rust_bridge KULLANILMIYOR.** Kendi codegen'ini ve runtime'ını
getiriyor, build zamanında iş yapıyor ve offline/vendor'lu derleme
disiplinini (`verification-metadata.xml`, `SECURECHAT_OFFLINE=1`) zorluyor.
vodozemac senkron ve değer tabanlı olduğu için dar bir el yazımı C ABI
yeterli. Kripto çekirdeğinde denetlenebilir ~20 fonksiyon, üretilmiş binlerce
satırdan iyidir.

**`matrix-sdk-crypto` GEREKMİYOR.** vodozemac tek başına `Account`
(identity + one-time + fallback key), `Session` (Olm), `GroupSession` /
`InboundGroupSession` (Megolm) ve `pickle`/`from_pickle` veriyor. Bu,
istemcinin libsignal'dan kullandığı yüzeyin tamamı.

**Famedly'nin Dart binding'ine BAKMA.** `pub.dev/packages/vodozemac` ve
`flutter_vodozemac` **AGPL-3.0**. Aynı Apache-2.0 crate'in üstüne kendi
binding'ini yazmak serbest, onların kodundan kopyalamak değil. Clean-room:
o depoları açma.

## Herkesin bilmesi gereken tuzaklar

**vodozemac base64'ü PADDING'SİZ üretiyor** (Matrix/libolm konvansiyonu).
Dart'ın `base64Decode`'u padding bekliyor; `base64.normalize()` şart. Sunucuya
yüklenen anahtarlarda da padding yok — sözleşme tarafında dikkat.

**Tek kullanımlık anahtarlar Account'ın İÇİNDE.** libsignal'da ayrı
kayıtlardı. `generateOneTimeKeys` çağrısından sonra hesabı yeniden
`pickle()` edip saklamak ZORUNLU, yoksa üretilen anahtarlar kaybolur.

**Her `encrypt`/`decrypt` ratchet'i ilerletiyor.** Her çağrıdan sonra oturumu
yeniden `pickle()` edip saklamak ZORUNLU, yoksa aynı mesaj anahtarı tekrar
kullanılır.

**`panic = "abort"` release profilinde.** Bir panic'in FFI sınırını geçmesi
tanımsız davranış. Testler debug profilinde koşuyor.

**iOS'ta kütüphane statik bağlanıyor**, `DynamicLibrary.process()` kullanılır.
Android ve Linux'ta `DynamicLibrary.open('libsecurechat_crypto.so')`.

## Görevler

Kritik yol: 01 → 03 → 04 → 02. Geri kalanı paralel.

| # | Görev | Bağımlılık | Tahmin |
|---|---|---|---|
| [01](TASK_01_native_build.md) | Native derleme + 5 hedef vendor'lama | — | 2-3 gün |
| [02](TASK_02_megolm.md) | Megolm grup akışı (C ABI + Dart) | 01 | 3-5 gün |
| [03](TASK_03_storage.md) | Depolama şeması + migration | 01 | 3-4 gün |
| [04](TASK_04_crypto_service.md) | Kripto servisi yeniden yazımı | 03 | 4-6 gün |
| [05](TASK_05_server.md) | Sunucu sözleşmesi + AGPL temizliği | 04 | 2-3 gün |
| [06](TASK_06_pushkit.md) | iOS PushKit + APNs VoIP | — | ~1 hafta |
| [07](TASK_07_localization.md) | 432 çevrilmemiş string | — | 1 gün |
| [08](TASK_08_ci.md) | CI kurulumu | — | 1-2 gün |
| [09](TASK_09_store.md) | Mağaza gönderim hazırlığı | 01-07 | ~1 hafta |

## Denetim raporu

Bu göçün çıktığı tam denetim (37 bulgu, canlı sunucu ölçümü dahil):
https://claude.ai/code/artifact/cc8e2eed-4798-44a8-a356-35986cdbe2d7
