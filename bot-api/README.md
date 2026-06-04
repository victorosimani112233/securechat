# SecureChat Bot API

Admin (tek kullanıcı) için **send-only** otomasyon API'si. Cron, CI/CD, monitoring scriptleri gibi farklı caller'lar Ed25519-imzalı JWT ile authenticate olur ve belirli kişi/gruplara önceden tanımlı allow-list dahilinde mesaj gönderir. Okuma, profil yönetimi, grup yönetimi **YOKTUR** — tek endpoint: `POST /v1/send`.

## Mimari

- **Ayrı container** (`bot-api`), sadece internal Docker network. Nginx üzerinden ASLA erişilmez.
- **3 listener** (TCP localhost — Unix socket'e geçiş ileride):
  - `:8091` Public — `POST /v1/send` (tek endpoint, route ağacı fiziksel olarak kısıtlı + PathWhitelistInterceptor defense-in-depth)
  - `:8092` Admin — `/admin/clients/*` + `/admin/emergency/*` (X-Admin-Token gate)
  - `:8090` Health/Metrics — `/health` ve `/metrics`
- **Auth**: Ed25519 imzalı JWT (EdDSA, RFC 8037), exp ≤ iat+60s, jti replay nonce (Redis 120s), body_hash claim.
- **Bot identity**: kendi Signal device'ı olarak kayıtlı ayrı user (`bot_user_id`). Linked device değil — recipient'lar için ayrı bir contact gibi görünür.
- **E2E korunur**: bot kendi `IdentityKeyPair`'ini üretir, recipient'lara libsignal `SessionCipher` ile şifreli gönderir. Plaintext sunucuda persist edilmez (yalnızca SendPipeline RAM'inde, send süresince).
- **3 katmanlı rate limit** + per-recipient daily limit + global emergency brake.
- **Idempotency** (`X-Idempotency-Key` zorunlu, 24h cache).

## Setup

### 1. Secret'ları üret

```bash
# Bot identity private key'i AES-256-GCM ile saran 32 byte master key
openssl rand -base64 32   # → BOT_MASTER_KEY

# Admin endpoint'lerine erişim için token (X-Admin-Token)
openssl rand -hex 32      # → BOT_ADMIN_TOKEN
```

`infra/.env` dosyasına ekle:
```
BOT_MASTER_KEY=<yukaridaki base64>
BOT_ADMIN_TOKEN=<yukaridaki hex>
```

### 2. ⚠️ KEY ESCROW UYARISI

`BOT_MASTER_KEY` kaybolursa:
- Bot'un kayıtlı tüm Signal session'ları **geri dönülemez** şekilde kaybolur.
- Recipient cihazlarında "identity changed" uyarısı çıkar.
- Bot bootstrap'i yeniden çalışır; recipient'lar yeni identity'i kabul etmek zorunda kalır.

**Mutlaka escrow yap:**
1. `.env` dosyası (operasyonel)
2. Admin'in kişisel GPG public key'i ile şifreli offline backup:
   ```bash
   echo "$BOT_MASTER_KEY" | gpg --encrypt --recipient YOUR_KEY_ID > bot-master-key.gpg
   # Bu dosyayı güvenli/offline bir yerde sakla
   ```

### 3. Build + deploy

```bash
# Fat JAR build
./gradlew :bot-api:fatJar :bot-admin-cli:installDist

# Docker image
cd infra
docker compose build bot-api

# signaling-server V3 migration uygula (bot-api'den ÖNCE)
docker compose up -d backend
docker compose logs backend | grep "Flyway"   # V3 uygulandi mi gor

# Bot-api'yi baslat
docker compose up -d bot-api
docker compose logs -f bot-api
```

İlk açılışta `bot-api` kendi Signal identity'sini üretir, `users` tablosuna direkt kayıt yapar, signaling-server'a prekey bundle yükler. Sonraki açılışlarda mevcut identity kullanılır.

## Client Ekleme Akışı

### Caller (API kullanıcısı) tarafı

```bash
# Ed25519 keypair üret
ssh-keygen -t ed25519 -f my-bot-key -N ""
# → my-bot-key (private — sadece sende)
#   my-bot-key.pub (public — admin'e yolla)

# Public key'in fingerprint'ini telefonda doğrulamak için göster:
ssh-keygen -lf my-bot-key.pub
```

`my-bot-key.pub` içeriğini güvenli kanaldan (SecureChat üzerinden, e-posta DEĞİL) admin'e yolla.

### Admin tarafı

```bash
# bot-admin CLI çalıştır (BOT_ADMIN_TOKEN env'i set olmalı)
export BOT_ADMIN_TOKEN=<env'deki deger>
export BOT_ADMIN_URL=http://127.0.0.1:8092   # veya container icinden

# Yeni client ekle
bot-admin client add \
  --name "monitoring-bot" \
  --pubkey-file ./received-key.pub \
  --allow "user:<recipient-uuid>,group:<group-id>" \
  --rate-per-hour 50 \
  --expires-in-days 90 \
  --show-fingerprint     # Public key fingerprint'ini gosterir; telefonda dogrula

# Çıktı: {"kid":"k_a1b2c3...","name":"monitoring-bot"}
```

`kid` değerini caller'a geri yolla. Caller artık `kid` + private key ile JWT imzalayabilir.

## Caller Tarafı: JWT Format

Her istek için yeni JWT mintlenir (1 kez kullanım, 60s ömür).

```
Header:
  { "alg": "EdDSA", "typ": "JWT", "kid": "<kid>" }

Payload:
  {
    "aud": "securechat-bot-api",
    "iat": <unix-now>,
    "exp": <iat + 60>,
    "jti": "<uuid>",
    "bh":  "<base64url SHA-256 of raw body>"
  }

Signature: Ed25519(private_key, header_b64 + "." + payload_b64)
```

### Örnek Python script

```python
import base64, json, time, uuid, hashlib, requests
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import load_ssh_private_key

KID = "k_a1b2c3..."
PRIV_KEY = load_ssh_private_key(open("my-bot-key", "rb").read(), password=None)

def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def send(recipient_ref, plaintext_bytes):
    body = json.dumps({
        "recipientRef": recipient_ref,         # "user:UUID" veya "group:ID"
        "plaintextBase64": base64.b64encode(plaintext_bytes).decode(),
        "messageType": "text"
    }).encode()
    body_hash = b64url(hashlib.sha256(body).digest())

    now = int(time.time())
    header  = b64url(json.dumps({"alg":"EdDSA","typ":"JWT","kid":KID}).encode())
    payload = b64url(json.dumps({
        "aud":"securechat-bot-api",
        "iat": now, "exp": now+30,
        "jti": str(uuid.uuid4()),
        "bh":  body_hash
    }).encode())
    signing_input = f"{header}.{payload}".encode()
    sig = PRIV_KEY.sign(signing_input)
    jwt = f"{header}.{payload}.{b64url(sig)}"

    r = requests.post(
        "http://127.0.0.1:8091/v1/send",
        data=body,
        headers={
            "Authorization": f"Bearer {jwt}",
            "X-Idempotency-Key": str(uuid.uuid4()),
            "Content-Type": "application/json",
        }
    )
    print(r.status_code, r.text)

send("user:<recipient-uuid>", "Backup tamamlandi".encode())
```

## Operasyonel Komutlar

```bash
# Tum client'lari listele
bot-admin client list

# Belirli client'i revoke et (anlik etki — cache invalidate Redis pub/sub ile)
bot-admin client revoke <kid> --reason "test sonu"

# Anahtar rotate — atomik: eski kid revoke + yeni kid ayni allowList ile
bot-admin client rotate <eski-kid> --new-pubkey-file new.pub

# Emergency stop — TUM send istekleri 503 doner
bot-admin emergency-stop
bot-admin emergency-resume
bot-admin emergency-status

# Logs
docker compose logs -f bot-api

# Container restart (env degisikligi sonrasi)
docker compose restart bot-api

# Audit log query (signaling-server postgres)
docker compose exec postgres psql -U securechat -c \
  "SELECT event_type, metadata, created_at FROM audit_log \
   WHERE event_type LIKE 'BOT_API_%' ORDER BY id DESC LIMIT 20;"

# Metrics
curl http://127.0.0.1:8090/metrics | grep botapi_
```

## Endpoint Yüzeyi (Public Listener)

**Sadece** `POST /v1/send` tanımlıdır. Diğer path'ler veya HTTP method'lar 404 döner — route ağacı fiziksel olarak başka endpoint içermez VE PathWhitelistInterceptor ekstra savunma katmanı sağlar.

Response codes:
| Code | Anlam |
|---|---|
| 202 | Kabul edildi, kuyruğa girdi |
| 400 | Body parse / eksik alan |
| 401 | JWT verify reddedildi (replay, expired, wrong alg, kid bilinmiyor) |
| 403 | Recipient allow-list'te yok |
| 409 | Aynı `X-Idempotency-Key` ile başka istek halen işleniyor |
| 429 | Rate limit (Retry-After header) |
| 502 | Delivery hatası (encrypt/WS) |
| 503 | Emergency stop aktif |

## Riskler ve Hatırlatmalar

1. **Plaintext logging kesin yasak** — `SendPipeline` plaintext'i RAM'de tutar; logger'lara plaintext referansı **YOK**. Kod review'da kontrol et.
2. **PreKey bundle staleness**: bot her yeni session establishment'ta fresh bundle çeker; bundle cache'lenmez.
3. **Session state büyür**: `bot_signal_session` her recipient × device. Yüksek hacimde manuel VACUUM gerekebilir.
4. **WS disconnect mid-send**: 202 verildikten sonra mesaj `OutboundQueue`'ya (Redis list) yazılır, reconnect'te drain edilir.
5. **Crash mid-send**: `IdempotencyStore` PENDING 24h sürer; script aynı key ile retry yapabilir.
6. **FCM senderId = bot UUID**: recipient'lar bot'u "yeni kontak" olarak görür (Plan Karar #2 v1: yok say; v2'de publish-as-contact eklenecek).
7. **`BOT_MASTER_KEY` kaybı = catastrophic** (yukarıda escrow uyarısı).
8. **JWT_SECRET paylaşımı**: signaling-server ve bot-api ortak (v1 Karar #1A). v2'de internal HMAC endpoint'e geçilir — blast radius azalır.
9. **Group fan-out cost**: 50 üyeli grup = 50 prekey fetch + 50 encrypt + 50 WS send. **Rate limit'te 1 group = 1 unit**.

## Test

```bash
# Unit testler
./gradlew :bot-api:test

# Manuel end-to-end:
docker compose up -d
# 1. Client ekle (yukarida)
# 2. Python script ile bir test mesaji yolla
# 3. Recipient cihazinda mesajin geldigini gor
# 4. Audit log'da BOT_API_SEND_ACCEPTED gor
# 5. Aynı jti ile 2. istek → 401 REPLAYED_JTI
# 6. bot-admin client revoke → sonraki istek 401 UNKNOWN_OR_REVOKED_CLIENT
# 7. bot-admin emergency-stop → tum send 503
```

## V1 Bilinen Sınırlar (sonraki version'larda)

- **Unix domain socket**: şu an TCP localhost; sonraki iterasyonda Netty `EpollServerDomainSocketChannel`'a geçilecek (`BOT_PUBLIC_SOCKET` env zaten config'de hazır).
- **JWT_SECRET paylaşımı**: v2'de signaling-server internal HMAC endpoint.
- **Publish-as-contact** akışı: v2'de recipient'lar bot'u "Admin-Bot" olarak görsün.
- **Anomaly detection**: 3-sigma alert + ilk kullanım manuel onay (v2).
