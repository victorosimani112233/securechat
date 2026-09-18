# Server Hardening Progress — SERVER_REVIEW_2026-08-18 kapanisi

Bu dosya `SERVER_REVIEW_2026-08-18.md` raporundaki bulgularin kapanis durumunu
tutar. Hedef `flutter_securechat/server_hardened`; kok `signaling-server` ve
`bot-api` davranis referansidir ve degistirilmez.

Kural: bir satir ancak (1) bulgu kaynak kodda dogrulandiginda, (2) once
basarisiz olan bir test yazildiginda, (3) fix sonrasi o test ve tam offline
paket yesil oldugunda `DONE` olur. Urun karari veya dis altyapi gerektiren
kalemler `EXTERNAL` isaretlenir ve gerekcesi yazilir.

## 2026-09-17 — Gizlilik oncelikli guvenilir mesaj teslimi

- `encrypted_message`, alici online olsa bile kalici cihaz-isleme ACK'i gelene
  kadar persistence-kapali Redis RAM'de tutulur. Socket write ve FCM/APNs
  kabul yaniti teslim sayilmaz.
- Client 256-bit `deliveryId` uretir; server sender+recipient+ID HMAC'inden
  opak `deliveryToken` turetir. Client token enjeksiyonu temizlenir ve ACK
  authenticated alici hesabina baglanir.
- Redis Lua adimi enqueue/idempotency/siralama/TTL'yi atomik uygular. Retry
  mevcut kaydin TTL'ini yenilemez; ciphertext basina ayri `SETEX`, ayni
  alicinin yeni trafiginin eski zarfi uzatmasini engeller. Hizli grup
  kontrolu, SenderKey ve mesaj zarflari Signal ratchet sirasini korur.
- Gonderen ciphertext'i socket'ten once encrypted local outbox'a yazar ve
  yalniz E2EE `DELIVERED`/`READ` receipt ile siler. Alici processed-token
  dedup kaydini receipt ag cagrısından once kalici yazar; reconnect replay'i
  ratchet'i ikinci kez ilerletmez.
- Server retention varsayilan 15 dakika, sert ust sinir 1 saattir; client
  outbox ve dedup 30 gunle sinirlidir. PostgreSQL mailbox eklenmedi.
- Dis Redis AES-GCM zarfi server anahtariyla acilabilir; ic Signal ciphertext
  cihaz private key'leri olmadan acilamaz. Trafik metadatasi ve TOFU ilk-temas
  siniri `PRIVACY_FIRST_RELIABLE_DELIVERY.md` icinde aciklanir.

Kanit: 420/420 Flutter testi, tam `:signaling-server:test`, temiz
`flutter analyze`, iOS readiness ve Codemagic privacy audit PASS. Redis
entegrasyon testleri idempotency, TTL yenilememe, sira, yanlis-hesap ACK'i,
hesap silme temizligi ve ACK oncesi reconnect replay'ini kapsar.

## P0 — release blocklayicilari

| ID | Konu | Durum | Not |
|---|---|---|---|
| P0-01 | Canli artefakt/route dogrulanamiyor | DONE (kod) | Build manifest image'a gomulur, operator-only `/api/v1/version`; canli probe operator kapisi |
| P0-02 | Telefon first-claim impersonation | EXTERNAL | Grant tuketimi kalici+atomik yapildi; sahiplik kaniti urun karari — `SERVER_DIRECTORY_IDENTITY.md` |
| P0-03 | RAM-only Redis auth state | DONE | Credential epoch/generation PostgreSQL'de; emergency stop durable |
| P0-04 | Hesap silme atomik degil | DONE | Idempotent silme; yalitilmis, tekrarlanabilir temizlik adimlari |
| P0-05 | Janus SFU medya E2EE sinirinda degil | PARTIAL | Sunucu yarisi tamam (yetenek-kapili promosyon, katilimci tavani, rastgele room ID); istemci yarisi `SFU_MEDIA_E2EE.md` |
| P0-06 | Bot shared JWT signing secret | DONE | Ed25519 scoped servis assertion; bot artik JWT_SECRET tasimaz |
| P0-07 | Fresh V14 bot bootstrap semayla uyumsuz | DONE | Reconcile state machine; 5 yeni Testcontainers testi |
| P0-08 | Hardened compose egress yolu yok | DONE (kod+konfig) | Internal/egress ayrimi + proxy referansi; firewall allow-list operator isi |
| P0-09 | Bot public/admin listener erisilemez | DONE | JDK Unix domain socket koprusu, 0600; compose bind mount |
| P0-10 | Bot grup allow-list alici yetkilendirmiyor | DONE | Her alici ayrica izinli olmali; per-recipient random outer ID |
| P0-11 | Bot Signal identity dogrulamasi her anahtari guveniyor | DONE | Kalici TOFU pin; rotasyon operator onayi ister |
| P0-12 | WS query token credential sizdirir | DONE | Query token fail-closed + proxy referans konfigurasyonu |

## Cutover checklist — hardened'a gecis gunu

Bu bolum, sertlestirmelerin bilincli fail-closed sonuclarini toplar. Hicbiri
hata degildir; hepsi gecis gunu once yapilmasi gereken islerdir.

Su an yayindaki sunucu hardened **degil** (2026-08-17 probe: `directory/config`
404). Yani asagidakiler ancak hardened deploy edildiginde devreye girer ve
mevcut test dalgasini etkilemez.

### 1. Tum kullanicilar bir kez yeniden giris yapar

`users.credential_epoch` her token'in icine gomulur (V15). Eski token'larda
`epc` claim'i olmadigi icin hem access hem refresh dogrulamasi duser. Bu tek
seferliktir ve gizlilik/guvenlik acisindan dogru davranistir: iptal edilmis
credential'in Redis kaybiyla geri gelmesi bu sayede imkansiz.

Planlama: cutover'i kullanicilarin yeniden giris yapabilecegi bir zamana
koyun; OTP/SMTP yolunun calistigini once dogrulayin.

### 2. Migration sirasi

V14 -> V15 -> V16 -> V17 -> V18. Backup alinmadan uygulanmaz.

| Surum | Icerik |
|---|---|
| V15 | `users.credential_epoch`, `users.refresh_generation` |
| V16 | `bot_control` (durable emergency stop) |
| V17 | `bot_peer_identity` (TOFU pin) |
| V18 | `registration_grant_use` (tek kullanimlik grant) |

### 3. Yeni zorunlu secret ve env

| Girdi | Nerede | Not |
|---|---|---|
| `BOT_SERVICE_PRIVATE_KEY_FILE` | bot-api | Ed25519 PKCS#8, base64 |
| `BOT_SERVICE_PUBLIC_KEY_FILE` | signaling | Ayni ciftin X.509 public'i |
| `BOT_SOCKET_DIR` | compose | Host'ta `10002:10002`, mode `0700` |
| `SOURCE_COMMIT` | build | Tam 40-hex; eksikse production baslamaz |
| `SFU_ENABLED` / `SFU_MEDIA_BOUNDARY_ACK` | signaling | SFU acilacaksa ikisi de |

Bota `jwt_secret` **artik verilmez**; compose'dan kaldirildi ve statik kapi
geri eklenmesini engeller.

Anahtar cifti uretimi:

```bash
umask 077
openssl genpkey -algorithm ed25519 -outform DER | base64 -w0 > bot-service.key.b64
base64 -d bot-service.key.b64 | openssl pkey -inform DER -pubout -outform DER \
  | base64 -w0 > bot-service.pub.b64
```

Deploy preflight, openssl varsa iki dosyanin ayni cifte ait oldugunu dogrular.

### 4. Davranis degisiklikleri

- **SFU varsayilan kapali.** Grup aramalari mesh'te kalir; pratik tavan
  yaklasik 5-6 goruntulu, 10-12 sesli katilimci. Acmak icin bolum 3'teki iki
  degisken gerekir ve medya, Janus'ta uygulama katmaninda sifresizdir.
- **WS query token reddedilir.** Flutter istemcisi zaten `Authorization`
  header kullaniyor; bot da gecirildi. Reverse proxy `Authorization`
  header'ini upgrade istegi boyunca iletmelidir, aksi halde hicbir istemci
  baglanamaz — `deploy/reverse-proxy.conf` referans alinmali.
- **Bot public/admin yuzu yalniz Unix socket.** Host CLI socket dosyasina
  erisir; ag uzerinden erisim yoktur.
- **Bot grup gonderimi** her alicinin ayrica `user:<uuid>` allow-list'inde
  olmasini ister. Mevcut bot client policy'leri buna gore guncellenmeli.
- **Bot alici identity pini.** Bir alicinin identity key'i degisirse gonderim
  fail-closed durur; `POST /admin/identity/approve-rotation` ile onaylanir.

### 5. Ag topolojisi

`securechat-internal` (egress yok) + `securechat-egress` (yalniz signaling ve
bot). Redis egress agina baglanmaz. Host firewall egress'i
`deploy/README.md`'deki hedef listesiyle sinirlamalidir.

### 6. Gecis sonrasi dogrulama

- `GET /api/v1/version` (metrics bearer) canli commit'i doner; release
  kaydiyla birebir esletin.
- `GET /api/v1/directory/config` 200 donmeli — 404 ise yine eski artefakt
  calisiyordur.
- Bot socket'ine host CLI'dan erisin; ag uzerinden erisilemedigini dogrulayin.

## P1 — durum

| ID | Konu | Durum |
|---|---|---|
| P1-02 | Rate limiter atomik degil | DONE — tek Lua adimi, benzersiz member |
| P1-03 | OTP verify/cooldown atomik degil | DONE — tek verify/consume Lua state machine'i + atomik cooldown |
| P1-04 | Refresh rotation atomik degil | DONE — P0-03 ile compare-and-set |
| P1-07 | Prekey bundle uc ayri transaction | DONE — tek transaction + `FOR UPDATE` |
| P1-13 | Grup arama concurrency | DONE — P0-05 ile immutable participants + cap |
| P1-14 | String interpolation JSON | KISMI — bot tarafi P0-10'da; signaling call/ACK acik |
| P1-16 | Flyway validation kapali | DONE — `validateOnMigrate` acik + beklenen surum kontrolu |
| P1-05 | Trusted proxy sinirI yok | DONE — `ClientAddress`, literal-IP + CIDR |
| P1-06 | Global body limiti yok | DONE — sinirli okuma + prekey alan sinirlari |
| P1-08 | Alici UUID/hesap dogrulanmiyor | DONE — registry kontrolu, bilinmeyen alici reddedilir |
| P1-09 | Presence aboneligi sinirsiz | DONE — hesap kontrolu, tavan, rate limit, bos anahtar temizligi |
| P1-15 | Byte kotasi karakter sayiyor | DONE — UTF-8 frame boyutu |
| P1-18 | Bot kuyrugu gonderimden once siliyor, ACK yok | DONE — in-flight + gorunurluk suresi + gercek server ACK |
| P1-20 | Es zamanli ratchet yazimi | DONE — alici basina serilestirme + compare-and-set |
| P1-01 | WS reconnect yarisi | DONE — compare-and-remove + kilit icinde kapasite |
| P1-10 | FCM init hatasi yutuluyor | DONE — hata raporlanir, health gercek durumu doner |
| P1-11 | APNs config yok | DONE — explicit APNs background/content-available |
| P1-12 | Janus pending sizintisi, cift reconnect, keepalive yok | DONE — finally temizligi, tek reconnect sahibi, 30 sn keepalive |
| P1-14 | String interpolation JSON | DONE — tum sunucu cerceveleri typed |
| P1-17 | Fanout idempotency | DONE — alici bazinda kalici ilerleme |
| P1-21 | Bot readiness | DONE — `/ready`: identity, signaling, kuyruk derinligi |
| P1-22 | Compose kaynak limiti yok | DONE — mem/cpu limiti + MaxRAMPercentage |
| P1-25 | Build testsiz image uretebiliyor | DONE — build once testleri calistirir; statik kapi zorunlu kilar |
| P1-19 | Bot WS reconnect yarisi | DONE — drain kilidi + tam-soket kontrolu |
| P1-23 | Secret ownership runtime'da kontrol edilmiyor | DONE — grup/diger izinli secret reddedilir |
| P1-24 | Audit sayaclari metrics'e bagli degil | DONE — kimliksiz sayaclar bearer korumali metrics'te |

## P2 — durum

| ID | Konu | Durum |
|---|---|---|
| P2-03 | `/health` ayrinti sizdiriyor | DONE — liveness/readiness ayrildi, readiness operator-only |
| P2-04 | SFU room endpoint yalniz auth istiyor | DONE — aktif cagri katilimcisi zorunlu |
| P2-06 | Admin rotate atomik degil | DONE — once create, sonra revoke |
| P2-07 | Admin girdi sinirlari yok | DONE — ad, allow-list, kota ve expiry sinirlari |
| P2-08 | Idempotency NX/GET yarisi | DONE — bos okumada yeniden NX |
| P2-09 | Nonce, body hash'ten once tuketiliyor | DONE — sira ters cevrildi |
| P2-10 | FCM rate map ham UUID + eviction yok | DONE — blind index + periyodik budama |
| P2-12 | Dokuman/kod TTL uyusmazligi | DONE |
| P2-15 | "ACK" olmayan seye ACK deniyor | DONE — P1-18 ile gercek ACK geldi |
| P2-01 | Snapshot O(N), kullanici sayisini aciyor | DONE — 256'lik kova dolgusu + uyelik surumlu onbellek |
| P2-02 | OPRF kotasi enumeration'a acik | DONE — PostgreSQL'de kalici gunluk kota |
| P2-05 | TURN `turns:`/TLS ve rotation yok | DONE — production'da yalniz `turns:`, sir restart'siz yenilenir |
| P2-13 | SCA/SBOM CI kaniti yok | DONE — offline CycloneDX SBOM + advisory kapisi |
| P2-11 | Hesap kurtarma akisi yok | KARAR BEKLIYOR — urun karari |
| P2-14 | Gradle 9 deprecation | ENGELLI — offline cache'te `junit-platform-launcher:1.10.2` yok |

## Calisma gunlugu

### P0-07 — fresh V1-V14 bot bootstrap

Dogrulanan kok neden:

- `V13__private_contact_directory.sql:7` `users.phone_hash` kolonunu
  `directory_token` olarak yeniden adlandirir.
- `BotIdentityBootstrap.firstRun()` halen `INSERT INTO users(user_id,
  phone_hash, ...)` calistirir. Temiz V1-V14 semasinda bu ifade
  `column "phone_hash" of relation "users" does not exist` ile patlar,
  transaction rollback olur ve bot listener acilmaz.
- Ikinci kirilma ayni fonksiyondadir: identity + `bot_identity` tek
  transaction'da commit edilir, fakat local prekey persistence ve remote
  bundle upload commit'ten sonra ayri adimlardadir. `loadExisting()` yalniz
  `bot_identity` satirina baktigi icin commit sonrasi herhangi bir hata
  kalici yarim-state birakir; restart bunu "zaten kayitli" sayip onarmaz.
- `BotIdentity.set(...)` upload'dan once cagrildigi icin yayinlanmamis bir bot
  hazir kabul edilir.

Korunacak dogru davranis: `UserRegistry.privateDirectorySnapshot()` yalniz
aktif `directory_key_id` tasiyan satirlari yayinlar; servis hesabi NULL key id
ile girdiginden rehber snapshot'ina sizmaz.

Uygulanan cozum:

- `BotBundlePublisher` ile remote yayin siniri arayuz haline getirildi;
  `HttpBundlePublisher` authenticated `POST /api/v1/prekeys/upload` yolunu
  korur. Bot prekey tablolarina dogrudan yazmaz.
- `BotIdentityBootstrap` her acilista calisan reconcile adimi oldu. Hesap,
  local prekey havuzu ve yayin durumu ayri ayri dogrulanir; `BotIdentity`
  yalniz ucu de tamamlaninca hazir isaretlenir.
- `users` satiri artik yalnizca `user_id` + `directory_token` +
  `directory_key_id` ile acilir. `identity_public_key`/`registration_id`
  alanlarini sadece authenticated yayin yolu doldurdugu icin "yayinlandi mi"
  sorusu botun kendi yazdigi satirdan uydurulamaz.
- Servis hesabi ayrilmis `service:` namespace'ini kullanir. OPRF tokenlari
  url-safe base64 oldugu ve `:` icermedigi icin cakisma yapisal olarak
  imkansizdir.
- One-time prekey yeniden yayini engellendi: yayinlanmis havuzda bulunmayan
  bir local anahtar bir peer tarafindan atomik olarak cekilmis demektir ve
  local'de de tuketilmis isaretlenir. Yeni anahtarlar iki havuzun tepe
  degerinin ustunden numaralanir; retention biri budasa bile id geri sarmaz.
- Baglanti icinde ikinci baglanti alinmasi kaldirildi (havuz tukenmesi riski).

Kanit: `BotIdentityBootstrapIntegrationTest` (gercek PostgreSQL 16, V1-V14) —
publish hatasinda hazir olmama, restart'ta ikinci identity uretmeden
tamamlama, tam saglikli botun yeniden yayin yapmamasi, servis namespace'i ve
peer-consumed anahtarin yeniden yayinlanmamasi. Mutasyon dogrulamasi: kolon
adi `phone_hash`'e geri alindiginda 5/5 test duser.

Taban: `:signaling-server:test :bot-api:test --offline` 69 test, 0 failure,
0 error, 0 skip (onceki taban 64).

### P0-12 — WebSocket query token

Dogrulanan kok neden:

- `WebSocketRoutes.kt` handshake'te once `queryParameters["token"]`, sonra
  `Authorization` header'ini kabul ediyordu.
- `SignalingWsClient.reconnectLoop()` bot access JWT'sini dogrudan URL
  query'sine yaziyordu.
- Hardened deploy hedefinde reverse proxy konfigurasyonu yok; container
  `logging=none` host proxy access logunu korumaz.

Uygulanan cozum:

- `WebSocketCredentials` sinirina tasindi. Query'de token gorulmesi sessizce
  yok sayilmaz: o token artik loglanmis kabul edilir ve baglanti
  `WS_AUTH_TOKEN_IN_QUERY` sayaciyla fail-closed reddedilir. Boylece bir
  istemci regresyonu sessizce credential sizdirmaya devam edemez.
- Header + query birlikte gelse bile reddedilir; header'a dusmek sizintiyi
  gorunmez kilardi.
- Bot istemcisi `Authorization: Bearer` header'ina gecti.
- Flutter istemcisi zaten header kullaniyor (`signaling_service.dart:264`);
  uygulama kontrati degismedi.

Kanit: `WebSocketCredentialsTest` (4 test). Taban 73 test, 0 failure/skip.

Kalan: hardened reverse proxy referans konfigurasyonu — Authorization
header'inin upgrade istegi boyunca korunmasi, access log kapatma/redaksiyon ve
`token=` query'sinin proxy seviyesinde reddi. P0-08 ile ayni dosya setinde.

### P0-06 — bot shared JWT signing secret

Dogrulanan kok neden:

- `BotApiConfig.load()` signaling ile ayni `JWT_SECRET`'i yukluyordu.
- `BotJwtMinter.issueAccessToken(userId)` verilen herhangi bir subject icin
  gecerli bir normal access token uretiyordu; uc cagri yeri vardi (prekey
  upload, prekey fetch, WS connect).
- Sonuc: bot container ihlali butun kullanicilarin taklit edilmesi demekti.
- Hardened compose bot servisine `jwt_secret` mount ediyordu.

Uygulanan cozum:

- Imza materyali asimetrik yapildi. Bot kendi Ed25519 private key'iyle
  imzalar; signaling yalniz public key tutar. Signaling ihlali servis
  assertion'i uretemez, bot ihlali yalniz botun kendi kimligini verir.
- `ServiceAssertion` kompakt bicimi `sc1.<b64url(payload)>.<b64url(imza)>`;
  JWT kutuphanesi kullanilmaz, dogrulama JDK 17 native Ed25519'dur.
- Yetki daraltildi: `prekey.upload`, `prekey.fetch`, `ws.connect`. Assertion
  baska hicbir route'ta gecerli degil; `requireAuth` varsayilani yalniz
  kullanici token'i kabul eder.
- Assertion omru en fazla 120 sn; `exp - iat` ust siniri asilirsa reddedilir,
  yani kalici bir credential uretilemez.
- `sub`, `bot_identity.bot_user_id` ile eslesmek zorunda. Gecerli imzali bir
  assertion baska bir UUID adina kullanilamaz.
- `BOT_SERVICE_PUBLIC_KEY` verilmezse servis kimligi tamamen kapali; kullanici
  trafigi etkilenmez, bot fail-closed calisamaz.
- Bot'tan `com.auth0:java-jwt` bagimliligi kaldirildi: process artik token
  mint edebilecek bir kutuphane tasimiyor.
- Compose: bota `jwt_secret` verilmiyor; yerine `bot_service_private_key`,
  signaling'e `bot_service_public_key` mount ediliyor.
- Deploy preflight iki dosyayi da zorunlu kilar ve openssl varsa private
  key'den turetilen public key ile konfigure edileni karsilastirir.

Kanit: `ServiceAssertionTest` (8 senaryo: yanlis anahtar, scope degistirme,
expired, omur tavani, gelecek tarihli, payload kurcalama, bozuk zarf, UUID
olmayan subject), `BotServiceTokenMinterTest`, `ServiceKeyFormatTest` (gercek
openssl anahtar cifti ile uctan uca). Statik kapi: bot compose blogunda
`jwt_secret` yasak — mutasyon dogrulamasi ile FAIL verdigi gorulmustur.

Taban: 86 Kotlin testi + 21 Flutter statik kapisi, 0 failure/skip.

### P0-03 — RAM-only Redis auth state

Dogrulanan kok neden:

- `JwtBlacklist` ve `AuthService.revokeUser` iptal bilgisini yalniz Redis'te
  tutuyordu; o Redis bilerek persistence'siz ve `allkeys-lru`'dur
  (`deploy/compose.privacy.yml`). Anahtarin kaybi "iptal edilmemis" demekti.
- `EmergencyStopFlag` TTL'siz tek bir Redis key'iydi; restart veya eviction
  operator durdurmasini kendiliginden kaldirabiliyordu.
- Refresh rotasyonu `verify -> revoke -> mint` seklinde atomik degildi (P1-04).

Uygulanan cozum:

- Auth iptali PostgreSQL'e tasindi (V15). `users.credential_epoch` her token'in
  icine gomulur; logout epoch'u dondurur ve hesabin tum access/refresh
  token'lari ayni anda duser. `users.refresh_generation` yalniz refresh
  token'dadir ve rotasyonda degisir.
- Rotasyon tek `UPDATE ... WHERE refresh_generation = ? RETURNING` compare-and-
  set'idir. Paralel iki istek ayni eski token ile gelirse yalniz biri kazanir;
  supersede edilmis token reuse olarak reddedilir (`AUTH_REFRESH_REUSE`).
- Per-JTI blacklist tamamen kaldirildi; artik yalniz Redis'te yasayan bir
  revocation kaydi yok. `revoked_user`/`jwt_blacklist` key uretecleri de
  olu kod olarak silindi.
- Silinen hesap icin ayri "revoked" kaydi tutulmuyor: `users` satiri yoksa
  hicbir token dogrulanamaz. Bu isaret dogasi geregi kalicidir.
- Her iki alan da sayac degil opaque 128-bit rastgele degerdir; bir DB
  snapshot'i rotasyon sayisi, hesap yasi veya aktivite sirasi vermez.
- Credential state okunamiyorsa authentication fail-closed olur.
- Emergency stop V16 `bot_control` tablosuna tasindi ve okuma cache'lenmez;
  depolama hatasinda "durduruldu" kabul edilir.

Kanit: `DurableCredentialStateIntegrationTest` (gercek PostgreSQL) — restart
sonrasi logout'un korunmasi, silinen hesabin refresh edememesi, supersede
edilmis refresh token'in reddi, 8 paralel rotasyonda tek kazanan ve opaque
deger bicimi. Statik kapi eski Redis tasarimini degil yeni durable tasarimi
zorunlu kilacak sekilde guncellendi.

Taban: 92 Kotlin testi + 21 Flutter statik kapisi, 0 failure/skip.

### P0-04 — hesap silme atomikligi

Dogrulanan kok neden:

- PostgreSQL transaction'i commit olduktan sonra push cache, registry,
  credential cache ve socket/queue temizligi korumasiz siralaniyordu.
- Aradaki bir hata kalan adimlari atliyor, genel `catch` 500 donuyordu:
  hesap DB'de yokken istemci "silme basarisiz" goruyordu.
- `ConnectionManager.purgeUserState` tek blok oldugu icin socket kapatma
  hatasi Redis kuyruk temizligini de dusuruyordu.

Uygulanan cozum:

- `AccountDeletion` ayri bir sinir oldu. Kalici kopyalar (`fcm_tokens`,
  `bot_signal_session`, `users`) tek transaction'da gider; commit aninda
  hesap authenticate edilemez hale gelir.
- Gecici temizlik adlandirilmis, bagimsiz ve tekrar calistirilabilir adimlara
  bolundu. Her adim `runCatching` ile yalitilir; bir adimin hatasi sonrakileri
  atlamaz. Basarisiz adimlar en fazla uc kez yeniden denenir ve kalanlar
  `ACCOUNT_DELETE_RESIDUAL` sayaciyla raporlanir.
- Islem idempotenttir: kayit zaten yoksa istek yine basarilidir
  (`alreadyAbsent`). Istemci guvenle yeniden deneyebilir.
- Kalici transaction basarisiz olursa hicbir kopya silinmez ve 500 doner;
  istemci lokal hesabini silmez.
- `ConnectionManager.purgeUserState` uc bagimsiz fonksiyona bolundu.

Bilincli sapma: rapor "durable tombstone/saga" oneriyordu. Silinen hesabin
UUID'sini kalici bir satirda tutmak, tam da silinmesi istenen iliskiyi geride
birakirdi ve gizlilik sozlesmesine aykiridir. Idempotanlik icin gerekli de
degildir: `users` satirinin yoklugu zaten kalici ve dogru isarettir. Kalan
gecici kopyalar yalniz process RAM'inde veya kisa TTL'li Redis'tedir ve hesap
artik authenticate olamadigi icin teslim edilemez.

Kanit: `AccountDeletionIntegrationTest` (gercek PostgreSQL) — uc kopyanin tek
transaction'da silinmesi ve token'in aninda gecersizlesmesi, tekrarlanan
istegin basarili kalmasi, hata veren adimin sonrakileri atlamamasi, gecici
hatanin yeniden denenmesi ve kalici hatada hicbir kopyanin silinmemesi.

Taban: 97 Kotlin testi, 0 failure/skip.

## Ortam notu — Flutter/Dart SDK

Bu oturum sirasinda `/tmp/flutter-sdk` ortamdan kayboldu; makinede baska bir
Flutter veya Dart kurulumu yok. Bu nedenle `flutter test` ile calisan statik
gizlilik kapilari ve `dart tool/audit_server_deployment_privacy.dart` P0-04
degisikliginden sonra yeniden calistirilamadi.

- P0-06 ve P0-03 kapanislarinda bu kapilar 21/21 yesil calistirilmisti.
- P0-04 kaynak konumu degistirdigi icin `server_privacy_gate_test.dart`
  icindeki hesap-silme testi yeni `AccountDeletion` sinirina tasindi ve
  iddialari guclendirildi (tek transaction, yalitilmis adimlar, tombstone
  yasagi). Bu blok SDK geri geldiginde dogrulanmalidir.

### P0-11 — bot alici identity pinlemesi

Dogrulanan kok neden:

- `PgSignalProtocolStore.isTrustedIdentity` kosulsuz `true` donuyordu.
- `saveIdentity` hicbir sey yazmiyor, `getIdentity` her zaman null donuyordu.
- Prekey bundle tamamen signaling'den geldigi icin signaling/DB/ic ag ihlali
  alicinin identity key'ini sessizce degistirebilir ve bot saldirganin
  anahtarina sifreleyebilirdi. Signal transport'u kullanmak tek basina
  authenticated E2EE vermez.

Uygulanan cozum:

- V17 `bot_peer_identity` tablosu: purpose-separated blind recipient index +
  BOT_MASTER_KEY altinda AAD-bagli muhurlenmis public identity key. Ham UUID,
  zaman damgasi veya mesaj iliskisi yok.
- Ilk gorulen anahtar trust-on-first-use ile pinlenir. Sonraki farkli bir
  anahtar fail-closed reddedilir; pin sessizce ustune yazilmaz.
- Rotasyon ancak acik operator onayindan sonra kabul edilir:
  `POST /admin/identity/approve-rotation` pini duserur, bir sonraki gonderim
  yeni anahtari yeniden pinler. `GET /admin/identity` opaque index + public
  anahtar parmak izi listeler.
- Pin okunamiyorsa guvenilirlik iddia edilmez (fail-closed).

Kanit: `PeerIdentityPinIntegrationTest` — ilk anahtarin pinlenmesi, takas
edilen anahtarin reddi, onay sonrasi rotasyon, satirda ham alici id
bulunmamasi ve AAD baglantisinin baska bir index altinda acilmayi
engellemesi.

### P0-02 — telefon kimligi first-claim

Ayrintili analiz, yapilanlar ve istemci tarafinda yapilmasi gerekenler ayri
belgede: `SERVER_DIRECTORY_IDENTITY.md`.

Ozet:

- Kok neden dogrulandi: e-posta OTP telefon sahipligini kanitlamaz; grant
  hicbir talebe bagli degildir ve `/users/register` istemcinin verdigi
  `phoneHash`'i sorgusuz kabul eder.
- Sunucu tarafinda kapatilabilen kisim kapatildi: registration grant
  tuketimi V18 ile PostgreSQL'e tasindi ve hesap kaydiyla **tek
  transaction** icinde yapiliyor. Reddedilen kayit grant'i yakmaz; paralel
  kullanimda tek kazanan olur; Redis kaybi replay penceresi acmaz.
- Kalan risk sunucu koduyla kapatilamaz: sahiplik kaniti (invite/QR veya
  SMS/voice) bir urun karari, commitment baglama ise istemci degisikligi
  gerektirir. Ikisi de belgede adim adim yazildi.

Kanit: `RegistrationGrantIntegrationTest` (5 senaryo).

Taban: 107 Kotlin testi, 0 failure/skip.

### P0-10 — bot grup alici yetkilendirmesi

Dogrulanan kok neden:

- `AllowListChecker.isAllowed` yalniz `recipientRef` degerini karsilastiriyordu.
  Izinli bir `group:<token>` bilen client, istegin govdesindeki
  `recipientUserIds` listesine istedigi UUID'leri koyabiliyordu; bu liste
  yalniz bicimsel olarak (UUID, <=256, distinct) dogrulaniyordu.
- Tum uyelere ayni dis `messageId` ve acik `messageType` gidiyordu: fanout
  signaling katmaninda dogrudan linklenebiliyor, icerik kategorisi aciga
  cikiyordu.
- Zarf string interpolasyonuyla kuruluyordu; istekten gelen `messageType`
  dogrudan JSON'a gomuluyordu (P1-14 injection yuzeyi).

Uygulanan cozum:

- `AllowListChecker.areRecipientsAllowed` eklendi: grup fanout'unda her
  alici ayrica `user:<uuid>` olarak izinli olmalidir. Grup tokeni tek basina
  yetki degildir.
- Her alici icin bagimsiz rastgele dis `messageId` uretilir.
- Zarf `buildJsonObject` ile typed serializer uzerinden kurulur.

Bilincli sinir: sunucu kalici grup uyeligi tutmadigi icin gercek uyelik
dogrulanamaz; kalici bir grup grafigi olusturmak gizlilik sozlesmesine
aykiri olurdu. Raporun onerdigi device-signed kisa omurlu group send
capability istemci katilimi gerektirir ve acik kalir.

Kalan sinir: dis zarftaki `messageType` halen aciktir. Ic E2EE payload'a
tasimak istemci tarafinda karsilik gelen bir degisiklik ister.

Kanit: `AllowListCheckerTest` — izinli grup tokeninin keyfi aliciyi
yetkilendirmemesi, bos alici kumesinin reddi, tek bir izinsiz alicinin tum
fanout'u dusurmesi.

Taban: 110 Kotlin testi, 0 failure/skip.

### P0-09 — bot public/admin yuzu erisilemez

Dogrulanan kok neden:

- `PublicListener` ve `AdminListener` container ici `127.0.0.1:8091/8092`
  dinliyordu; Unix socket "Task 13" olarak birakilmisti.
- Hardened compose bot icin ne port mapping ne socket mount sagliyordu.
  Sonuc: bot send ve admin CLI yollari container disindan hic erisilemezdi.

Uygulanan cozum:

- `UnixSocketBridge` JDK 17'nin yerel Unix domain socket destegini kullanir;
  Netty native transport veya ek container gerekmez. Socket 0600 ile acilir,
  eski dosya temizlenir, kapanista silinir.
- Ktor'un Netty motoru inet olmayan adrese bind edemedigi icin yonlendirme
  ayni process icindedir: socket baglantisi loopback listener'a aktarilir.
  Loopback yuzeyi container disindan erisilemez.
- Compose'da `/run/bot` tmpfs yerine `BOT_SOCKET_DIR` bind mount'u kullanilir.
- Deploy preflight dizinin varligini, 0700 modunu ve 10002:10002 sahipligini
  dogrular. Statik kapi bot blogunda `ports:` yasaklar ve socket mount'u
  zorunlu kilar.

Kanit: `UnixSocketBridgeTest` — socket uzerinden uctan uca trafik, 0600 izin,
kalmis socket dosyasindan sonra yeniden baslatma, kapanista dosyanin silinip
servisin durmasi ve loopback yuzeyinin disari acilmamasi.

### P0-08 — kontrollu egress

Dogrulanan kok neden: butun servisler yalniz `internal: true` bir aga
bagliydi; signaling ise dis PostgreSQL, SMTP, Firebase ve Janus'a ulasmak
zorundaydi. Verilen topoloji ile stack calisamazdi.

Uygulanan cozum:

- Ag ikiye ayrildi. `securechat-internal` disari cikmaz; `securechat-egress`
  yalniz signaling ve bota baglidir. Redis bilerek yalniz ic agdadir.
- Egress hedefleri `deploy/README.md` icinde tek tek listelendi; host
  firewall bu listenin disini reddetmelidir. Compose tek basina allow-list
  saglayamaz ve bu acikca yazildi.
- P0-12'den kalan `deploy/reverse-proxy.conf` eklendi: access log kapali,
  upgrade isteginde `Authorization` korunuyor, `token=` query'si reddediliyor.
- Statik kapi Redis'in egress agina baglanmadigini ve proxy'nin uc davranisi
  tasidigini dogrular.

Kalan operator isi: gercek firewall allow-list'i ve proxy'nin bu referansa
gore kurulmasi.

Taban: 115 Kotlin testi, 0 failure/skip.

### P0-05 — Janus SFU medya siniri (kismi)

Dogrulanan kok neden:

- Kaynak agacinda SFrame, FrameCryptor veya esdeger bir uygulama-katmani
  medya sifrelemesi yok. SFU yolunda WebRTC oturumu Janus'ta sonlandigi icin
  Janus host/process'i ses ve goruntu icin guven sinirinin icindedir.
- Room ID `groupId.hashCode()` ile turetiliyordu: 31 bitlik, cakismaya acik
  ve grup routing tokenini bilen biri tarafindan onceden hesaplanabilir.
- Client-facing Janus icin uygulanmis participant capability yok.

Uygulanan ara cozum:

- `SfuPolicy` ile SFU **varsayilan kapali**. Kapaliyken grup aramalari mesh
  modda kalir; kullaniciya sessizce zayif bir garanti verilmez.
- Production'da acmak `SFU_MEDIA_BOUNDARY_ACK=sfu-media-not-end-to-end-
  encrypted` beyanini gerektirir. Eksik beyan sessizce "kapali"ya donusmez,
  startup durur — operator neyi kabul ettigini gormeden gecemez.
- Room ID 62-bit rastgele ve aktif odalarla cakismayacak sekilde uretilir.

Acik kalan: SFrame/FrameCryptor medya E2EE'si ve participant-bound Janus
capability. Ikisi de istemci tarafinda karsilik gelen implementasyon ister;
sunucu tek basina kapatamaz.

Kanit: `SfuPolicyTest` (6 senaryo).

### P0-01 — calisan artefaktin kimligi

Dogrulanan kok neden: canli uctaki route seti hardened kaynakla uyusmuyordu
ve hangi commit'in calistigini gosteren hicbir kanit yoktu.

Uygulanan cozum:

- Gradle build sirasinda `build-info.properties` uretilir: commit, build
  zamani ve migration klasorunden turetilen hedef (su an `V18`).
- `BuildManifest.validate()` production'da manifest eksikse startup'i
  durdurur; kaynagi kanitlanamayan artefakt calismaz.
- Operator-only `GET /api/v1/version` (metrics bearer) manifest'i doner.
  Anonim istemciye acilmaz.
- `build_privacy_images.sh` tam 40-hex `SOURCE_COMMIT` ister ve degeri
  build'e gecirir.

Acik kalan operator isi: image'in imzalanmasi, registry digest + commit +
SBOM bagini release kaydinda tutmak ve canli container digest'ini bu kayitla
karsilastirmak.

Taban: 125 Kotlin testi, 0 failure/skip.

### P0-05 devami — sunucu yarisi tamamlandi

`SFU_MEDIA_E2EE.md` tam tasarimi ve istemci sartnamesini tutar. Sunucuda
yapilanlar:

- **Yetenek-kapili promosyon.** `ActiveCall` katilimci basina medya
  sifreleme yetenegini tutar; `mediaEndToEndEncrypted` ancak **tum**
  katilimcilar bildirdiginde true olur. `SfuPolicy.canPromote` medya uctan
  uca sifreliyse operator beyani aramaz, degilse arar. Yetenek wire'da
  opsiyonel `mediaE2ee` alanidir; eksikse false — eski istemci sessizce
  SFU'ya gecirilmez.
- **Katilimci tavani.** Arayan dahil mutlak tavan 8'dir. SFU kullanilamiyorsa
  video mesh tavani 6, ses mesh tavani 8'dir. Kontrol per-group lock altinda;
  iki es zamanli katilim tavani birlikte asamaz. Tavan dolunca
  `GROUP_CALL_CAPACITY_REACHED` ile reddedilir — mesh'te sessizce
  kullanilamaz hale gelen arama yerine ongorulebilir ret.
- **Concurrency.** `ActiveCall.participants` immutable oldu; onceki
  `MutableSet` concurrent map icinde thread-safe degildi (P1-13'un cekirdegi).
- **Room ID.** `groupId.hashCode()` yerine aktif odalarla cakismayan 62-bit
  rastgele deger.

Anahtar dagitiminin sunucuda **hicbir rolu yok**: medya anahtari mevcut
direct Signal zarflariyla istemciden istemciye gider. Grup uyeligi cihazda
tutuldugu icin anahtari kime verecegine istemci karar verir; kotu niyetli bir
sunucu odaya katilimci eklese bile yalniz ciphertext alir. Bu nedenle Janus
token auth gizlilik kontrolu degil, abuse/DoS kontrolu olarak siniflandirildi
ve istemci degisikligiyle ayni dalgaya birakildi.

Kanit: `GroupCallCapacityTest` (7 senaryo), `SfuPolicyTest` (6 senaryo).

Taban: 132 Kotlin testi, 0 failure/skip.

### P1 parti 1 — atomiklik ve sema butunlugu

**P1-16 — Flyway validation.** `validateOnMigrate(false)` idi: uygulanmis bir
migration dosyasi sonradan degisse Flyway fark etmezdi ve sema ile kod sessizce
ayrisirdi. Acildi. Ayrica migration sonrasi ulasilan surum, build manifestinden
gelen beklenen surumle karsilastirilir; eksik veya fazla surum startup'i
durdurur. Beklenti migration klasorunden turedigi icin elle guncelleme
gerektirmez.

**P1-02 — rate limiter.** `ZREMRANGEBYSCORE -> ZCARD -> ZADD` uc ayri
gidis-donusttu; es zamanli istekler ayni "limit altinda" okumasini paylasip
hep birlikte gecebiliyordu. Ayrica member olarak yalniz timestamp yazildigi
icin ayni milisaniyedeki istekler tek kayda dusuyor ve limit hic dolmuyordu.
Tek Lua adimina alindi; member'a nonce eklendi. Byte tabanli limit ayni
scripti cost ile kullanir.

Kanit: `RateLimiterAtomicityIntegrationTest` (gercek Redis, 7 senaryo).
Mutasyon dogrulamasi: eski uc-adimli sıraya donuldugunde 4 test duser.

**P1-03 — OTP.** `HGETALL -> karsilastir -> DEL/HINCRBY` atomik degildi:
paralel iki dogru deneme tek OTP'den iki grant uretebiliyordu; paralel yanlis
denemeler tavani asabiliyordu. Ayrica cooldown ayri bir okumaydi, iki paralel
istek ayni "gecti" sonucunu paylasabiliyordu.

Ilk duzeltmedeki iki adimli `claim`/`consume` akisi, cok sayida paralel dogru
istekte deneme tavanina ulasan bir istegin kaydi digerleri consume etmeden
silmesine izin veriyordu. Karsilastirma, yanlis-deneme artisi ve basarili
tek-kullanimlik silme artik tek Redis Lua state machine'indedir. Cooldown da
OTP uretimiyle ayni scripttedir.

Kanit: `OtpAtomicityIntegrationTest` (gercek Redis, 7 senaryo; paralel dogru
deneme 20 tur tekrar edilir).

**P1-07 — prekey bundle.** Identity, signed prekey ve one-time prekey'ler uc
ayri transaction'daydi; arada bir hata karisik bundle birakabiliyordu (yeni
identity + eski signed prekey) ve onu ceken peer cozemeyecegi bir oturum
kurardi. Tek `uploadBundle` transaction'i oldu; hesap satiri `FOR UPDATE` ile
kilitlenir, identity rotasyonunda eski one-time havuzu ayni adimda silinir.

Kanit: `PreKeyBundleTransactionIntegrationTest` (gercek PostgreSQL, 5 senaryo;
paralel upload'larin karisik bundle uretmedigi dahil).

Taban: 151 Kotlin testi, 0 failure/skip.

### P1 parti 2 — sinirlar ve yetki

**P1-15 — byte kotasi.** `file_transfer` kotasi `messageJson.length` ile
karakter sayiyordu; cok byte'li karakterlerde gercek boyut daha buyuk oldugu
icin kota altinda kaliniyordu. Frame okunurken zaten hesaplanan UTF-8 byte
boyutu asagi gecirildi.

**P1-05 — guvenilen proxy.** Yedi yerde soket adresi okunuyordu ve forwarded
header hic degerlendirilmiyordu: proxy arkasinda butun kullanicilar tek kimlik
gibi sayiliyor, IP basina limitler anlamini yitiriyordu. `ClientAddress` sinirI
eklendi:

- `X-Forwarded-For` yalniz `TRUSTED_PROXIES` listesindeki kaynaklardan gelirse
  okunur; aksi halde yok sayilir, yani istemci header uydurarak limiti
  atlayamaz.
- Zincirde en sagdaki guvenilmeyen adres alinir; soldan baslamak istemcinin
  eklediklerini kabul etmek olurdu.
- Yalniz literal IP kabul edilir. `InetAddress.getByName` hostname alsaydi
  saldirgan kontrolundeki bir header istek basina DNS cozumlemesi
  tetikleyebilirdi.
- Bozuk `TRUSTED_PROXIES` girdisi guveni genisletmez, sessizce dusurulur.

Kanit: `ClientAddressTest` (8 senaryo, production fonksiyonuna karsi).

**P1-08 — alici dogrulamasi.** Route edilen mesajlarda alicinin gercek bir
hesap oldugu kontrol edilmiyordu; uydurulmus UUID'ler icin offline kuyrukta
kalici anahtarlar olusturulabiliyordu. Registry kontrolu eklendi
(`ROUTE_UNKNOWN_RECIPIENT`).

**P1-09 — presence.** Kimligi dogrulanmis herkes herhangi bir metne abone
olabiliyor, harita process omru boyunca buyuyordu. Hedefin gercek hesap olmasi
zorunlu kilindi, abone basina 512 tavan, dakikada 120 abonelik rate limiti ve
bos hedef anahtarlarinin temizligi eklendi.

Bilincli sinir: gercek "yalniz kisilerim gorebilsin" davranisi sunucuda bir
sosyal grafik gerektirir ve gizlilik sozlesmesi bunu yasaklar. Kalici cozum,
hedefin kendi cihazindan verdigi imzali bir presence capability'sidir; bu bir
protokol degisikligidir ve acik birakildi.

Kanit: `PresenceSubscriptionTest` (4 senaryo).

**P1-06 — govde sinirlari.** OTP, kayit, refresh, prekey ve FCM route'lari
`call.receive()` ile sinirsiz govde okuyordu. `receiveBounded` eklendi:
bildirilen `Content-Length` ve gercekte okunan byte ayri ayri sinirlanir.
Prekey yuklemesinde ayrica alan bazinda sinir var — one-time prekey sayisi,
tekrarlanan key id, identity/signed/signature byte boyutlari — cunku az sayida
ama cok buyuk alan govde limitini asmadan gecebilirdi.

Taban: 163 Kotlin testi, 0 failure/skip.

### P1 parti 3 — bot dayanikliligi

**P1-20 — ratchet butunlugu.** `loadSession -> ilerlet -> storeSession` dizisi
kosulsuz ustune yaziyordu; ayni aliciya iki es zamanli gonderim bir ratchet
adimini kaybettiriyor ve alici o mesaji hicbir zaman cozemiyordu.

- Gonderim sabit boyutlu recipient-hash lock striping ile serilestirildi;
  yukle-ilerlet-yaz dizisi tek parca calisir ve process RAM'inde sinirsiz
  recipient/social-graph anahtari birikmez.
- `storeSession` artik okunan degere karsi compare-and-set yapar. Kayit
  okundugundan beri degistiyse yazma reddedilir ve
  `ConcurrentSessionModificationException` firlatilir. Boylece birden fazla
  bot instance'i calissa bile cakisma sessizce degil hata ile sonuclanir.

Kanit: `RatchetConcurrencyIntegrationTest` (gercek PostgreSQL, 4 senaryo).

**P1-18 — teslim garantisi.** Uc ayri sorun vardi:

1. `RPOP` mesaji kuyruktan hemen siliyordu; process veya soket o anda olurse
   202 verilmis bir mesaj kayboluyordu.
2. Basarisiz teslimde mesaj `LPUSH` ile geri yaziliyordu. Kuyruk LPUSH/RPOP
   ile FIFO oldugu icin bu, mesaji sirasinin **sonuna** atiyordu.
3. `WebSocket.send()==true` teslim sayiliyordu; oysa o yalniz soket tamponunu
   ifade eder.

Cozum:

- Her kabul edilen mesaj, WebSocket bagli olsa bile once bounded durable queue'ya
  yazilir; kapasite dolunca eski 202 mesaji dusurulmez, yeni istek fail-closed
  reddedilir.
- Mesaj kuyruktan benzersiz checkout tokeniyla **in-flight** kaydina gecer;
  gercek messageId'ye gecis ve basarisiz gonderimi geri alma atomik Lua
  adimlaridir.
- Signaling, servis hesabi baglantilarina mesajin route edildigini bildiren
  `message_ack` cercevesi gonderir; in-flight kaydi ancak bununla silinir.
  Normal istemcilere bu cerceve gonderilmez ve client-originated sahte ACK
  server route'unda reddedilir.
- ACK gelmezse 30 saniyelik gorunurluk suresi sonunda mesaj `RPUSH` ile
  kuyrugun **basina** geri alinir; ayni milisaniyede checkout edilen birden
  fazla mesajda da sira korunur. Bagli socket bunu periyodik uzlastirir.
- Basarisiz gonderimde de mesaj sirasini koruyarak geri konur.

Kanit: `OutboundQueueDurabilityTest` (gercek Redis, 8 senaryo),
`SignalingWsClientAckTest` ve server-only frame regresyonu.

Taban: 177 Kotlin testi, 0 failure/error/skip.

### P1 parti 4 — baglanti, operasyon ve build

- **P1-01.** `removeConnection` kosulsuz siliyordu; ayni kullanici yeniden
  baglandiginda eski soketin `finally` blogu **yeni** soketi map'ten
  dusuruyor ve kullanici bagliyken cevrimdisi gorunuyordu. Compare-and-remove
  eklendi. Kapasite kontrolu de kilit icine alindi; disarida iki es zamanli
  baglanti limiti birlikte asabiliyordu.
- **P1-12.** `sendAndWait` timeout veya gonderim hatasinda `pendingRequests`
  kaydini birakiyordu (sizinti). `onClose` ve `onError` ayri ayri reconnect
  baslatiyor, catch blogu ozyinelemeli deniyordu: tek kopmada birden fazla
  dongu ureyebiliyordu. `finally` temizligi, tek reconnect sahibi ve 30
  saniyelik keepalive eklendi; kopmada bekleyen istekler asili birakilmadan
  dusurulur.
- **P1-14.** Sunucunun urettigi on cerceve string interpolasyonuyla
  kuruluyordu; istemciden gelen `callId`/`groupId` dogrudan JSON'a
  gomuluyordu. Hepsi `buildJsonObject` ile typed hale getirildi.
- **P1-10/11.** Firebase baslatma hatasi yutuluyor, health yalniz env
  path'inin varligina bakip "enabled" diyordu — push hic calismazken sistem
  saglikli gorunuyordu. Hata artik raporlanir ve health gercek durumu doner.
  Push builder'a explicit APNs `background` + `content-available`
  yapilandirmasi eklendi; yalniz `AndroidConfig` tasiyan data-only push iOS
  istemcisini uyandirmaz.
- **P1-17.** Kismi grup fanout'unda tum idempotency rezervasyonu
  birakiliyordu; ayni anahtarla retry, mesaji zaten almis uyelere yeniden
  gonderiyordu. `FanoutProgress` alici bazinda opaque ilerleme tutar, retry
  yalniz eksikleri isler.
- **P1-21.** `/health` yalniz DB/Redis olcuyordu; identity saglanmamis veya
  signaling kopmus bir bot da "ok" gorunuyordu. Liveness ile readiness
  ayrildi; `/ready` identity, signaling baglantisi ve kuyruk derinligini de
  kapsar.
- **P1-22.** Servislere bellek/CPU limiti ve `MaxRAMPercentage` eklendi.
- **P1-25.** Image build'i once test paketlerini calistirir; statik kapi hem
  bunu hem `SOURCE_COMMIT` damgasini zorunlu kilar.

Taban: 177 Kotlin testi + 250 Flutter testi, 0 failure/skip.

### P2 partisi

- **P2-09** (en onemlisi). Nonce, body hash kontrolunden once tuketiliyordu:
  yakalanmis bir token yanlis bir body ile oynatildiginda mesru istegin
  nonce'u yaniyor ve gercek istek replay sayilarak reddediliyordu — mesru
  istemciye karsi hizmet engeli. Sira ters cevrildi; yalniz butunlugu
  dogrulanmis istek nonce tuketir. Sirayi sabitleyen test eklendi.
- **P2-04.** SFU oda bilgisi yalniz kimlik dogrulamasi istiyordu; artik aktif
  cagrinin katilimcisi olmak zorunlu.
- **P2-06.** Admin rotate once revoke edip sonra create ediyordu; create
  hatasi client'i credential'siz birakabiliyordu. Sira ters cevrildi.
- **P2-07.** Admin create'te ad, allow-list boyutu/bicimi, kota ve expiry
  sinirlari eklendi.
- **P2-08.** `NX` basarisiz olup okuma bos donduğunde kod rezervasyon almadan
  `Fresh` donuyordu; artik yeniden `NX` denenir.
- **P2-10.** FCM zamanlama haritalari ham UUID tutuyor ve hic temizlenmiyordu;
  blind index'e gecildi ve periyodik budama eklendi.
- **P2-03.** `/health` bagimlilik ayrintisi donuyordu; liveness sadelesti,
  ayrintili readiness operator-only oldu ve proxy'de kapatildi.
- **P2-12.** Dokumandaki "30 gun" access TTL'i gercek degerlerle degistirildi;
  kullanilmayan `TOKEN_TTL_MS` kaldirildi.

Taban: 179 Kotlin testi + 250 Flutter testi, temiz analyze, deployment audit
PASS.

### P2 ikinci parti

- **P2-01 (snapshot).** Yanit her hesaba ayni listeyi verdigi icin eleman
  sayisi dogrudan kayitli hesap sayisiydi; kimlik dogrulamis herhangi bir
  istemci sunucunun buyuklugunu ve gunluk buyume hizini olcebiliyordu. Liste
  artik 256'lik kovaya yuvarlanir ve dolgu kayitlari gercek kayitlardan
  ayirt edilemez: ayni etiket uzunlugu (32 byte), ayni zarf uzunlugu
  (12+36+16 byte). Dolgu etiketi sunucu anahtariyla turer — rebuild'ler
  arasinda sabit kalir, cunku her rebuild'de degisen bir etiket dolguyu ele
  verirdi; zarf ise gercek kayitlarda da her muhurlemede degistigi icin
  yenilenir. Liste etikete gore siralanir, dolgular sona kumelenmez.
  Istek basina O(N) muhurleme de kalkti: liste zaten herkes icin ayni
  oldugundan uyelik surumu degisene (ya da 60 sn dolana) kadar paylasilir.
  Flutter istemcisi degismedi — cozulemeyen kayitlari zaten atliyordu.
- **P2-02 (kota).** Kota yalniz Redis sliding window'undaydi. Redis bu
  dagitimda kasten kalicisizdir (RDB kapali); restart ya da bellek baskisi
  tum sayaclari sifirliyor, yani rehber enumeration'ina konan sinir tekrar
  tekrar denenebiliyordu. Gunluk kota artik PostgreSQL'de, hesabin blind
  index'i altinda tutulur (`directory_quota`): ham `user_id` yok, yalniz gun
  kovasi ve sayac, iki gun sonra silinir. Kontrol tek atomik `INSERT ... ON
  CONFLICT ... WHERE` ifadesidir; reddedilen istek sayaci artirmaz, aksi
  halde sinira dayanan hesap kendini kalici kilitleyebilirdi. Es zamanlilik
  testi 8 paralel istekten tam 2'sinin gectigini dogrular.
- **P2-05 (TURN).** Iki gercek sorun vardi. Birincisi duz `turn:`: STUN/TURN
  mesajlari sifresiz oldugu icin yol uzerindeki gozlemci username'i, relay
  adresini ve cagri zamanlamasini goruyordu — medya SRTP ile sifreli olsa da
  kimin ne zaman aradigi acikti. Production artik yalniz `turns:` sunar ve
  `ProductionDeploymentPolicy` duz relay'i acikca istense bile reddeder.
  Ikincisi rotasyon: secret `by lazy` ile surece sabitleniyordu, operator
  dosyayi degistirse bile sunucu restart edilene kadar eski sirri
  kullaniyordu — pratikte rotasyon hic yapilmiyordu. Deger en fazla 60 sn
  gecikmeyle yeniden okunur; okuma hatasinda eski deger korunur (kismi
  write sirasinda TURN'u tamamen dusurmek daha kotu bir sonuc olurdu).
  Ayrica kaynak koda gomulu IP fallback'i kaldirildi: yanlis yapilandirilmis
  bir dagitim sessizce baska bir operatorun relay'ine yonelirdi.
- **P2-13 (SBOM/SCA).** `deploy/sbom.py`, `gradle/verification-metadata.xml`
  icindeki 278 bileseni CycloneDX 1.5 belgesine cevirir ve
  `deploy/known_vulnerable.txt` listesine karsi kontrol eder. Manifest zaten
  release'e giren her artefaktin sha256'sini tasidigi icin SBOM tam olarak
  calisan baytlari anlatir. Betik kasten ag kullanmaz — deploy anindaki bir
  ag cagrisi hem tekrar uretilebilirligi hem de egress kisitini bozardi.
  `build_privacy_images.sh` bunu image uretiminden once calistirir; eslesme
  varsa build durur (mutasyonla dogrulandi). Advisory listesini agi olan bir
  makinede guncel tutmak operatorun isidir.
- **Test semasi.** `LAST_MIGRATION` yedi test dosyasinda sabit `18` idi; yeni
  bir migration eklendiginde testler sessizce eski semaya karsi calisirdi.
  Deger artik migration dizininden okunur.

### P2-14 neden acik

Deprecation, Gradle'in `junit-platform-launcher`'i test runtime'ina otomatik
yuklemesinden gelir; dogru cozum onu acikca bildirmektir. Offline cache'te
yalniz `1.10.1` var, projede `junit-jupiter 5.10.2` / platform `1.10.2`
kullaniliyor. Surum karisik bir launcher `LinkageError` riski tasidigi ve
Gradle 9 dagitiminin kendisi de cache'te olmadigi icin bu adim bilerek
yapilmadi. Yapilmasi gereken: agi olan bir makinede
`org.junit.platform:junit-platform-launcher:1.10.2` ve Gradle 9 dagitimi
offline aynaya alinip `verification-metadata.xml`'e sha256'lariyla eklenir,
sonra `testRuntimeOnly` olarak bildirilir.

Taban: 198 Kotlin testi + 250 Flutter testi, temiz analyze, deployment audit
PASS.

## Kapsamli test gecisi (2026-08-25)

Butun bulgular test kapsamina karsi tarandi. Kapsanan/kapsanmayan ayrimi
kaynak taramasiyla cikarildi: `ConnectionManager`, `serverFrame`,
`JanusOrchestrator`, `FcmPushSender`, Flyway yapilandirmasi, `FanoutProgress`,
govde tavanlari, bot readiness ve audit sayaclari hicbir testten
gecmiyordu. Kotlin takimi 198'den **268 teste** cikti.

### Bu gecis gercek bir acik buldu

**P1-06 bot tarafinda kapanmamisti.** `SendPipeline.handle` govdeyi hala
`call.receiveChannel().toByteArray()` ile tavansiz okuyordu — gelen ne
kadarsa o kadar bayt RAM'e giriyordu. Uc admin route'u da `call.receive<T>()`
ile ayni sekilde sinirsizdi. `http/BoundedBody.kt` eklendi: bildirilen
`Content-Length` kontrol edilir (chunked gonderimde bulunmayabilir ya da
yalan olabilir) **ve** okuma tavan+1 bayt ile sinirlanir. Gonderim tavani
256 KB (downstream WebSocket cercevesiyle ayni), kontrol govdeleri 8 KB.

### Eklenen testler

| Dosya | Bulgu | Senaryolar |
|---|---|---|
| `ConnectionLifecycleTest` | P1-01 | eski soket kapanisi yeni baglantiyi silmiyor, gercek kapanis cevrimdisi yapiyor, abonelik temizligi yalniz kopan oturumda, kullanicilar birbirini etkilemiyor, shutdown yeni baglanti almiyor |
| `ServerFrameTest` | P1-14 | tirnakli/ters bolulu/suslu parantezli `callId`, dusman `recipientId` ile ikinci nesne enjeksiyonu, unicode, boolean tipi korunuyor |
| `FcmPushSenderTest` | P1-10, P1-11, P2-10 | baslatma hatasi yutulmuyor, gecici sinyaller push uretmiyor, ICE/SDP answer cagri kotasini yakmiyor, cagri ve mesaj ayri sayac, blind index anahtari, budama |
| `SchemaMigrationIntegrationTest` | P1-16 | temiz veritabani beklenen surume ciiyor, ikinci migrate no-op, bozulmus checksum startup'i durduruyor, koddan yeni sema startup'i durduruyor |
| `PreKeyUploadBoundsTest` | P1-06 | OTPK tavani, tekrarli keyId, buyuk/bos/base64 olmayan anahtar materyali, registrationId araligi |
| `JanusOrchestratorTest` | P1-12 | oda kimligi 62-bit rastgele ve carpismasiz, gonderim hatasi bekleyen kayit birakmiyor, transaction'siz mesaj reddediliyor |
| `AuditMetricsTest` | P1-24 | kimlik girdileri yutuluyor, bicimsiz olay turu yeni seri acmiyor, sayaclar metrics ciktisinda, scrape'te hesap kimligi yok |
| `RequestSizeAccountingTest` | P1-06, P1-15 | cok byte'li karakter aritmetigi, frame tavani byte cinsinden, chunk kotasi byte dusuyor, tavansiz `call.receive<` yok |
| `FanoutProgressTest` | P1-17 | retry teslim edilmis uyeyi atliyor, idempotency key ve client bazinda ayrik, tamamlanan fanout kaydi siliniyor, kayit ham kimlik tasimiyor, TTL |
| `HealthReadinessTest` | P1-21 | her bagimlilik tek basina readiness'i kapatiyor, olculemeyen kuyruk hazir degil, kuyruk tavani, metrics bearer eslesmesi |
| `BodyLimitTest` | P1-06 | gonderim ve admin route'lari tavanli okuyor, tavanlar gercek sinir, okuyucu hem Content-Length hem stream'i kontrol ediyor |
| `TurnCredentialServiceTest` | P2-05 | production yalniz `turns:`, TLS once, gomulu host yok, port araligi, sir restart'siz yenileniyor |
| `DirectorySnapshotPaddingTest` | P2-01 | kova yuvarlamasi, dolgu gercek kayitla ayni sekilli, dolgu etiketi rebuild'ler arasi sabit, carpisma yok |
| `DirectoryQuotaIntegrationTest` | P2-02 | gunluk sinir, restart'a dayanikli, reddedilen istek kota yakmiyor, gun kovasi sifirlamasi, es zamanli 8 istekten 2'si geciyor |

### Testabilite icin yapilan kucuk yeniden duzenlemeler

- `FcmPushSender` artik token deposunun tamamini degil ihtiyaci olan iki
  yetenegi (lookup + remove) alir; kapi karari veritabanina bagli degildir.
  Servis hesabi yolu da disaridan verilebilir, boylece basarisiz baslatma
  yolu dogrulanabilir.
- `HealthListener.isReady(...)` route govdesinden ayri saf bir fonksiyondur.
- `serverFrame`, `hasSaneKeyMaterial`, `JanusOrchestrator.nextRoomId`,
  `sendAndWait`, `ConnectionManager.subscriptionCount` `internal` yapildi.
- Yedi test dosyasindaki sabit `LAST_MIGRATION = 18` migration dizininden
  okunur hale getirildi.

### Mutasyon dogrulamasi

Testlerin bos olmadigi, duzeltmeler geri alinarak dogrulandi: readiness'ten
identity/signaling cikarildiginda, oda kimligi sayaca cevrildiginde, push
haritalari birlestirildiginde, gonderim govdesi tavansiz okundugunda,
`removeConnection` kosulsuz `remove`a dondurulduğunde, kota `WHERE`
korumasi kaldirildiginda ve SCA listesine mevcut bir bagimlilik
eklendiginde ilgili testler kirmizi oldu.

Taban: 268 Kotlin testi + 250 Flutter testi, 0 skip, temiz analyze,
deployment audit PASS, SBOM/SCA kapisi PASS.

## Uctan uca testler (2026-08-25)

`ktor-server-test-host` offline aynaya alindi ve gercek Ktor motoruyla
uctan uca senaryolar yazildi. Kotlin takimi **299 teste** cikti; 31'i
uctan uca.

### Bagimlilik ekleme

`io.ktor:ktor-server-test-host`, `ktor-client-websockets` ve
`ktor-client-content-negotiation` (2.3.7) eklendi. `verification-metadata.xml`
26 yeni bilesenle guncellendi; **hicbir mevcut kayit dusmedi ve hicbir
hash degismedi** (544 -> 570, karsilastirmayla dogrulandi). Yeni bilesenler
`testImplementation` oldugu icin release artefaktina girmez — fat JAR
denetlendi, test sinifi tasimiyor.

Bunun bir yan etkisi vardi: SBOM dogrulama manifestinden uretiliyordu, yani
test bagimliliklarini da listeliyordu ve test-only bir CVE release'i
durdurabilirdi. `writeRuntimeArtifacts` Gradle gorevi runtime classpath'i
yazar, `sbom.py --runtime` yalniz dagitilan bilesenleri alir: 300 yerine
**179 bilesen**. Deployment audit bu adimi de zorunlu kilar.

### Modul cikarimi

Route'lar ve pluginler `main()` icindeki `embeddedServer` lambda'sinda
duruyordu; bir uctan uca test ayni yapilandirmayi ancak kopyalayarak
kurabilirdi — yani test ettigi sey production yapilandirmasi olmazdi.
`fun Application.signalingModule(...)` ayri durur, `main()` ve testler ayni
fonksiyonu kullanir.

Testler gercek PostgreSQL ve gercek Redis ile kosar. Rehber OPRF anahtari
build dizinine uretilip owner-only yapilir ve `DIRECTORY_OPRF_PRIVATE_KEY_FILE`
ile verilir; boylece production'daki dosya tabanli secret yolu da ayni
testlerde calisir. Repoda anahtar materyali durmaz.

### Kapsanan senaryolar

- **WebSocket kimlik dogrulamasi:** kimliksiz baglanti reddedilir; query
  string'deki token gecerli bir header varken bile reddedilir (P0-12);
  baska hesabin token'i bu userId'yi talep edemez; uydurma token reddedilir;
  gecerli bearer ile baglanti kabul edilir ve kullanici cevrimici olur.
- **Yonlendirme:** mesaj alicinin soketine ulasir; istemcinin iddia ettigi
  `senderId` token'daki kimlikle ezilir; bilinmeyen alici icin kalici kuyruk
  anahtari olusmaz (P1-08); cevrimdisi alici icin mesaj kuyruklanir ve
  yeniden baglandiginda teslim edilir; kuyruk muhurludur — ne alici kimligi
  ne mesaj govdesi duz durur; tavan ustu cerceve soketi kapatir.
- **Operator yuzeyleri:** `/metrics`, `/ready` ve `/api/v1/version` bearer
  ister; `/health` public fakat bagimlilik ayrintisi tasimaz (P2-03);
  metrics ciktisinda hesap kimligi yoktur.
- **Rehber:** snapshot 256'lik kovaya yuvarlanir ve ham hesap kimligi
  icermez (P2-01); kota tukendiginde 429 + `Retry-After` (P2-02); yanlis
  batch boyutu, eskimis keyId ve bilinmeyen alan reddedilir.
- **Govde ve alan sinirlari:** buyuk govde 413, bozuk JSON 400 (P1-06);
  tavan ustu one-time prekey sayisi 400; kimliksiz prekey upload 401.
- **Yetki:** SFU oda bilgisi aktif cagri katilimciligi ister (P2-04); FCM
  unregister baska hesabi hedefleyemez.
- **ICE:** yalniz `turns:` sunulur (P2-05).

### Mutasyon dogrulamasi

Ilk yazimda uc WebSocket testi **bos cikti**: "cerceve gelmedi" ret kaniti
degil, cunku kabul edilmis fakat bosta duran bir soket de cerceve
gondermez. Olcut `connectionManager.isOnline(...)` ile degistirildi. Bundan
sonra query-token korumasi kaldirildiginda ilgili test kirmizi oluyor.
Ayni sekilde `senderId` otoritesi istemci degerine cevrildiginde, `/ready`
anonim erisime acildiginda ve snapshot dolgusu kaldirildiginda ilgili
testler kirmizi oluyor.

Taban: 299 Kotlin testi (31 uctan uca) + 250 Flutter testi, 0 skip, temiz
analyze, deployment audit PASS, SBOM/SCA kapisi PASS.

## Kapsam olcumu ve ikinci test dalgasi (2026-08-25)

Soru "her satiri test ettin mi" idi. Cevap olcumle verildi: JaCoCo XML
raporu acildi ve baslangic degeri **%52.5 satir / %36.4 dal** cikti. Yani
hayir — kritik boslukar vardi. Kapatildi.

**Bugunku taban: 486 Kotlin testi, %72.6 satir / %52.2 dal.**
(bot-api %72.1/%57.1, signaling-server %72.9/%49.9.)

### Olcum sifirdi denilen yerler

| Sinif | Onceki | Neden onemli |
|---|---|---|
| `EdDsaJwtVerifier` | %0 | Botun tek kimlik dogrulama siniri |
| `RateLimitGuard` | %0 | 3 katmanli kotuye kullanim siniri |
| `IdempotencyStore` | %0 | Ayni mesajin iki kez gonderilmesini onler |
| `SendPipeline` | %0 | `/v1/send` guard zincirinin tamami |
| `ClientCrudRoutes` | %0 | Bot kimligi uretir ve iptal eder |
| `BotApiConfig` | %14 | Anahtar amac ayrimi, TTL ve token sinirlari |
| `JanusOrchestrator` | %21 | SFU kontrol duzlemi |
| `EmailService` | %0 | Kayit OTP'sinin fail-closed yapilandirmasi |
| `WebSocketRoutesKt` | %21 | Butun mesaj yonlendirme dallari |

### Bu dalgada bulunan gercek hatalar

1. **Bot rate limiter atomik degildi.** `ZREMRANGEBYSCORE -> ZCARD -> ZADD`
   uc ayri gidis-donusteydi; es zamanli istekler siniri birlikte asiyordu.
   Signaling tarafinda ayni hata (P1-02) Lua ile kapatilmis, bot tarafi
   geride kalmisti — dosyadaki yorum "algoritma signaling ile ayni" diyordu,
   degildi. Tek atomik Lua'ya cevrildi; 16 paralel istekten tam 10'unun
   gectigi test mutasyonla dogrulandi.
2. **Rate-limit yaniti serialize edilemiyordu.** `mapOf("error" to "...",
   "retry_after_seconds" to <Long>)` `Map<String, Any>` uretir; kotlinx
   serializer bulamaz. Yani limite takilan istemci 429 ve `Retry-After`
   yerine 500 aliyordu. Ayni sinif hata uc yerde daha vardi
   (`/api/v1/latest-version`, SFU oda yaniti, admin `public_key_size`).
   Tipli yanitlara cevrildi ve kaynak duzeyinde bir regresyon kapisi eklendi.
3. **Mesaj siniflandirmasi push tasiyicisina bagliydi.** Tur yalniz
   `fcmPushSender?.extractMessageType(...)` ile okunuyordu. Push
   yapilandirilmamis bir dagitimda (`fcm: disabled` desteklenen bir durum)
   tur `null` kaliyor ve uc davranis birden bozuluyordu: gecici sinyaller
   (typing, presence) kalici offline kuyruga yaziliyordu — davranis verisi
   tutmama sozlesmesinin dogrudan ihlali; `file_transfer` mesaj kovasina
   dusuyor, dosya icin konan dusuk byte tavani ve kisa TTL uygulanmiyordu;
   bekleyen cagri sinyallerinin temizligi hicbir kaydi silmiyordu.
   Siniflandirma `MessageTypes` altina alindi.
4. **Bot govdesi hala tavansizdi** (onceki dalgada bulundu, burada
   testlerle sabitlendi).

### Eklenen test kumeleri

`EdDsaJwtVerifierTest` (20), `BotRateLimitAndIdempotencyTest` (22),
`SendEndpointTest` (20), `AdminApiTest` (16), `BotApiConfigTest` (13),
`WebSocketRoutingE2ETest` (21), `PreKeyStoreIntegrationTest` (13),
`ConnectionManagerIntegrationTest` (17), `JanusControlPlaneTest` (13),
`EmailServiceConfigTest` (6), `MessageTypesTest` (5),
`ResponseSerializationTest` (1) ve `EndToEndServerTest`'e eklenen kayit,
oturum ve anahtar dagitimi senaryolari (51'e cikti).

Janus icin `FakeJanusServer` yazildi: gercek bir WebSocket uzerinden
`create`/`attach`/`message`/`keepalive` konusur, boylece SFU kontrol
duzlemi — oturum kurma, oda olusturma, sir gonderimi, sessiz gateway
timeout'u — uretim kodunun kendisiyle surulur.

### Testabilite icin yapilan yeniden duzenlemeler

- `BotApiConfig.load(environment)`, `EmailService.validate(environment)`,
  `TurnCredentialService.iceServers(..., environment)` — fail-closed
  yapilandirma kurallari gercek process ortami olmadan surulebilir.
- `Application.signalingModule(...)`, `PublicListener.publicApiModule(...)`,
  `AdminListener.adminModule(...)` — uctan uca testler kopyalanmis bir
  kurulumu degil production yapilandirmasinin kendisini kosar.
- `SendPipeline(clientLookup)` — guard zinciri veritabani olmadan surulur.
- `BotQueuePrivacy.primitives` artik anahtar materyaline bagli onbelleklidir.
  Onceki `by lazy` ilk kullanimda sabitleniyordu: yapilandirma sonradan
  degisirse eski anahtar sessizce kullanilmaya devam ederdi.

### Kapsam kapisi

`coverageGate` gorevi `check`e baglandi: satir %70, dal %50 altina duserse
build kirilir. Esikler bugunku degerin hemen altindadir; amac bir hedef ilan
etmek degil, ulasilan seviyenin sessizce gerilemesini engellemektir. Kapinin
gercekten calistigi esik gecici olarak %95'e cekilerek dogrulandi. Process
giris noktalari (`ApplicationKt`) olcumden cikarildi: `main()` gercek bir
listener acar ve process'i bloklar, test icinde calistirilamaz.

### Hala kapsanmayan ve nedeni

- `SendPipeline` adim 8 (Signal sifreleme + WebSocket teslimi), `SignalingWsClient`,
  `PreKeyBundleFetcher`, `HttpBundlePublisher`: bunlar bot ile signaling
  arasinda calisan gercek bir cift gerektiriyor. Iki servisi ayni testte
  ayaga kaldiran bir kurulum yazilabilir; bugun yok.
- `ApplicationKt.main()`: process giris noktasi, kasten disarida.
- `EmailService.sendMail`: gercek SMTP oturumu gerektirir; yapilandirma
  dogrulamasi kapsamda, gonderim degil.

Taban: 486 Kotlin testi + 250 Flutter testi, 0 skip, temiz analyze,
deployment audit PASS, SBOM/SCA kapisi PASS, kapsam kapisi PASS.

## Harici tarama (strix / Kali sandbox) — 2026-08-25

`strix-claude-code` (github.com/tghastings/strix-claude-code) kuruldu ve
sunucuya karsi calistirildi. Arac, Kali Linux Docker sandbox'i icinde otonom
bir pentest ajani kosuyor; araclar (nmap, nuclei, sqlmap, ffuf, jwt_tool ...)
konteyner icinde calisiyor, host dosya sistemine yazamiyor.

### Kurulum
- Kaynak once okundu ve GitHub clone'u incelenen kopyayla byte-byte
  dogrulandi. Sandbox `--privileged` degil, docker socket mount edilmiyor,
  kaynak `/workspace`'e kopyalaniyor (bind-mount degil).
- Python 3.13 venv, `strix-sandbox:1.3.0` image (4GB).

### Hedef
Uretim `main()`'i PKCS#11 HSM ve verify-full TLS ister; laboratuvarda
saglanamaz. Bunun yerine ayni Ktor modulu (`signalingModule`) gercek
PostgreSQL + Redis ile `runDummyServer` Gradle gorevi uzerinden gercek bir
portta ayaga kaldirildi. Sandbox konteyneri hedefe `host.docker.internal:8080`
ile ulasti (dogrulandi: `/health = 200`). Tarama hem auth'suz hem auth'lu
yuzeyleri (3 hesap + token verildi) standart modda test etti.

### Sonuc
Tam bir aktif pentest yapildi. **Auth bypass, injection, impersonation,
IDOR, DoS basarilamadi.** Denenip **basarisiz** olan saldirilar:
- JWT: `alg:none`/bos-imza reddedildi, zayif-sir sozluk saldirisi kirmadi.
- Operator yuzeyleri: path hileleri (`//metrics`, `/%2e/metrics`,
  `/metrics%00`, `/metrics..;/`, `/api/v1/../metrics`) ve header spoofing
  (X-Forwarded-For/-Host/-Original-URL ...) hepsi 401/404.
- WebSocket: query-string token kimlik dogrulamiyor (yalniz header);
  `senderId`/`timestamp` sunucu tarafindan eziliyor (impersonation yok);
  server-only ve bilinmeyen frame'ler yok sayiliyor; >256KB frame kapatiliyor.
- Govde tavani tum endpoint'lerde (2MB -> 413), OTP brute -> 429.
- Rehber snapshot 256'ya padded (kullanici sayisi sizmiyor), CORS permissive
  degil, swagger/actuator/.git/.env yok.

Tam rapor: `docs/STRIX_SCAN_2026-08-25.md`.

### Bulunan tek gercek bulgu ve duzeltmesi (LOW)
Butun yanitlarda HTTP guvenlik basliklari eksikti (defense-in-depth).
`SecurityHeaders` Ktor plugin'i eklendi: `X-Content-Type-Options: nosniff`,
`X-Frame-Options: DENY`, `Content-Security-Policy: default-src 'none';
frame-ancestors 'none'`, `Referrer-Policy: no-referrer` ve tum API'de
`Cache-Control: no-store` (TURN kimlikleri ve rehber snapshot'i ara
proxy'lerde onbelleklenmesin). Uc e2e test eklendi; canli sunucuda curl ile
dogrulandi. Yeni bagimlilik yok (`createApplicationPlugin`).

Taban: 489 Kotlin testi + 256 Flutter testi, 0 skip, temiz analyze, coverage
kapisi PASS, deployment audit PASS, SBOM/SCA PASS.

### Deep-mode tarama denemesi (2026-08-25)

`-m deep` uc kez denendi; ucunde de nested tarama ajani (Opus 4.8) Claude'un
**gercek-zamanlri siber guvenlik korumasina** takildi:

```
API Error: Opus 4.8's safeguards flagged this message ... Details: `[cyber]`
```

Deep modun agresif sistem prompt'u bu korumayi tetikliyor; bir kez recon
asamasindan sonra, iki kez basta. Guardrail bilincli olarak asilmadi.

Bloktan **once** kosan auth'suz recon (deep2), sertlestirmenin ayakta
oldugunu tekrar dogruladi: authZ ayrimi (`/api/v1/version` kullanici
token'ini 401'liyor), WS auth (query-string token reddi dahil), `alg:none`
reddi, metrics/version'da sir sizmasi yok, ve yeni guvenlik basliklari tum
yanitlarda mevcut. Kismi rapor: `docs/STRIX_DEEP_RECON_2026-08-25.md`.

Otoritatif harici sonuc **standart mod** taramasidir (tam kosdu):
`docs/STRIX_SCAN_2026-08-25.md`. Deep modun ek degeri bu platformda
guardrail nedeniyle alinamadi. Whitebox kaynak taramasi (`-t <kaynak yol>`,
savunma amacli kod incelemesi) bu korumayi tetiklemeden ek kapsam saglar.

## Whitebox kaynak taramasi (strix) — 2026-08-25

Deep mod nested ajanda siber koruma nedeniyle tamamlanamayinca, whitebox
kaynak taramasi calistirildi: kaynak (`.kt/.sql/.kts/...`, build haric, 214
dosya / ~24k satir) sandbox `/workspace`'ine kopyalandi ve nested ajan
semgrep + dogrudan kod okuma ile inceledi (savunma amacli; siber koruma
tetiklenmedi). Tam rapor: `docs/STRIX_WHITEBOX_2026-08-25.md`.

Genel degerlendirme: enjeksiyon/RCE/deserialization/SSRF/auth-bypass/IDOR
bulunmadi; SQL tamamen parametrize, atomik Redis/Postgres gecisleri, fail-
closed startup, container/deploy sertlestirmesi dogru. Uc gercek bulgu
cikti — hepsi prekey alt sistemi + cross-instance iptal — ve **hepsi
duzeltildi**:

### Bulgu 1 (MEDIUM) — prekey fetch rate limit yoktu
`GET /api/v1/users/{userId}/prekeys` her cagride hedefin bir one-time
prekey'ini tuketiyor ama diger auth'lu endpoint'lerin aksine rate limit yok.
Bilinen bir UUID'nin havuzu bosaltilip yeni oturumlar icin X3DH forward
secrecy dusurulebiliyordu. **Fix:** `prekey_fetch` rate limit (120/saat per
caller). Test + mutasyon dogrulamasi.

### Bulgu 2 (MEDIUM) — prekey upload/refresh sinirsiz, refresh validation'i atliyordu
`/prekeys/refresh` `hasSaneKeyMaterial()`'i cagirmiyordu (keyId araligi,
boyut, sayi, tekrar kontrolu yok) ve iki yazma yolu da rate-limitsiz/
tavansizdi; tek hesap `one_time_prekeys` tablosunu sinirsiz buyutebiliyordu.
**Fix:** `List<PreKeyEntry>.hasSaneOneTimeKeys()` refresh'e uygulandi,
`prekey_write` rate limit (30/saat), hesap basina `MAX_STORED_ONE_TIME_PREKEYS
= 1000` tavani (asilirsa 409 `prekey_pool_full`). Testler.

### Bulgu 3 (LOW) — instance'lar arasi iptal gecikmesi
Epoch onbellegi process-yerel + 10s TTL; yatay olceklemede logout/silme
yapan instance kendi kopyasini dusurse de digerleri iptal edilmis access
token'i 10s'ye kadar kabul ediyordu. **Fix:** Redis pub/sub kanali
(`signaling:credential_invalidate`); epoch rotasyonu (logout) ve hesap silme
iptali butun instance'lara yayar, her instance bir abone thread ile dinleyip
yerel kopyayi dusurur. Kalicilik hala PostgreSQL'de (Redis yalniz yayin,
dogruluk kaynagi degil); yayin gitse bile eski 10s davranisina donulur
(fail-safe). Gercek Redis ile 4 entegrasyon testi; deployment gate
guncellendi.

Taban: 497 Kotlin testi + 259 Flutter testi, 0 skip, temiz analyze, coverage
kapisi PASS, deployment audit PASS.

## Deep-scan (interaktif) + SonarQube + code-smell temizligi — 2026-08-25 (ek)

**Deep scan** interaktif TTY'de tam kostu (siber koruma modeli Opus 4.8'e
dusurdu ama devam etti). Iki bulgu, ikisi de duzeltildi:
- (CVSS 4.8) `POST /api/v1/auth/refresh` tek rate-limit'siz credential
  endpoint'iydi. `auth_refresh` rate limit eklendi (30/10dk per IP). Test.
- (CVSS 3.1) tamamlayici izolasyon basliklari eksik. `SecurityHeaders`'a
  Permissions-Policy, COOP, COEP, CORP, X-Permitted-Cross-Domain-Policies
  eklendi; HSTS reverse-proxy'ye (TLS terminator). Test.

Raporun "test edilemedi" dedigi WS senderId-spoof / server-only frame /
prekey-fcm mass-assignment yuzeyleri whitebox testlerinde zaten kapali
(ikinci lab kimligi black-box'ta alinamadigi icin gorulememis). Rapor:
`docs/STRIX_DEEP_2026-08-25.md`.

**SonarQube** (yerel community 26.8, kod disari gitmedi): 0 bug, 0
vulnerability (3 FP triyaj), 0 hotspot, 25 acik code smell (hepsi
maintainability-A). Detay: `docs/SONARQUBE_2026-08-25.md`.

**Code-smell temizligi:** 3 dead `ts`, 14 bos catch yoruma, 2 idiom.

Taban: 499 Kotlin testi + 272 Flutter testi, 0 skip, temiz analyze, coverage
kapisi PASS, deployment audit PASS.
