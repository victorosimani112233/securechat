# 03 — Depolama şeması ve migration

**Durum: TAMAM (katmanlı)** · **Bağımlılık:** 01

## Yaklaşım — neden katmanlı

`signal_protocol_crypto_service.dart` hâlâ libsignal kullanıyor ve eski
store'lara bağlı. `CryptoPreKeyStore`/`CryptoSignedPreKeyStore` arayüzlerini
bu görevde silmek uygulamanın derlenmemesine yol açardı.

O yüzden yeni depolama eski yolun **yanına** eklendi. TASK_04 servisi
devraldığında eski koleksiyonlar ve arayüzler silinecek. Her commit'te
uygulama derleniyor ve testler geçiyor.

## Eklenenler

**Entity'ler** (`storage_entities.dart`)

`VodozemacAccountEntity` — tek satır, şifreli account pickle.
`VodozemacSessionEntity` — `peerId|sessionId` anahtarlı, pickle +
`lastUsedAt`.

Olm aynı peer için **birden fazla oturuma** izin veriyor: karşı taraf eski
bir prekey ile yeni bir oturum başlatabilir. Çözme denemesi en son
kullanılandan başlamak zorunda, `lastUsedAt` bu yüzden var.

**Koleksiyonlar ve DAO'lar** (`secure_chat_database.dart`)

`vodozemacAccount` ve `vodozemacSessions` snapshot'a eklendi; `_load`,
`_StorageSnapshot.empty`, `fromJson` ve `isEmpty` güncellendi.
`VodozemacAccountDao` ve `VodozemacSessionDao` yazıldı.

`clearCryptoProtocolState` **ve** `installRecoveryIdentity` yeni koleksiyonları
da temizliyor. İkincisi önemliydi: kurtarma sonrası eski yerel anahtarlara
bağlı oturumlar yaşamaz.

**Store** (`vodozemac_protocol_store.dart`)

Kapanış tabanlı: `withAccount` ve `withSession` işlem bittiğinde yeniden
pickle'lamayı **kendileri** yapıyor.

Gerekçe: vodozemac'ta hem anahtar üretimi hem her `encrypt`/`decrypt`
durumu ilerletiyor ve yazılmazsa kayboluyor. Kaybın sonuçları sessiz ve
yıkıcı — sunucuya yüklenen anahtarın yerel karşılığı olmaz, ya da aynı mesaj
anahtarı ikinci kez kullanılır. libsignal bu sorumluluğu store
callback'leriyle kendisi taşıyordu. Çağırana bırakılsa "pickle'lamayı
unutma" yazılı bir kural olurdu; API unutmayı imkânsız kılıyor.

`action` fırlatırsa durum **yazılmıyor**: yarım kalmış bir anahtar üretimi
veya başarısız bir çözme denemesi diske geçmiyor. İkisi de testli.

Durumu değiştirmeyen okumalar için ayrı `readAccount` var ve dokümantasyonu
anahtar üreten/tüketen çağrılarda kullanılmamasını söylüyor.

**Pickle anahtarı** master key'den HKDF ile amaç ayrımıyla türetiliyor
(`securechat/vodozemac-pickle/v1`). Depolama anahtarının kendisi
kullanılmıyor: aynı anahtarı iki amaç için kullanmak, birinin sızmasını
diğerinin de sızması yapar. Sunucudaki `PRIVACY_INDEX_KEY` /
`OFFLINE_QUEUE_ENCRYPTION_KEY` ayrımıyla aynı gerekçe.

**Migration** (`vodozemac_migration.dart`)

Diskteki `record` blob'ları legacy Java libsignal protobuf düzeninde;
vodozemac onları okuyamaz ve dönüştürmek de mümkün değil, çünkü iki
protokolün ratchet durumu aynı şey değil.

Silinen: yalnız kriptografik durum. **Korunan: mesaj geçmişi, konuşmalar,
kişiler, arama kayıtları, zamanlanmış mesajlar, ayarlar.** Kullanıcı hiçbir
mesajını kaybetmiyor — testle bağlandı.

Görünür sonuç: her konuşma için oturum yeniden kurulur (ilk mesajda
otomatik), her grup için sender key yeniden dağıtılır, karşı taraf kimlik
değişikliği görür. Beklenen ve doğru davranış.

Yarıda kesilirse: temizlik idempotent ve işaret **en son** yazılıyor, yani
kesilen geçiş sonraki açılışta baştan koşup aynı sonuca varıyor.

## Test

`test/vodozemac_storage_test.dart` — 17 test: pickle anahtarı türetme ve
amaç ayrımı, hesabın kalıcılığı, üretilen tek kullanımlık anahtarların
kaybolmaması, hata halinde yazılmama (hesap ve oturum için ayrı ayrı),
ratchet ilerlemesinin diske geçmesi, çok oturumlu sıralama, ve migration'ın
kripto durumunu silip kullanıcı verisini koruması.

## TASK_04 için notlar

**Grup depolaması bilerek yazılmadı.** ABI'de henüz Megolm yok (TASK_02);
uygulanmamış bir ABI için şema uydurmak spekülatif iş olurdu. Grup şekli
02 bitince netleşecek.

**Pickle anahtarını kompozisyon kökünde türet.** `app_container.dart` ve
`background_tasks.dart` master key'i zaten
`PlatformKeyMaterialStore().readOrCreateMasterKey()` ile hesaplıyor;
`VodozemacProtocolStore.derivePickleKey` oraya bağlanacak.

**Migration'ı açılışta çağır.** Store kullanılmadan önce koşmalı.

**Silinecekler** (04 servisi devraldığında): `CryptoPreKeyStore`,
`CryptoSignedPreKeyStore`, `PreKeyDao`, `SignedPreKeyDao`, `preKeys` ve
`signedPreKeys` koleksiyonları, `PreKeyEntity`, `SignedPreKeyEntity`,
`libsignal_protocol_store.dart` ve `pubspec.yaml`'daki
`libsignal_protocol_dart`.
