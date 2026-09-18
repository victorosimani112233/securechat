# Test sunucusu kurulum runbook'u

Hedef: tek VDS (4 vCPU / 8 GB / 200 GB) uzerinde mesajlasma, 1:1 arama ve
kucuk grup aramasi calisir durumda.

Onemli: bu sunucunun ayri bir "test modu" yoktur.
`ProductionDeploymentPolicy.validate()` kosulsuz calisir, yani test kurulumu
da production sartlarini saglamak zorundadir. Asagidaki adimlar bu yuzden
kisaltilamaz.

Tahmini sure: ilk kurulumda 4-6 saat.

---

## Faz 0 — VDS'e dokunmadan once

Bunlar olmadan kuruluma baslamanin anlami yok:

- [ ] **Alan adi** ve ona isaret eden A kaydi (or. `test.example.com`).
      Sertifika ve TURN TLS bunsuz olmaz.
- [ ] **SMTP hesabi** (kayit OTP'si icin). Saglayici starttls veya ssl
      desteklemeli; duz SMTP reddedilir.
- [ ] **Firebase projesi** ve service-account JSON'u (push wake-up icin).
- [ ] **Container registry** (private). Compose mutable tag kabul etmez;
      `image@sha256:<digest>` zorunludur.
- [ ] **Build makinesi** — asagida "Faz 5" bunun neden ayri bir konu
      oldugunu anlatiyor.
- [ ] **Cevrimdisi makine** — Sealed Sender trust root'unu uretmek icin.
      Internete bagli olmayan bir laptop yeterli.

---

## Faz 1 — VDS temel kurulum

```bash
# Debian 12 / Ubuntu 22.04 varsayimi
apt update && apt upgrade -y
apt install -y docker.io docker-compose-v2 postgresql-16 nginx \
               coturn softhsm2 opensc openssl ufw

# Swap kapali olmali: sifreli ciphertext diske yazilmamalidir.
swapoff -a
sed -i '/swap/d' /etc/fstab

# Core dump kapali.
echo 'kernel.core_pattern=|/bin/false' >> /etc/sysctl.d/99-securechat.conf
sysctl --system

ufw default deny incoming
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 3478/tcp && ufw allow 3478/udp     # TURN
ufw allow 5349/tcp && ufw allow 5349/udp     # TURN TLS
ufw allow 49160:49200/udp                    # TURN relay araligi
ufw enable
```

TLS sertifikasi:

```bash
apt install -y certbot
certbot certonly --standalone -d test.example.com
```

---

## Faz 2 — PostgreSQL + TLS

`DATABASE_URL` `sslmode=verify-full` zorunlu tutar. Localhost'ta bile
sertifika gerekir ve JVM'in o sertifikayi dogrulayabilmesi gerekir.

```bash
sudo -u postgres psql -c "CREATE USER securechat WITH PASSWORD '<database_password degeri>';"
sudo -u postgres psql -c "CREATE DATABASE securechat OWNER securechat;"
```

Sunucu sertifikasi (self-signed, CN = baglanacagin host adi):

```bash
cd /var/lib/postgresql/16/main
openssl req -new -x509 -days 825 -nodes \
  -out server.crt -keyout server.key -subj "/CN=localhost"
chmod 0600 server.key && chown postgres:postgres server.key server.crt
```

`postgresql.conf`:

```
ssl = on
listen_addresses = 'localhost'
shared_buffers = 384MB
max_connections = 50
```

`pg_hba.conf` — sadece TLS'li baglanti:

```
hostssl securechat securechat 127.0.0.1/32 scram-sha-256
```

JVM'in sertifikaya guvenmesi icin truststore hazirla ve container'a mount et:

```bash
keytool -importcert -alias pg-test -file server.crt \
  -keystore /srv/securechat/pg-truststore.jks -storepass changeit -noprompt
```

Sonra `SIGNALING_JAVA_OPTS` icine ekle:
`-Djavax.net.ssl.trustStore=/run/pg/truststore.jks -Djavax.net.ssl.trustStorePassword=changeit`
(ve compose'a bu dosyayi read-only mount et).

> Bu adim atlanirsa sunucu `sslmode=verify-full` yuzunden hicbir sekilde
> baglanamaz ve hata mesaji yaniltici olur.

---

## Faz 3 — SoftHSM (PKCS#11)

Private contact directory OPRF anahtari HSM'de olmak zorunda.
Test icin SoftHSM2 yeterli; production'da gercek HSM.

```bash
mkdir -p /var/lib/softhsm/tokens
softhsm2-util --init-token --slot 0 --label securechat-oprf \
  --so-pin <rastgele> --pin "$(cat /srv/securechat/secrets/directory_hsm_pin)"

# 3072-bit RSA OPRF anahtari uret (export edilemez)
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so \
  --login --pin "$(cat /srv/securechat/secrets/directory_hsm_pin)" \
  --keypairgen --key-type rsa:3072 --label securechat-directory-key
```

Env:

```
DIRECTORY_OPRF_KEY_BACKEND=PKCS11
DIRECTORY_OPRF_PKCS11_PROVIDER=<java.security icinde tanimli provider adi>
DIRECTORY_OPRF_KEY_ALIAS=securechat-directory-key
DIRECTORY_HSM_PIN_FILE=/srv/securechat/secrets/directory_hsm_pin
```

SunPKCS11 provider'i JVM tarafinda bir config dosyasiyla tanimlanir ve
container icine mount edilmelidir.

---

## Faz 4 — Secret'lar

### 4a. Cevrimdisi makinede: Sealed Sender anahtarlari

```bash
java -cp signaling-server-all.jar \
  com.securechat.signaling.tools.SealedSenderOfflineKeygen /media/usb/sealed-sender
```

Uretilen dort dosyadan:

| Dosya | Nereye |
|---|---|
| `trust_root_private_key` | **Cevrimdisi kasada kalir. Sunucuya asla kopyalanmaz.** |
| `trust_root_public_key` | Sunucu + mobil build (`SECURECHAT_SEALED_SENDER_TRUST_ROOT`) |
| `server_private_key` | Sunucu |
| `server_certificate` | Sunucu |

Sunucuda trust root private key bulunursa `ProductionDeploymentPolicy`
baslamayi reddeder — bu kasitli.

### 4b. VDS'te: kalan secret'lar

```bash
./generate_test_secrets.sh /srv/securechat/secrets
```

Betik 17 dosyayi rastgele ve birbirinden farkli uretir (preflight ayni degerin
iki amaca verilmesini reddeder). Elle eklenecekler:

```bash
cd /srv/securechat/secrets
printf '%s' '<smtp sifresi>' > smtp_password
cp /path/firebase-service-account.json firebase_service_account
cp /media/usb/sealed-sender/server_certificate     sealed_sender_server_certificate
cp /media/usb/sealed-sender/trust_root_public_key  sealed_sender_trust_root_public_key
cp /media/usb/sealed-sender/server_private_key     sealed_sender_server_private_key
chmod 0600 *
```

Bot socket dizini:

```bash
install -d -o 10002 -g 10002 -m 0700 /srv/securechat/bot-sockets
```

---

## Faz 5 — Image build (dikkat: bu snapshot'tan dogrudan calismaz)

`build_privacy_images.sh` uc sey istiyor ve bu sunucu snapshot'inda ucu de yok:

1. `dart tool/audit_server_deployment_privacy.dart` — **flutter_securechat**
   projesinin `tool/` dizininde. Bu snapshot yalniz sunucuyu iceriyor.
2. `SOURCE_COMMIT` — 40 hex commit id. Snapshot bir git deposu degil.
3. Dart SDK.

Yani image'lari **tam depoyu** (sunucu + flutter) barindiran bir build
makinesinde uretmelisin:

```bash
JRE_IMAGE='registry.example/jre@sha256:<64-hex>' \
SIGNALING_IMAGE_TAG='securechat-signaling:candidate' \
BOT_API_IMAGE_TAG='securechat-bot-api:candidate' \
SOURCE_COMMIT="$(git rev-parse HEAD)" \
./build_privacy_images.sh
```

Sonra private registry'ye push et ve registry'nin verdigi digest'leri kullan.
Betik ayrica testleri `--rerun-tasks` ile kosar; yesil olmayan agactan image
cikmaz.

---

## Faz 6 — Janus, coturn, nginx

**coturn** (`/etc/turnserver.conf`):

```
listening-port=3478
tls-listening-port=5349
realm=test.example.com
use-auth-secret
static-auth-secret=<turn_secret dosyasinin icerigi>
cert=/etc/letsencrypt/live/test.example.com/fullchain.pem
pkey=/etc/letsencrypt/live/test.example.com/privkey.pem
min-port=49160
max-port=49200
no-cli
```

`static-auth-secret` ile `TURN_SECRET` **birebir ayni** olmali; yoksa
istemciler TURN'e authenticate olamaz ve NAT arkasindaki aramalar sessizce
kurulamaz.

**Janus**: 4 vCPU'da SFU'yu kapali birakmani oneririm. Kapaliyken grup
aramalari mesh kalir (sesli 8, goruntulu 6 kisiye kadar) ve sunucu CPU'su
harcanmaz. Acmak istersen `JANUS_WS_URL` + `JANUS_PUBLIC_WS_URL` (wss
zorunlu) ver ve `SfuPolicy` kabul beyanini isaretle.

**nginx**: `reverse-proxy.conf` referans alinir. Uc davranis zorunlu —
access log kapali, WebSocket upgrade'inde `Authorization` header'inin
korunmasi, `token=` query parametresi tasiyan isteklerin reddi.
Upstream `127.0.0.1:8080`.

---

## Faz 7 — Deploy

`/srv/securechat/.env`:

```bash
# 8 GB kutuda production varsayilanlari fazla gelir:
SERVICE_MEMORY_LIMIT=1g
SERVICE_CPU_LIMIT=2.0
REDIS_MAXMEMORY=768mb
REDIS_MEMORY_LIMIT=1g

REDIS_IMAGE=registry.example/redis@sha256:<64-hex>
SIGNALING_IMAGE=registry.example/securechat-signaling@sha256:<64-hex>
BOT_API_IMAGE=registry.example/securechat-bot-api@sha256:<64-hex>

DATABASE_URL=jdbc:postgresql://127.0.0.1:5432/securechat?sslmode=verify-full
DATABASE_USER=securechat
TRUSTED_PROXIES=127.0.0.1
SIGNALING_BIND_IP=127.0.0.1

SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=<kullanici>
SMTP_FROM=noreply@test.example.com
SMTP_TLS=starttls

TURN_HOST=test.example.com
TURN_TLS_PORT=5349

BOT_SOCKET_DIR=/srv/securechat/bot-sockets

# ... tum *_FILE yollari /srv/securechat/secrets/ altini gosterir
```

Once **salt-okunur** preflight (hicbir container'a dokunmaz):

```bash
set -a && . /srv/securechat/.env && set +a
./deploy_privacy_stack.sh --check-only
```

Preflight; image digest'lerini, DB URL'sini, 22 secret dosyasinin izin/boyut/
tekilligini ve bot anahtar ciftinin eslesmesini dogrular. Gecerse:

```bash
SECURECHAT_DEPLOY_CONFIRMATION='deploy-hardened-privacy-stack' \
  ./deploy_privacy_stack.sh --apply
```

Flyway V1-V22 migration'lari ilk acilista otomatik uygulanir.

---

## Faz 8 — Dogrulama

```bash
# Liveness (anonim)
curl -s https://test.example.com/health

# Readiness (bearer korumali)
curl -s -H "Authorization: Bearer $(cat /srv/securechat/secrets/metrics_token)" \
  http://127.0.0.1:8080/ready
```

Beklenen: `database: ok`, `redis: ok`, `privacy: ok`.

Sema surumu kontrolu:

```bash
sudo -u postgres psql securechat -c \
  "SELECT version FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 1;"
# 22 donmeli
```

Iki gercek cihazla fonksiyonel tur:

- [ ] Kayit + e-posta OTP
- [ ] Iki hesap arasi mesajlasma (online)
- [ ] Alici kapaliyken mesaj, sonra acilinca teslim
- [ ] **ACK sonrasi Redis'te kayit kalmadigi** —
      `securechat_messages_delivery_total{result="acknowledged"}` artmali
- [ ] Fotograf / dosya / sesli mesaj
- [ ] 1:1 sesli ve goruntulu arama (ayni agda ve farkli aglarda — ikincisi
      TURN'u test eder)
- [ ] 3-4 kisilik grup aramasi
- [ ] Hesap silme ve sonrasinda token'in reddedilmesi

---

## Sik yapilan hatalar

| Belirti | Sebep |
|---|---|
| Sunucu aciliyor gibi, aninda kapaniyor | `ProductionDeploymentPolicy` kapilarindan biri — log'un ilk satirina bak |
| `Production requires an offline-issued SEALED_SENDER_SERVER_CERTIFICATE` | Faz 4a atlanmis |
| `The Sealed Sender trust-root private key must not be present` | Trust root private key yanlislikla sunucuya kopyalanmis |
| DB'ye hic baglanamiyor | Faz 2'deki truststore adimi atlanmis |
| `reuses secret material assigned to ...` | Ayni deger iki secret dosyasina yazilmis |
| NAT arkasinda arama kurulamiyor | `static-auth-secret` ile `TURN_SECRET` farkli |
| Rate limit herkese ayni uygulaniyor | `TRUSTED_PROXIES` bos |
| Her istemci limitleri asabiliyor | `TRUSTED_PROXIES` fazla genis (`0.0.0.0/0`) |
