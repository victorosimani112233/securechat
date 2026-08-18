# Server Data Privacy Contract

Bu belge `flutter_securechat/server_hardened` production hedefinin baglayici
veri minimizasyonu sozlesmesidir. Referans olarak korunan kok
`signaling-server` ve `bot-api` bu garantiyi vermez; production deployment
yalniz hardened hedefi veya ayni kontrolleri kanitlanmis bir esdegeri
kullanabilir.

Son dogrulama: 2026-08-14. E2EE mesaj icerigini korur, fakat trafik iliskisini,
zamanlamayi ve endpoint IP'sini kendiliginden gizlemez. Bu nedenle "ciphertext
ise sinirsiz saklanabilir" yaklasimi kesinlikle kabul edilmez.

## Degistirilemez ilkeler

1. Sunucu mesaj gecmisi, rehber, profil, medya veya davranis analitigi deposu
   degildir.
2. Mesaj, medya, grup adi, dosya adi, caption, kisi adi ve private Signal key
   plaintext olarak sunucu persistence katmanina yazilmaz.
3. Offline teslim yalniz client-E2EE zarfina uygulanir; zarf Redis'te ayrica
   server-storage AEAD ile sarilir, opaque key altinda kisa TTL ile tutulur ve
   basarili socket gonderiminden sonra silinir.
4. Saklama veya privacy migration katmani calismiyorsa servis fail-closed
   baslar/yanit verir. DB/Redis hatasinda cache-only hesap, plaintext fallback
   veya eski zayif kayda geri donus yoktur.
5. HMAC indeks, AEAD, JWT, bot ve push anahtarlari birbirinden bagimsizdir.
   Anahtarlar DB'de, image'da veya mobil istemcide tutulmaz.
6. Hesap silme PostgreSQL, Redis, process cache, push ve bot session kopyalarini
   kapsar. Yalniz `users` satirini silmek yeterli sayilmaz.
7. Log ve metric verisi de hassastir. Raw UUID, e-posta, telefon, IP, token,
   envelope, grup/dosya adi ve exception request icerigi loglanmaz. Security
   eventleri kalici audit satiri yerine yalniz event-turu bazli process-RAM
   sayaci artirir.

## Kalici ve gecici veri sozlesmesi

| Veri | Neden zorunlu | Sunucudaki bicim | Varsayilan / sert ust sinir | Silme |
|---|---|---|---|---|
| Hesap kimligi | JWT subject ve prekey adresleme | Rastgele UUID; V13 ile telefon yerine finalized blind-RSA OPRF directory tokeni + public key ID | Hesap omru | Kalici hesap silmede transaction icinde |
| E-posta OTP | Kayit sahipligi | Redis key'i e-posta HMAC blind index'i; deger OTP+adres bagli HMAC | 10 dk / 10 dk, 5 deneme | Basarida veya limitte hemen |
| Public Signal materyali | Yeni E2EE session kurma | Identity public key, tek aktif signed prekey ve kullanilmamis one-time public prekey | Aktif key | One-time prekey atomik teslimde hemen silinir; digerleri rotate/hesap silme |
| Offline mesaj | Kisa sureli offline teslim | Client Signal ciphertext'i + server AES-GCM; recipient HMAC key; yalniz persistence-kapali Redis RAM | 15 dk / 1 saat | Gonderim ACK-sonrasi silme veya TTL |
| Offline dosya parcasi | Kesintili file transfer | Client ciphertext + server AES-GCM; ayri opaque RAM bucket | 5 dk / 15 dk | Gonderim ACK-sonrasi silme veya TTL |
| Presence/call state | Canli route | Presence process RAM; 1:1 call key'i opaque Redis; grup call state'i yalniz process RAM | Oturum; 1:1 call 5 dk; grup call sert ust sinir 4 saat | Disconnect/hangup/hesap silme/TTL |
| Sohbet kontrol olaylari | Edit/delete/reaction/pin/receipt/typing/timer senkronu | Sunucu yalniz ordinary direct Signal ciphertext gorur; kontrol turu ve alanlari sabit 16 KiB `CHATCTRL:v2` paketinin icindedir | Offline mesaj zarfiyla ayni en fazla 15 dk / 1 saat RAM TTL | ACK sonrasi veya TTL; plaintext frame reddedilir |
| Grup sosyal grafigi | Sunucu icin zorunlu degil | **Tutulmaz**; `group_members` V9 ile drop edilir | Yok | Migration aninda fiziksel tablo silme |
| Push token | Kapali istemciyi generic wake ile uyandirma | User HMAC blind index + AAD-bagli AES-256-GCM `v4` token; yalniz gun-duzeyi `registered_on`; V14 final tabloda raw UUID kolonu yok | 30 gun / 90 gun | Logout, rotate, hesap silme veya retention |
| Abuse sayaci | Brute-force/operasyon sinyali | Yalniz event turu -> toplam sayi; kimlik, IP, metadata ve timestamp yok; process RAM | Process omru | Restart |
| Bot outbound/idempotency | Retry ve duplicate engeli | Blind-index Redis key; AEAD zarf; yalniz persistence-kapali Redis RAM | 15 dk / 1 saat | Drain/release veya TTL |
| Bot API credential/policy | Ed25519 istemci auth ve alici yetkisi | Rastgele `kid`, public key, limit/expiry/revocation; gorunen ad ve allow-list `BOT_MASTER_KEY` AEAD zarfindadir; positive RAM cache yoktur, her istekte DB revoke/expiry kontrolu yapilir | Aktif credential; expired/revoked sonrasi 30 gun / 90 gun | Admin revoke/rotation veya zorunlu retention transaction'i |
| Bot identity/prekey | Botun Signal katilimcisi olmasi | Public keyler acik; private identity ve prekeyler `BOT_MASTER_KEY` AEAD zarfindadir | Aktif bot identity/key omru; consumed OTPK 1 saat varsayilan | Rotate, consume retention veya bot kaldirma |
| Bot Signal session | Bot E2EE ratchet devamligi | Recipient blind index + `BOT_MASTER_KEY` AEAD record; V14 final tabloda raw recipient kolonu yok | Aktif session | Recipient hesap silme veya session reset |
| TURN credential | Kisa omurlu medya relay auth | HMAC pseudonymli username | 10 dk / 1 saat | Dogal expiry |

`users.registered_at`, `users.last_seen_at`, tarihsel `group_members.joined_at`,
`api_client.last_used_at` ve `bot_signal_session.updated_at` V8 ile
kaldirilmistir. Ortak uygulama anahtariyla acilabilen `encrypted_phone` V6 ile
kaldirilmistir. V7'nin gecis donemindeki encrypted/blind-index grup dizini de
"ciphertext sosyal grafik yine sosyal grafiktir" karariyla V9'da tamamen
silinmistir. V10 pseudonymous olsa bile davranis zaman cizelgesi uretebilen
`audit_log` tablosunu silmistir. Yeni runtime grup uyeligini veya security event
satirlarini PostgreSQL/Redis'e yazmaz.
V11 user one-time prekey'ini `DELETE ... RETURNING` ile atomik teslim eder ve
`consumed_at`/`created_at` timeline kolonlarini kaldirir.
V12 push token retention'i icin exact `updated_at` yerine gun-duzeyi
`registered_on` tutar.
V13 tahmin edilebilir telefon SHA-256/HMAC discovery kolonunu private-directory
OPRF tokeni ve ayri key ID semasina tasir; legacy hesap yalniz kendi
authenticated cihazindan yeniden indekslenir.
V14 gecis icin birakilmis nullable `fcm_tokens.user_id` ve
`bot_signal_session.recipient_user_id` kolonlarini fiziksel olarak siler.
Migration private-v4/opaque donusumu tamamlanmamis tek satir gorurse veri
silmek veya zayif fallback yapmak yerine fail-closed durur. Final schema testi
izinli tablo ve kritik kolon setini birebir kilitler.

## Telefon ve rehber kesfi

Mobil istemci normalize telefonlari cihazda SHA-256 yapar, her girdiyi 3072-bit
blind-RSA OPRF public key'iyle rastgele korur, gercek ve cover girdilerini
karistirir ve authenticated her istegi tam 256 grup elemanina doldurur. Server
adres-defteri hash'lerini veya bir batch icindeki gercek kisi sayisini gormez.
Tum istemciler ayni token-label + token-AEAD sealed user-ID snapshot'ini alir;
yalniz eslesen tokeni cihazda ureten istemci label'i bulup kimligi acabilir.
Eslesme sonucu ve gorunen ad/telefon yalniz encrypted local database'e yazilir;
caller-contact sosyal grafigi server DB/Redis/cache'inde tutulmaz.

Server yine authenticated sorgu zamanini, kaynak IP'yi ve kac adet 256'lik
batch istendigini gorur. Kayit ve legacy self-migration sirasinda yalniz hesap
sahibinin kendi telefon hash'i transient olarak islenir; adres defteri degildir,
loglanmaz ve finalized token disinda saklanmaz. DB kopyasi OPRF private key
olmadan telefon sozluk saldirisina acik degildir; fakat DB ile export edilebilir
OPRF key'inin veya PKCS#8 kullanan tum host runtime'in birlikte ele gecirilmesi
bu korumayi kaldirir. Production key'i bu nedenle PKCS#11 backend ile ayri,
export edilemeyen ve rate-limited HSM/KMS sinirinda kalmalidir. Bu protokol
trafik anonimligi veya kotu niyetli
sunucuya karsi tam PSI iddiasi degildir.

## Wire ve push metadata politikasi

- Direct mesaj icerigi Signal V3 ciphertext'tir; encrypt/session/prekey hatasi
  mesaji `FAILED` yapar, plaintext gondermez.
- Grup icerigi SenderKey ile sifrelenir; bunun group ID/token tasiyan ic zarfi
  `GROUPROUTE:v3` payload'i olarak her alicinin ayri direct Signal session'i
  icinde yeniden sarilir. Server yalniz ordinary `encrypted_message` gorur;
  sabit grup tokeni ve tek frame'de tam recipient listesi gorup saklayamaz.
  Linkable `group_message_fanout` production'da reddedilir.
- Grup dosyasi `flutter-file-v3-group` ile ayni recipient-specific direct route
  sarmasini kullanir. Ad, MIME, caption ve gercek boyut authenticated encrypted
  private manifest icindedir; wire boyutu yalniz chunk-aligned ust sinirdir.
  Partial metadata da cihazda AEAD ile saklanir.
- Grup aramasi her arama icin yeni 256-bit routing nonce uretir. Gercek group ID
  ve isim recipient-specific private control icindedir; invite `participants`
  listesini bos tasir. Server nonce'u yalniz aktif call RAM state'inde tutar.
- Mesaj edit/delete/reaction/pin, delivery/read receipt, typing ve disappearing
  timer olaylari `CHATCTRL:v2` ile kimlige bagli direct Signal ciphertext icine
  alinir. Ic JSON rastgele doldurulan sabit 16 KiB pakettir; sunucu kontrol
  turunu, message ID'yi, emoji'yi, yeni metni veya timer suresini zarf boyundan
  ayiramaz. Hardened server eski plaintext kontrol discriminator'larini
  fail-closed reddeder. Alici de raw legacy kontrol frame'ini uygulamaz; control
  yalniz authenticated decrypt yolundan gelebilir.
- Admin export audit'inin dis `eventType` alani yalniz `PRIVATE_EVENT` tasir;
  gercek olay turu sadece ilgili admin cihazinin acabildigi payload icindedir.
- FCM/APNs saglayicisina yalniz `type=securechat_wake_v2` gider. Sender,
  recipient, message type, metin, zaman ve grup bilgisi push payload'inda yoktur.

## Hesap silme ve retention

Authenticated hesap silme once tek PostgreSQL transaction'inda private push
indeksini, bot recipient session'ini ve account/cascade prekey kayitlarini
siler. Commit sonrasinda FCM
RAM cache, user registry, token revocation, socket, presence, aktif call ve iki
offline Redis bucket temizlenir. Silme basarisizsa istemci yerel hesabi silmez;
retry yapabilmesi icin fail-closed kalir.

Retention worker listener acilmadan once zorunlu cleanup transaction'i
calistirir, sonra 6 saatte bir consumed bot prekey, stale push ve retention
suresini asmis expired/revoked bot API credential satirlarini temizler.
Periyodik cleanup bozulursa privacy health kapanir, aktif
socket'ler kapatilir, HTTP/WS trafik 503/retry-later ile reddedilir ve worker
her dakika yeniden dener. Yalniz tam transaction basarisi trafigi tekrar acar.
Redis TTL silmenin ust siniridir; basarili teslim daha erken siler. Startup
`appendonly=no` ve bos RDB `save` schedule'ini dogrular; AOF/RDB aciksa veya
CONFIG sonucu okunamiyorsa signaling ve bot listener'lari fail-closed acilmaz.
Redis volume/snapshot ve host memory dump'i deployment tarafinda da yasak
olmalidir. PostgreSQL backup politikasi tablodaki retention'i asamaz. Silinen
hesabi eski backup'tan geri getiren restore production'a uygulanamaz.

## Tehdit modeli siniri

Asagidaki metadata mevcut mimaride canli route icin sunucu process'i tarafindan
gorulebilir:

- kaynak IP, baglanti zamani ve trafik hacmi;
- canli sender/recipient route iliskisi ve socket presence;
- ayni kullanicinin kisa zaman araliginda iletisim kurdugu sender/recipient
  ciftleri (ayri direct zarflar grup oldugunu acikca isaretlemez, fakat trafik
  korelasyonu yine tahmin uretebilir);
- genel mesaj/dosya packet boyutu, tum paketlerin zamanlamasi ve TURN/Janus
  medya endpoint iliskisi (chat-control paketleri kendi aralarinda sabit
  boyutludur, fakat trafik zamani ve sender/recipient route'u gorunur);
- push saglayicisinda cihaz tokeni ile generic wake zamanlamasi.
- private discovery isteginin zamani ve 256'lik batch sayisi; batch icindeki
  gercek rehber girdileri ve eslesme sonucu gorulmez.

DB-only ihlali blind index ve AEAD ile sinirlanir; tam host/runtime ihlalinde
anahtarlar ve canli metadata erisilebilir. Trafik analizi direnci icin sealed
sender, sabit boyutlu padding/batching, capability tabanli grup auth,
oblivious relay/mixnet ve PSI gibi protokoller gerekir. Bunlar mevcut Signal V3
wire'ina sessizce eklenemez ve bu belgede varmis gibi iddia edilmez.

## Production release kapisi

- Yalniz `server_hardened` artefakti deploy edilir.
- Root `infra/docker-compose.yml` kalici Redis/log volume'u tasidigi icin
  production'da yasaktir. Yalniz `server_hardened/deploy` hedefi ve varsayilan
  salt-okunur preflight kullanilir.
- Signaling ve bot binary'si `PRIVACY_PRODUCTION_MODE=true`, PostgreSQL
  `sslmode=verify-full`, credential-free JDBC URL ve plaintext queue reddini
  compose'dan bagimsiz olarak listener oncesi dogrular.
- `PRIVACY_INDEX_KEY`, `OFFLINE_QUEUE_ENCRYPTION_KEY`,
  `FCM_TOKEN_ENCRYPTION_KEY`,
  `BOT_MASTER_KEY` ve `BOT_QUEUE_ENCRYPTION_KEY` bagimsiz 32-byte secret'lardir.
- `DIRECTORY_OPRF_PRIVATE_KEY` ayri amacli en az 3072-bit RSA key'dir; mobil
  bundle'a/DB backup'a girmez ve key ID rotation runbook'u olmadan degistirilmez.
- JWT, SMTP TLS, TURN, metrics bearer, PostgreSQL ve Redis zorunludur; eksiginde
  listener acilmaz.
- `ALLOW_LEGACY_PLAINTEXT_QUEUE` production'da false/eksik olmalidir.
- `API_CLIENT_RETENTION_DAYS` varsayilan 30, sert ust sinir 90 gundur;
  expired/revoked policy satirlari bu siniri asamaz.
- Flyway V1-V14 (V9 persistent grup grafigini, V10 behavioral audit tablosunu,
  V11 user-prekey kullanim timeline'ini siler; V12 push zamanini gun bucket'ina
  indirir; V13 private directory token semasini kurar; V14 raw-UUID legacy
  kolonlarini donusum tamamlanmadan kaldirmayi reddeder ve sonra fiziksel olarak
  siler), bot process'inden once signaling process'iyle tamamlanir. Backup
  alinmadan migration yapilmaz.
- Kalici uygulama logu ve log aggregation yasaktir. Fixed ERROR console cikisi
  production Docker `logging=none` ile atilir; core/heap/error dump ve JVM
  attach kapali, Redis yalniz volume'suz tmpfs'tir. DB backup, FCM service
  account ve secret manager erisimleri en az yetki ve ayni retention
  politikasina tabidir.
- Tum secret'lar group/world izni olmayan read-only `NAME_FILE` girdileridir;
  iki amac icin ayni materyal startup ve deploy preflight'ta reddedilir.
- Redis, signaling ve bot image referanslarinin her biri immutable registry
  `image@sha256` digest'i olmadan preflight gecmez.
- Statik gizlilik kapisi, Kotlin unit testleri ve gercek PostgreSQL Testcontainers
  integration testleri yesil olmadan release uretilmez.

Son kanit: `flutter analyze`, 194/194 Flutter testi, statik privacy gate'leri,
`assembleRelease --offline` (663 gorev), stripped/server-secret audited AAB ve hardened 64/64
`:signaling-server:test :bot-api:test --offline` (sifir skip) basarilidir. Bu kod hedefinin
kanitidir; production secret, migration, backup ve altyapi politikasinin gercek
deployment'ta ayrica dogrulanmasi gerekir.
