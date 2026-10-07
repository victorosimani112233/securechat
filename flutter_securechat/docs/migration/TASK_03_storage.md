# 03 — Depolama şeması ve migration

**Bağımlılık:** 01 · **Tahmin:** 3-4 gün · **Kritik yol:** evet

## Amaç

Kripto durumunun şeklini libsignal'dan vodozemac'a taşımak ve mevcut
kurulumlar için migration yazmak.

## Şekil değişimi

libsignal prekey'leri ayrı kayıtlarda tutuyordu; vodozemac hepsini
Account'ın içinde tutuyor:

```
storage_entities.dart
  IdentityEntity        ->  Account pickle (tek kayit)
  PreKeyEntity          ->  Account pickle icine katlaniyor  (TABLO KALKIYOR)
  SignedPreKeyEntity    ->  Account pickle icine katlaniyor  (TABLO KALKIYOR)
  SessionEntity         ->  SessionPickle, 1:1 kaliyor (~1.4 KB/peer)
  SenderKeyEntity       ->  GroupSessionPickle / InboundGroupSessionPickle
```

`lib/src/crypto/crypto_protocol_store.dart` içindeki beş arayüzden ikisi
(`CryptoPreKeyStore`, `CryptoSignedPreKeyStore`) ortadan kalkıyor.
`DatabaseCryptoProtocolStore` buna göre sadeleşiyor.

## Yapılacaklar

1. `crypto_protocol_store.dart` arayüzlerini yeniden şekillendir. Hedef:
   Account pickle'ı okuyup yazan tek bir yol + peer başına session pickle +
   grup başına group session pickle.

2. `storage_entities.dart` ve `secure_chat_database.dart`'taki DAO'ları
   güncelle. `PreKeyDao` ve `SignedPreKeyDao` kalkıyor.

3. **Migration.** Mevcut `record` blob'ları legacy Java protobuf düzeninde
   ve vodozemac bunları okuyamaz. Yani:
   - Eski oturum, prekey ve sender-key kayıtları silinir
   - Yeni bir Account üretilir, prekey'ler sunucuya yeniden yüklenir
   - Her konuşma için oturum yeniden kurulur (ilk mesajda otomatik)
   - Her grup için sender-key yeniden dağıtılır

   Bu kullanıcıya görünen bir olay. Migration'ın kullanıcıyı bilgilendiren
   ve yarıda kesilirse devam edebilen bir yol olması gerekiyor —
   `lib/src/storage/legacy_room_importer.dart` benzer bir tek seferlik
   geçiş deseni içeriyor, örnek alınabilir.

4. Migration testi: eski şemadan yeni şemaya geçişin veri kaybetmediğini
   (mesaj geçmişi KORUNUR, yalnızca kripto durumu sıfırlanır) doğrula.

## Tuzaklar

**Mesaj geçmişi silinmemeli.** Sıfırlanan şey oturum/anahtar durumu;
`messages`, `conversations`, `callLogs` tabloları olduğu gibi kalır.

**One-time key'ler Account pickle'ında.** `generateOneTimeKeys` sonrası
hesabı yeniden pickle edip yazmayı atlarsan anahtarlar kaybolur ve sunucuya
yüklediğin anahtarların yerel karşılığı olmaz — karşı taraf oturum kurar,
sen çözemezsin. Bu sessiz ve yıkıcı bir hata; teste bağla.

**Depolama katmanının bilinen sorunu.** `secure_chat_database.dart` okuma
tarafında tüm tabloları belleğe alıyor (`_load()`, satır 215) ve
`data_version` değişince baştan yüklüyor; ayrıca 1 saniyelik bir
`Timer.periodic` yoklaması var (satır 79). Bu göç o sorunu çözmek zorunda
değil ama **büyütmemeli**. Ayrı bir iş olarak duruyor.

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
