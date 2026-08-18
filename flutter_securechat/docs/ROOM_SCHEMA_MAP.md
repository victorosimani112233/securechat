# Room v1-v22 -> Flutter Encrypted Snapshot Esleme Haritasi

Bu belge `storage/schemas/com.securechat.storage.SecureChatDatabase/{1..22}.json`,
Kotlin entity dosyalari ve `StorageModule.kt` esas alinarak uretilmistir. Native
adapter Room'u calistirmaz; SQLCipher dosyasini salt-okunur acar. Bu nedenle eski
surum eksik kolonlari Dart converter'da ayni Kotlin constructor/migration
varsayilanlariyla tamamlanir ve destructive migration yolu kullanilmaz.

## Tablo Eslemesi

| Room tablosu | Ilk surum | Flutter snapshot anahtari | Anahtar / binary davranisi |
|---|---:|---|---|
| `conversations` | 1 | `conversations` | `id`; v2-v22 kolonlari asagidaki varsayilanlarla tamamlanir. |
| `messages` | 1 | `messages` | `id`, `conversation_id` FK dogrulanir. |
| `contacts` | 1 | `contacts` | `id`. |
| `prekeys` | 1 | `preKeys` | `id`; `record` BLOB byte-for-byte Base64 tasinir. |
| `signed_prekeys` | 1 | `signedPreKeys` | `id`; `record` BLOB degistirilmez. |
| `sessions` | 1 | `sessions` | `id`; Double Ratchet protobuf kaydi degistirilmez. |
| `identities` | 1 | `identities` | `addressName`; `identity_key` BLOB degistirilmez. |
| `call_log` | 8 | `callLogs` | `id`. |
| `scheduled_messages` | 10 | `scheduledMessages` | `id`. |
| `pending_timer_updates` | 17 | `pendingTimerUpdates` | `id`. |
| `export_log` | 18 | `exportLogs` | `id`. |
| `sender_keys` | 19 | `senderKeys` | `(group_id,sender_id,device_id)`; protobuf BLOB degistirilmez. |

Yerel Signal identity pair ve registration ID Room tablosunda degildir.
`crypto_prefs/local_identity_key_pair_v2`, ayni Android Keystore alias'i ile
native tarafta acilir; plaintext yalniz bellekte kalir ve rastgele transport
anahtariyla sifreli gecici export'a yazilir. Flutter snapshot'ta
`local_identity_key_pair_v1` ve `local_registration_id` olarak yeniden cihaz-ici
AEAD ile saklanir.

## Surum Zinciri ve Varsayilanlar

| Surum | Eklenen davranis | Eski satira uygulanan deger |
|---:|---|---|
| 2 | `is_group`, `group_members` | `false`, `null` |
| 3 | message `is_starred` | `false` |
| 4 | `contact_note`, `custom_notification_uri` | `null` |
| 5 | `is_archived` | `false` |
| 6 | `disappearing_duration`, `expires_at` | `0`, `null` |
| 7 | `group_admins` | `null` |
| 8 | `call_log` | eski surumde tablo yok |
| 9 | `is_favorite` | `false` |
| 10 | `scheduled_messages` | eski surumde tablo yok |
| 11 | `edited_at` | `null` |
| 12 | `edit_history` | `null` |
| 13 | `reactions` | `null` |
| 14 | `is_locked` | `false` |
| 15 | Semada yeni alan yok | veri davranisi degisikligi |
| 16 | `caption`, `is_view_once`, `is_viewed` | `null`, `false`, `false` |
| 17 | `pending_timer_updates` | eski surumde tablo yok |
| 18 | `is_export_enabled`, `export_log` | `false`, eski surumde tablo yok |
| 19 | `sender_keys` | eski surumde tablo yok; lazy olusur |
| 20 | message `is_pinned`, `pinned_at` | `false`, `null` |
| 21 | `manually_unread` | `false` |
| 22 | `is_read_only` | `false` |

Kotlin kaynakta yalniz 17->22 migration nesneleri bulunur ve builder halen
`fallbackToDestructiveMigration()` tasir. Flutter upgrade yolu bu builder'i
cagirmadigi icin 1->22 arasindaki her export semasini dogrudan donusturur.

## v22 Index ve Iliski Envanteri

- `messages`: `(conversation_id,timestamp)`,
  `(conversation_id,is_outgoing,status)`, `(conversation_id,content_type)`,
  `sender_id`, `status`, `is_starred`, `expires_at`; conversation silmede
  `ON DELETE CASCADE`.
- `conversations`: `last_message_timestamp`, `peer_id`, `is_archived`,
  `(is_pinned,last_message_timestamp)`.
- `call_log.timestamp`, `scheduled_messages.next_trigger_time`.
- `export_log(group_id,timestamp)` ve `export_log.timestamp`.
- Snapshot DAO indeksleri fiziksel SQL indeksleri olarak kopyalamaz; ayni
  siralama/filtre davranislari DAO testleriyle korunur.

## Atomiklik ve Kurtarma

1. Native taraf deterministic passphrase'i dener; eski APK random passphrase'i
   varsa Android Keystore'dan fallback olarak acar.
2. Tum satirlar, sayimlar ve binary alanlar salt-okunur okunur. Export cache'te
   AES-256-GCM ile sifrelidir; transport anahtari diske yazilmaz.
3. Dart tum export'u parse eder, kolon tiplerini, row count ve message FK'larini
   etkin DB'ye dokunmadan dogrular.
4. Yalniz bos Flutter deposu tek encrypted snapshot write ile degistirilir;
   import marker'i ayni commit icindedir. Persist hatasi in-memory state'i geri
   alir.
5. Commit sonrasi kaynak DB/WAL/SHM once arsive kopyalanip boyutlari dogrulanir,
   marker yazilir ve kaynak kopyalar temizlenir. Tekrar baslatma bu adimi
   idempotent tamamlar.

iOS'ta Room kaynagi olamayacagi icin gateway salt `absent` sonucu verir; yeni
kurulum bos encrypted snapshot ile baslar.
