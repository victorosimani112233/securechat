# 02 — Megolm grup akışı

**Bağımlılık:** 01 · **Tahmin:** 3-5 gün

## Amaç

C ABI'ye ve Dart katmanına Megolm'u eklemek: mevcut SenderKey tabanlı grup
mesajlaşmasının karşılığı.

## Eşleme

```
libsignal                        vodozemac
GroupCipher                      GroupSession (giden)
                                 InboundGroupSession (gelen)
SenderKeyDistributionMessage     SessionKey  (ilk dagitim)
                                 ExportedSessionKey (gecmis paylasimi)
SenderKeyRecord                  GroupSessionPickle / InboundGroupSessionPickle
```

Rust tarafında kullanılacak tipler `vodozemac::megolm` altında:
`GroupSession`, `GroupSessionPickle`, `InboundGroupSession`, `MegolmMessage`,
`SessionKey`, `ExportedSessionKey`, `SessionConfig`.

## Yapılacaklar

1. `native/securechat_crypto/src/lib.rs` desenini izleyerek
   `src/megolm.rs` ekle. Mevcut dosyadaki sözleşmeyi birebir koru:
   pointer dönenlerde `null` = hata, ayrıntı `sc_last_error()`, stringler
   `sc_string_free` ile serbest, handle'lar `*_free` ile yok edilir.

2. Fonksiyonlar (öneri):
   ```
   sc_group_session_new() -> *mut GroupSession
   sc_group_session_free / _pickle / _from_pickle
   sc_group_session_id / _message_index
   sc_group_session_key(gs) -> *mut c_char          // ilk dagitim
   sc_group_session_encrypt(gs, bytes, len) -> *mut c_char  // base64
   sc_inbound_group_session_new(session_key_b64) -> *mut InboundGroupSession
   sc_inbound_group_session_import(exported_key_b64) -> *mut InboundGroupSession
   sc_inbound_group_session_free / _pickle / _from_pickle
   sc_inbound_group_session_decrypt(igs, message_b64) -> *mut c_char
   ```

3. `sc_abi_version()` değerini **2**'ye yükselt ve
   `securechat_crypto_ffi.dart` içindeki `expectedAbiVersion` sabitini
   birlikte güncelle. İkisi ayrı düşerse yanlış `.so` sessizce çalışır.

4. Dart tarafında `OlmAccount`/`OlmSession` desenini izleyen
   `MegolmGroupSession` ve `MegolmInboundSession` sınıfları; `dispose()`
   ve dispose sonrası kullanım kontrolü dahil.

5. Rust testleri + Dart testleri: grup oturumu kur, anahtar dağıt, şifrele,
   başka bir tarafta çöz, pickle gidip gel, mesaj indeksi ilerliyor mu.

## Tuzaklar

**Megolm'un bilinen zayıflığı:** oturum anahtarı daha erken bir indeksten
paylaşılabiliyor, bu da geçmiş paylaşımına izin veriyor. 2016 NCC Group
denetimi Megolm'da unknown key-share saldırısı buldu. Grup anahtarını hangi
indeksten paylaştığına dikkat et; geçmiş paylaşımı istemiyorsan
`ExportedSessionKey` yerine yalnızca güncel `SessionKey` dağıt.

**Her `encrypt` mesaj indeksini ilerletir.** Pickle'ı her çağrıdan sonra
sakla.

## Bitirme ölçütü

- ABI sürümü iki tarafta da 2
- Rust ve Dart testleri geçiyor
- Üç taraflı bir grupta mesaj dağıtımı testte doğrulanmış

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
