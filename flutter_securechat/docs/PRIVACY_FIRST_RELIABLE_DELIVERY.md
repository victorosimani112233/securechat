# Gizlilik Öncelikli Güvenilir Mesaj Teslimi

Son güncelleme: 2026-09-17

Bu belge, mesaj teslim güvenilirliği artırılırken sunucuda mümkün olan en az
verinin tutulması için yapılan değişiklikleri ve güvenlik sınırlarını açıklar.
Bu tasarım bir sunucu mesaj geçmişi oluşturmaz; PostgreSQL mailbox eklemez ve
FCM/APNs'i mesaj taşıyıcısı olarak kullanmaz.

## Kriptografik sınır

Bir bekleyen mesaj sunucuda iki katmanlıdır:

1. İç katman istemcinin ürettiği Signal Protocol E2EE ciphertext'idir. Mesaj
   metni, chat-control içeriği ve grup SenderKey içeriği bu katmandadır.
2. Dış katman Redis için sunucuya ait AES-256-GCM zarfıdır (`OQ1`). Redis
   anahtarları alıcı kimliğinin HMAC blind index'idir.

Sunucu dış AES-GCM zarfını açabilir; bunu yeniden WebSocket'e gönderebilmek
için yapması gerekir. Açılan veri yine Signal ciphertext'tir. Sunucuda cihazın
Signal private identity/ratchet anahtarları bulunmadığından içeriği çözemez.

Bu, sunucunun hiçbir şey görmediği anlamına gelmez. Sunucu canlı yönlendirme
için gönderen ve alıcı hesap kimliğini, bağlantı IP'sini, zamanı, yaklaşık
zarf boyutunu ve opak teslim tokenını görür. Tam host ele geçirilmesi dış zarf
anahtarını ve bu metaveriyi açığa çıkarır; mesaj plaintext'ini açığa çıkarmaz.

İlk Signal oturumu için public prekey bundle sunucudan alınır. Mevcut TOFU
identity pinning daha sonraki anahtar değişimini durdurur, fakat kullanıcılar
ilk temasta safety number/fingerprint'i bağımsız kanaldan karşılaştırmazsa
kötü niyetli bir sunucuya karşı ilk temas MITM riski tamamen ortadan kalkmaz.
Bu sınır key transparency veya bağımsız safety-number doğrulaması olmadan
"sunucuya hiç güven yok" şeklinde sunulmamalıdır.

## Güvenlik tabanı

Üretim davranışı aşağıdaki kontrolleri birlikte zorunlu tutar:

- Mesaj ve özel kontrol payload'ları cihazdan çıkmadan önce Signal Protocol
  ile uçtan uca şifrelenir. Direct Double Ratchet ve grup SenderKey ratchet'i
  her mesajda ilerler; aynı plaintext'in ardışık gönderimleri farklı
  ciphertext üretir.
- Android ve iOS sohbet geçmişi SQLCipher içindedir. Runtime gerçek SQLCipher
  bağlanmadığını algılarsa düz SQLite'a düşmek yerine depoyu açmayı reddeder;
  32 bayt master materyal Android Keystore/iOS Keychain'de tutulur.
- Release transport yalnız HTTPS/WSS kabul eder. Uygulama hem birincil hem
  yedek SPKI pin ister ve pin eşleşmezse bağlantıyı reddeder.
- FCM/APNs yalnız `securechat_wake_v2` uyandırması taşır; plaintext,
  ciphertext, sender, recipient veya mesaj türü push payload'ına girmez.
- Sunucu sohbet geçmişi oluşturmaz. Teslim edilmemiş Signal ciphertext'i
  yalnız persistence kapalı Redis RAM'de ACK veya kısa TTL sonuna kadar
  bulunabilir; varsayılan 15 dakika, sert yapılandırma tavanı 1 saattir.

Bu sözleşmede "sunucuda mesaj tutulmaz" ifadesi, teslim edilmiş konuşma
geçmişinin veya plaintext'in tutulmadığı anlamına gelir. Kısa ömürlü ve E2EE
teslim kuyruğu ayrıca ve açıkça belirtilmeden mutlak bir ifade kullanılmaz.

## Teslim akışı

1. Gönderen, plaintext mesajı encrypted local database'e yazar.
2. Signal ciphertext bir kez üretilir ve rastgele 256-bit `deliveryId` ile
   encrypted local outbox'a socket gönderiminden **önce** yazılır.
3. Sunucu authenticated gönderici, alıcı ve `deliveryId` üzerinden HMAC ile
   `deliveryToken` türetir. İstemcinin verdiği token kabul edilmez.
4. Ciphertext, alıcı online olsa bile ACK gelene kadar Redis RAM kuyruğuna
   alınır. Server-storage AES-GCM zarfı ve blind-index anahtar kullanılır.
5. Aynı `deliveryId` retry'si aynı kayda düşer. Atomik Redis Lua işlemi mevcut
   kaydın skorunu/TTL'ini yenilemez. Her ciphertext ayrı `SETEX` anahtarında
   tutulduğu için aynı alıcının yeni mesajı eski zarfın süresini uzatamaz.
   Farklı hızlı zarflar monoton server-time skoru ile Signal ratchet sırasını
   korur.
6. Alıcı zarfı açar, doğrular ve gerekli kalıcı local database değişikliğini
   tamamlar. Normal mesajda E2EE `DELIVERED` receipt'i de başarıyla gönderilir.
7. Bundan sonra plaintext içermeyen `delivery_transport_ack` sunucuya gider.
   Sunucu yalnız authenticated alıcının kendi blind-index kuyruğundaki tokenı
   silebilir.
8. Gönderen encrypted local outbox kaydını ancak alıcıdan gelen authenticated
   E2EE `DELIVERED`/`READ` kontrolünü açtıktan sonra siler.

Socket'e yazma, FCM/APNs çağrısının başarılı olması veya sunucunun kuyruğa
yazması "cihaza teslim" sayılmaz.

## Saklama ve silme

| Veri | Konum | Varsayılan sınır | Silme |
|---|---|---:|---|
| Signal ciphertext + opak token | Redis tmpfs/RAM, server AEAD | 15 dakika; config sert üst sınırı 1 saat | Alıcının transport ACK'i, hesap silme veya TTL |
| Giden Signal ciphertext outbox | Gönderenin encrypted local database'i | 30 gün | E2EE delivery/read receipt veya süre aşımı |
| İşlenmiş teslim tokenı | Alıcının encrypted local database'i | 30 gün, en fazla 50.000 kayıt | Süre/boyut budaması veya yerel hesap temizliği |
| Generic push wake-up | FCM/APNs | Provider politikası | Mesaj veya ciphertext taşımaz |

Redis için AOF ve RDB kapalı olmalıdır (`appendonly no`, boş `save`), kalıcı
volume bağlanmamalı, swap/core/heap dump engellenmelidir. Hardened server bu
Redis ayarlarını startup'ta okuyamazsa veya doğrulayamazsa fail-closed açılmaz.

## FCM/APNs davranışı

Push yalnız `securechat_wake_v2` türünde genel bir uyandırmadır. Push payload'ı
mesaj metni, Signal ciphertext'i, gönderen, alıcı veya mesaj ID'si taşımaz.
FCM/APNs başarı yanıtı yalnız push sağlayıcısının uyandırma isteğini kabul
ettiğini gösterir; SecureChat mesajının işlendiğini göstermez ve hiçbir ACK'in
yerine geçmez.

## Kesinti davranışı ve bilinçli sınırlamalar

- Alıcı 15 dakikalık server TTL içinde online olursa aynı ciphertext yeniden
  gönderilir. Alıcı dedup kaydı sayesinde Signal ratchet ikinci kez açılmaz;
  gerekli receipt ve transport ACK yeniden gönderilir.
- Server TTL dolarsa sunucuda kopya kalmaz. Gönderen uygulama 30 gün içindeki
  local outbox ile yeniden bağlandığında ciphertext tekrar sunucuya sunulur.
- Alıcı ve gönderen hiçbir zaman tekrar online olmazsa merkezi kalıcı mailbox
  olmadan teslim garanti edilemez. Bu, veri minimizasyonunun bilinçli
  sonucudur.
- 30 gün sonunda E2EE receipt alınmamış local outbox kaydı silinir ve mesaj
  `FAILED` olur. Süresiz cihaz takibi yapılmaz.
- Dosya chunk kuyruğu bu ACK protokolüne dahil değildir. Büyük dosyalar ayrı
  RAM bucket'ında kısa süre tutulur ve mevcut file-transfer retry protokolüne
  bağlıdır.
- Grup kontrolü, SenderKey dağıtımı ve asıl grup mesajı ayrı recipient-specific
  direct Signal zarflarıdır. Hepsi aynı local receipt yaşam döngüsüne bağlanır
  ve server kuyruğunda üretim sırası korunur.

## Değiştirilen bileşenler ve nedenleri

- `lib/src/core/signal_message.dart`: `deliveryId`, server `deliveryToken` ve
  transport ACK codec'i eklendi.
- `lib/src/network/network_resilience.dart`: ciphertext önce encrypted local
  outbox'a yazılıyor; socket başarısında silinmiyor, receipt bekleniyor.
- `lib/src/domain/send_message_use_case.dart`: direct/grup mesaj ve gerekli
  grup kontrol zarfları aynı güvenilir gönderim hattına bağlandı.
- `lib/src/incoming/incoming_message_handler.dart`: kalıcı işlem sonrası ACK,
  encrypted token dedup, başarısız decrypt'te ACK vermeme ve E2EE receipt ile
  outbox temizliği eklendi.
- `lib/src/storage/*`: receipt'e kadar tutulan pending signal alanları ve
  monoton mesaj durum güncellemeleri eklendi.
- `lib/src/backup/backup_service.dart`: aktif outbox ve processed-token
  protokol durumu normal kullanıcı yedeğine alınmıyor; ratchet klonlanmıyor.
- `server_hardened/.../ConnectionManager.kt`: online/offline ciphertext için
  ACK tabanlı RAM kuyruğu, atomik idempotency, sıralama, TTL ve kota eklendi.
- `server_hardened/.../ServerPrivacy.kt`: delivery blind index ve kimlik
  göstermeyen Redis key namespace'leri eklendi.
- `server_hardened/.../WebSocketRoutes.kt`: client token enjeksiyonu
  temizleniyor; transport ACK authenticated socket kimliğine bağlanıyor.

## Doğrulanan güvenlik özellikleri

- Aynı sender/recipient/`deliveryId` tek Redis kaydı üretir ve retry TTL'i
  yenilemez.
- Başka bir hesap tokenı bilse bile alıcının kaydını ACK ile silemez.
- Kuyruk değeri ve Redis key'i recipient/message plaintext'i göstermez.
- ACK öncesi reconnect aynı tokenı yeniden teslim eder; ACK sonrası kayıt
  tamamen silinir.
- Hızlı grup bağımlılıkları ve mesajlar üretim sırasını korur.
- Decrypt/tamper hatası transport ACK üretmez.
- Outbox cihazda şifreli saklanır, E2EE receipt'e kadar korunur ve süreyle
  sınırlandırılır.
