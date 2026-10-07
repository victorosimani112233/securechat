# 02 — Megolm grup akışı

**Durum: TAMAM** · **Bağımlılık:** 01, 03

## Eşleme

```
libsignal                        vodozemac
GroupCipher (giden)              GroupSession
                                 InboundGroupSession (gelen)
SenderKeyDistributionMessage     SessionKey
SenderKeyRecord                  GroupSessionPickle / InboundGroupSessionPickle
```

## Yapıldı

**C ABI** — `native/securechat_crypto/src/megolm.rs`, 13 fonksiyon.
`lib.rs` sözleşmesi birebir korundu: `null` = hata, `sc_last_error()`,
`sc_string_free`, her unsafe fonksiyonda `# Safety`. 5 Rust testi.

**ABI sürümü 2**'ye çıkarıldı. Üç yer birlikte güncellendi — Rust gövdesi,
`include/securechat_crypto.h`, Dart `expectedAbiVersion` — ve
`test/vodozemac_ffi_test.dart` içindeki tutarlılık testi üçünü bağlıyor.

**Dart** — `MegolmGroupSession`, `MegolmInboundSession`, `MegolmDecrypted`.
8 test.

**Depolama** — `VodozemacGroupSessionEntity` (grup başına giden oturum) ve
`VodozemacInboundGroupSessionEntity` (gönderen + oturum başına gelen).
Koleksiyonlar, DAO'lar ve iki temizleme noktası güncellendi.

**Store** — `withGroupSession`, `acceptGroupSessionKey`,
`decryptGroupMessage`, `resetGroupSession`, `deleteGroupSessions`. 7 test.

## İki güvenlik kararı

**Geçmiş paylaşımı ABI'ye konmadı.** vodozemac `export_at` ve `import` ile
bir oturum anahtarının **daha erken bir indeksten** paylaşılmasına izin
veriyor; bu yeni katılana geçmiş mesajları açar ve 2016 NCC Group
denetiminin Megolm'da işaret ettiği zayıflığın dayandığı yer de burası.
Ürün geçmiş paylaşmıyor, o yüzden o iki fonksiyon hiç dışa açılmadı:
yalnızca güncel `session_key` dağıtılabilir.

**Replay koruması store'un içinde.** Megolm bir oturumda her plaintext'i
tek bir indeksle şifreliyor, yani aynı indeksin ikinci kez görülmesi tekrar
oynatmadır — ve **vodozemac bunu kendisi takip etmiyor.** Kontrolü çağırana
bırakmak, unutulduğunda sessizce replay'e açık bir sistem verirdi.
`decryptGroupMessage` görülen en yüksek indeksi saklıyor ve küçük veya eşit
indeksi reddediyor.

Buna bağlı bir incelik: `acceptGroupSessionKey` aynı oturum tekrar
dağıtılırsa görülen indeksi **sıfırlamıyor**. Aksi halde saldırgan dağıtımı
tekrar göndererek replay korumasını devre dışı bırakabilirdi. Testli.

## Doğrulama

```
cargo test        10/10
cargo clippy      0 hata (-D warnings)
flutter test      1253/1253
Android artefakt  3 ABI, ABI 2, release audit PASS
```

## 04 için notlar

Servisin altı grup metodunun karşılığı artık hazır:

```
createSenderKeyDistribution  -> withGroupSession(...).sessionKey
processSenderKeyDistribution -> acceptGroupSessionKey(...)
encryptGroup / encryptGroupWire -> withGroupSession(...).encrypt(...)
decryptGroup                 -> decryptGroupMessage(...)
resetLocalSenderKey          -> resetGroupSession(...)
```

`decryptGroupMessage` **sessionId istiyor**: Megolm mesajı hangi oturuma ait
olduğunu kendi içinde taşımıyor, o yüzden kablo formatında taşınması gerekiyor.
libsignal'ın `SenderKeyDistributionMessage.id` alanıyla aynı rol. Kablo
formatı değişikliği 04'ün kapsamında.
