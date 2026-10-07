# 04 — Kripto servisi yeniden yazımı

**Bağımlılık:** 03 · **Tahmin:** 4-6 gün · **Kritik yol:** evet

## Amaç

İstemcinin libsignal kullanan üç dosyasını yeni API üzerine taşımak.

```
lib/src/crypto/libsignal_protocol_store.dart       209 satir  -> kalkiyor
lib/src/crypto/signal_protocol_crypto_service.dart 432 satir  -> yeniden
lib/src/crypto/pre_key_manager.dart                369 satir  -> yeniden
```

`lib/src/features/settings/about_screen.dart` da libsignal'a referans
veriyor (lisans metni) — güncellenmeli.

## API eşlemesi

```
libsignal                           vodozemac (Dart katmani)
IdentityKeyPair                     OlmAccount + identityKeys()
PreKeyRecord havuzu                 account.generateOneTimeKeys(n)
SignedPreKeyRecord                  account.generateFallbackKey()
SessionBuilder.process(bundle)      account.createOutboundSession(...)
SessionCipher.encrypt               session.encrypt(bytes) -> OlmEnvelope
SessionCipher.decrypt               session.decrypt(envelope)
PreKeySignalMessage / SignalMessage OlmEnvelope.type (0 = PreKey, 1 = mesaj)
```

## Yapılacaklar

1. `pre_key_manager.dart`'ı yeniden yaz. `buildSerializedReplenishBatch`
   sözleşmesini koru — `pre_key_maintenance_service.dart` ona bağlı ve o
   dosya **yakın zamanda düzeltildi, dokunmaya gerek yok** (commit
   `fe57367`: background isolate token yenileme).

2. `signal_protocol_crypto_service.dart`'ı yeniden yaz. Dikkat: bu dosyanın
   dışa verdiği sözleşme çok yerde kullanılıyor —
   `incoming_message_handler.dart`, `send_message_use_case.dart`,
   `media_message_service.dart`, `call_manager.dart`, `group_management_service.dart`.
   Mümkün olduğunca **dışa dönük imzayı koru**, böylece değişiklik bu
   dosyayla sınırlı kalır.

3. `no plaintext fallback` davranışını koru: encrypt/session/prekey hatasında
   mesaj `FAILED` olur, düz metin gönderilmez. Bu bir ürün sözleşmesi,
   `test/signal_protocol_crypto_service_test.dart` içinde
   "missing PreKey bundle fails closed without a local AEAD fallback"
   testiyle korunuyor.

4. `pubspec.yaml`'dan `libsignal_protocol_dart` bağımlılığını kaldır. GPL-3.0
   notunu da sil.

## Tuzaklar

**Her encrypt/decrypt sonrası session pickle'ını sakla.** libsignal'ın store
callback'leri bunu otomatik yapıyordu; vodozemac'ta sorumluluk sende.
Atlanırsa aynı mesaj anahtarı tekrar kullanılır — ciddi bir kripto hatası.

**`test/signal_protocol_crypto_service_test.dart` büyük ve davranış
sözleşmesini tutuyor.** Silme, uyarlamaya çalış: 21 MB'lık medya akışı,
grup sender-key sırası, paralel ratchet erişimi gibi gerçek senaryoları
koruyor.

**Mimari sınır testleri var.** `test/architecture_boundaries_test.dart`
feature widget'larının kriptoyu import etmesini yasaklıyor; yeni dosya
yollarının o listeyle uyumlu olması gerekiyor.

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
