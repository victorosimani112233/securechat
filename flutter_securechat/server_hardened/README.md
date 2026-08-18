# Hardened server target

Bu dizin, kok Kotlin kaynak agacina dokunmadan uretilen production sunucu
hedefidir. Flutter istemcinin privacy garantisi yalniz bu hedef veya ayni
kontrolleri bagimsiz olarak kanitlanmis bir deployment ile gecerlidir. Kok
`signaling-server`/`bot-api` referanstir ve production artefakti degildir.

Baglayici veri/retention sozlesmesi:
[`../docs/SERVER_DATA_PRIVACY_AUDIT.md`](../docs/SERVER_DATA_PRIVACY_AUDIT.md).

## Zorunlu secret'lar

Asagidaki Base64 alanlar decode edildiginde tam 32 byte olmali ve birbirinden
bagimsiz uretilmelidir:

- `PRIVACY_INDEX_KEY`: HMAC blind index ve pseudonym anahtari.
- `OFFLINE_QUEUE_ENCRYPTION_KEY`: Redis offline envelope AES-256-GCM anahtari.
- `FCM_TOKEN_ENCRYPTION_KEY`: push token `v4` AES-256-GCM anahtari.
- `BOT_MASTER_KEY`: bot identity/session private state anahtari.
- `BOT_QUEUE_ENCRYPTION_KEY`: bot queue/idempotency zarf anahtari.

Ayrica zorunludur:

- `DIRECTORY_OPRF_KEY_BACKEND=PKCS11` production tercihiyle
  `DIRECTORY_OPRF_PKCS11_PROVIDER`, `DIRECTORY_OPRF_KEY_ALIAS` ve
  `DIRECTORY_OPRF_KEYSTORE_PIN`; veya izole gelistirmede
  `DIRECTORY_OPRF_KEY_BACKEND=PKCS8` + `DIRECTORY_OPRF_PRIVATE_KEY`. Key yalniz
  private contact discovery icin uretilmis en az 3072-bit RSA/65537 olmalidir;
- `JWT_SECRET`, `TURN_SECRET`, `DATABASE_PASSWORD` ve gerekiyorsa
  `REDIS_PASSWORD`;
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_TLS=starttls|ssl` ve SMTP auth
  kullaniliyorsa `SMTP_USERNAME` + `SMTP_PASSWORD`;
- `METRICS_BEARER_TOKEN`, `BOT_METRICS_BEARER_TOKEN` ve `BOT_ADMIN_TOKEN`
  (her biri en az 32 karakter);
- Firebase Admin service-account credential'i; mobil istemciye konmaz.

Secret'lar image, Git, DB backup, log veya mobil bundle'a eklenmez. Bir key'in
birden fazla amacla kullanilmasi startup validation tarafindan reddedilir.
Production secret'lari direct environment degeri yerine read-only
`NAME_FILE=/run/secrets/...` ile verilir; ikisi birlikteyse, dosya relative,
symlink, bos veya 64 KiB'dan buyukse startup fail-closed durur.
OPRF key'i production'da export edilemeyen, islem/rate audit'i kimlik verisi
tutmayan bir HSM/KMS sinirinda tutulmalidir. JVM PKCS#11 backend'i key'i export
etmeden raw RSA private operation'i provider icinde calistirir ve provider,
alias veya certificate yoksa PKCS#8'e geri dusmeden startup'i durdurur. PKCS#8
backend'inde host+DB'nin birlikte ele gecirilmesi telefon sozluk saldirisini
yeniden mumkun kilar; bu backend production release icin kabul edilmez.

Izole gelistirme anahtari ornegi (uretilen PEM/DER veya Base64 degeri repoya
eklenmez):

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -pkeyopt rsa_keygen_pubexp:65537 -out directory-oprf.pem
openssl pkcs8 -topk8 -nocrypt -in directory-oprf.pem -outform DER \
  | base64 -w0
```

## Privacy-first varsayilanlar

| Ayar | Varsayilan | Kod ust siniri |
|---|---:|---:|
| `OFFLINE_QUEUE_TTL_SECONDS` | 900 sn | 3600 sn |
| `OFFLINE_FILE_TTL_SECONDS` | 300 sn | 900 sn |
| `CONSUMED_PREKEY_RETENTION_HOURS` | 1 saat | 168 saat |
| `PUSH_TOKEN_RETENTION_DAYS` | 30 gun | 90 gun |
| `API_CLIENT_RETENTION_DAYS` | 30 gun | 90 gun |
| `TURN_CREDENTIAL_TTL_SECONDS` | 600 sn | 3600 sn |
| `BOT_OUTBOUND_TTL_SECONDS` | 900 sn | 3600 sn |
| `BOT_IDEMPOTENCY_TTL_SECONDS` | 900 sn | 3600 sn |

Daha uzun deger islevsel bir urun karari degil, acik bir privacy risk kabuludur.
Kod ust siniri asan config ile process baslamaz.

Redis kesinlikle gecici RAM store'u olarak calismalidir. Hem signaling hem bot
process'i startup'ta `CONFIG GET appendonly save` sonucunu dogrular;
`appendonly=no` ve bos `save` schedule'i disinda listener acmaz. Ornek Redis
baslatma parametreleri: `redis-server --appendonly no --save ""`. CONFIG okuma
izni olmayan managed Redis, no-disk garantisi kanitlanamadigi icin fail-closed
reddedilir. Ayrica volume/snapshot/host-swap katmaninda Redis memory dump'i
alinmadigi deployment politikasiyla dogrulanmalidir.

## Kalici veri korumalari

- Redis offline ve bot key'leri ham UUID tasimaz; degerler randomized AEAD
  zarfindadir. Basarili socket gonderiminden sonra kayit silinir.
- Push token satirlari blind user index + AAD-bagli `v4` AEAD kullanir. V14
  push ve bot session tablolarindaki raw-UUID compatibility kolonlarini
  donusum tamamlanmadan kaldirmayi reddeder, sonra fiziksel olarak siler.
- Bot API gorunen ad/allow-list alanlari AEAD'dir; expired veya revoked
  credential policy satirlari varsayilan 30, en cok 90 gun sonra zorunlu
  retention transaction'inda silinir. Decrypt edilmis policy positive RAM
  cache'e alinmaz; her bot istegi DB'de revoke/expiry durumunu yeniden
  dogrular.
- Rehber discovery girdileri server'a gonderilmez. Client her sorguyu blind-RSA
  OPRF ile korur ve 256 elemana doldurur; server snapshot'i token-turevi label
  ve token-AEAD ile sealed user ID tasir. DB yalniz finalized OPRF tokeni ve
  OPRF public key ID'sini tutar. Ortak istemci anahtariyla acilabilen
  `encrypted_phone` veya kalici caller-contact sosyal grafigi yoktur.
- Grup sosyal grafigi hicbir kalici server store'una yazilmaz. Eski
  `group_members` tablosu V9'da fiziksel olarak silinir. Grup mesaji ve dosyasi
  her alici icin ayri direct Signal zarfi olarak route edilir; grup arama route
  nonce'u yalniz aktif cagri boyunca process RAM'de tutulur.
- Security eventleri DB/log satiri uretmez; yalniz event turu bazinda kimliksiz,
  zamansiz process-RAM sayaclari artar. V10 eski `audit_log` tablosunu siler.
- Push payload yalniz `securechat_wake_v2` generic sinyalidir.
- Edit/delete/reaction/pin, receipt, typing ve disappearing timer yalniz
  ordinary direct Signal ciphertext icindeki sabit 16 KiB `CHATCTRL:v2`
  paketidir. Plaintext legacy control frame'leri route edilmez. Admin audit
  outer event'i yalniz `PRIVATE_EVENT` olabilir.
- OTP backdoor yoktur; SMTP veya PostgreSQL/Redis yoksa listener acilmaz.
- Retention cleanup listener'dan once zorunludur. Runtime cleanup hatasinda
  privacy health kapanir, aktif socket'ler sonlandirilir ve trafik basarili
  retry'ya kadar fail-closed reddedilir.
- Metrics bearer-authenticated; request body, token ve identity loglanmaz.

## Migration ve baslatma sirasi

Yalniz `deploy/deploy_privacy_stack.sh --check-only` kapisi kullanilir;
`PRIVACY_PRODUCTION_MODE=true`, tum image digest'leri ve PostgreSQL
`sslmode=verify-full` olmadan binary veya compose baslatilamaz. Kok
`../infra/docker-compose.yml` production icin yasaktir.

1. PostgreSQL ve Redis backup politikasinin bu retention sozlesmesine uydugunu
   dogrula; offline Redis snapshot'i tercihen kapat.
2. Tum bagimsiz secret'lari secret manager'dan sagla.
3. Populated bir V13 kurulumu guncelliyorsan once V13 binary'sini tek instance
   calistirip push ve bot private-row donusumunu tamamla. Yalniz aggregate
   `COUNT(*)` ile `fcm_tokens.user_id IS NOT NULL`, non-v4 push zarf ve
   `bot_signal_session.recipient_user_id IS NOT NULL` sonucunun sifir oldugunu
   dogrula. Fresh kurulumda bu staging adimi gerekmez.
4. Signaling server'i tek instance ile baslat. Flyway V1-V14'u uygular; V4 bot
   state, V5 push, V6 telefon, V7 gecis-donemi private grup dizini, V8 metadata
   minimizasyonu, V9 kalici grup grafiginin ve V10 behavioral audit tablosunun
   tamamen silinmesi ve V11 user-prekey kullanim zaman cizelgesinin
   kaldirilmasi, V12 push retention zamaninin gun duzeyine indirilmesi ve V13
   legacy telefon blind index'inin private-directory OPRF token semasina
   gecisidir. V14 push ve bot session tablolarindaki nullable raw-UUID legacy
   kolonlarini fiziksel olarak kaldirir; eski satir bulursa veri silmeden
   migration'i durdurur.
5. PostgreSQL+Redis health check gecmeden listener acilmaz.
6. Migration tamamlandiktan sonra signaling instance'larini olcekle.
7. Bot API'yi en son baslat; private session/client dogrulamasi
   basarisizsa bot fail-closed durur.

`ALLOW_LEGACY_PLAINTEXT_QUEUE=true` yalniz izole ve kisa bir cutover penceresi
icin vardir. Production release config'inde false/eksik olmalidir; eski entry
kalmaz kalmaz tekrar kapatilir.

## Dogrulama

```bash
env \
  PRIVACY_INDEX_KEY='<base64-32-byte>' \
  OFFLINE_QUEUE_ENCRYPTION_KEY='<different-base64-32-byte>' \
  ./gradlew :signaling-server:test :bot-api:test --offline
```

Test paketi unit testlere ek olarak gercek `postgres:16` Testcontainers ile
V1-V14 migration, legacy iliski varken V14 fail-closed davranisi, final exact
schema, push-token AAD ve gun-bucket retention, kalici grup/audit/prekey
timeline silinmesi ve hesap silme sinirlarini sorgular.

Guncel sonuc signaling+bot toplam 64/64 test, sifir failure/error/skip'tir.
Kalici log appender'i, runtime log seviye acma, direct secret env, guvensiz DB
TLS, secret amac tekrari ve production policy bypass'i statik/Kotlin
kapilarinda reddedilir.

Artefakt:

```bash
./gradlew :signaling-server:fatJar :bot-api:installDist --offline
```

Kodun yesil olmasi deployment'in kaniti degildir. Production oncesi secret
ayrimi, migration sonucu, Redis snapshot, backup TTL, FCM service account,
SMTP TLS, log aggregation ve hesap-silme runbook'u gercek ortamda ayrica
denetlenmelidir.
