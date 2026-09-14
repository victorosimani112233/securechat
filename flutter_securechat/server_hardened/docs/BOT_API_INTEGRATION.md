# Bot-API Entegrasyon Rehberi — Dışarıdan Mesaj Gönderme

Bu belge, kendi uygulamandan/scriptinden SecureChat kullanıcılarına **program
aracılığıyla mesaj göndermek** için `bot-api` modülünün nasıl kullanılacağını
adım adım anlatır.

---

## 1. Ne yapar, ne yapmaz

**Yapar:**
- Kayıtlı bir SecureChat kullanıcısına ya da gruba **mesaj gönderir**.
- Mesajı uçtan uca şifreler (bot kendi Signal identity'sine sahip ayrı bir
  "linked device" gibi davranır). Sinyal sunucusu içeriği göremez.

**Yapmaz (bilinçli, saldırı yüzeyini minimize eder):**
- Mesaj **okumaz / almaz** (gelen mesaj, geçmiş, okundu bilgisi yok).
- Profil / grup yönetimi yapmaz.
- 3rd-party developer akışı (OAuth, portal) yok.

Bu **send-only linked-device** modelidir: tek gerçek risk, imza anahtarı
çalınırsa senin adına spam — ve o da allow-list + rate limit ile sınırlı.
Geçmiş/gelen mesaj sızıntısı **imkansız**, çünkü bot decrypt yapmaz.

---

## 2. Mimari: iki yüz, ikisi de Unix domain socket

Bot-api container'ı **ağ portu açmaz**. İki dış yüzü Unix domain socket'tir:

| Yüz | Socket (varsayılan) | İzin | Ne için |
|---|---|---|---|
| **Public** | `/run/bot/bot-public.sock` | 0600 | `POST /v1/send` — tek endpoint |
| **Admin** | `/run/bot/bot-admin.sock` | 0600 | client oluştur/döndür/iptal, acil durdurma |

İç sağlık listener'ı yalnız `127.0.0.1:<healthPort>` (konteyner içi).

"Dışarıdan" demek = **aynı makinedeki** bir process socket'e yazar. İnternete
açmak istersen önüne kendi reverse-proxy / SSH tünel / mTLS gateway'ini
koyarsın (varsayılan değil, bilinçli karar — bkz. §8).

`curl` ile socket'e istek:
```bash
curl --unix-socket /run/bot/bot-public.sock http://localhost/v1/send ...
```

---

## 3. Kimlik doğrulama: Ed25519 imzalı kısa ömürlü JWT

Her `/v1/send` isteği, senin ürettiğin bir Ed25519 (EdDSA) JWT ile
imzalanır. Simetrik sır **yok** — sen private key'i tutarsın, sunucu yalnız
public key'ini bilir.

**JWT header:**
```json
{ "alg": "EdDSA", "typ": "JWT", "kid": "<sana admin'in verdiği kid>" }
```

**JWT claims:**
```json
{
  "aud": "securechat-bot-api",
  "iat": <unix saniye>,
  "exp": <unix saniye, en fazla iat + 60>,
  "jti": "<her istekte benzersiz UUID>",
  "bh":  "<base64url( SHA-256( ham istek gövdesi ) ), padding yok>"
}
```

Sunucunun uyguladığı kontroller (hepsi fail-closed):
1. `alg == EdDSA` (alg:none / HS256 reddedilir)
2. `kid` bilinen, revoked/expired olmayan client
3. Ed25519 imza doğru (JDK native)
4. `aud == securechat-bot-api`
5. `iat` penceresi: en fazla 60sn geçmiş, +5sn ileri sapma
6. `exp <= iat + 60` (uzun ömürlü token reddedilir)
7. **`bh` gövde ile eşleşmeli** — nonce'tan ÖNCE (yanlış gövde meşru nonce'u yakamaz)
8. `jti` ilk kez kullanılıyor (replay reddi, 120sn nonce penceresi)

> Not: `bh` claim'i gövdenin **birebir gönderdiğin baytları** üzerinden
> hesaplanır. Gövdeyi ürettikten sonra hash'le, sonra JWT'yi imzala, sonra
> aynı baytları gönder (yeniden serialize etme).

---

## 4. Önce: admin ile bir API client oluştur

`kid` + kabul edilen allow-list'i admin socket'ten alırsın. Admin token
(`BOT_ADMIN_TOKEN`) `X-Admin-Token` header'ında zorunlu.

Önce **kendi Ed25519 keypair'ini** üret (private'ı SEN tutarsın):
```bash
# private (PKCS#8) + raw public (32 byte) üret
openssl genpkey -algorithm ed25519 -out bot_client.pem
# raw 32-byte public key -> base64 (sunucuya bunu verirsin)
openssl pkey -in bot_client.pem -pubout -outform DER | tail -c 32 | base64
```

Client oluştur:
```bash
curl --unix-socket /run/bot/bot-admin.sock \
  -X POST http://localhost/admin/clients \
  -H "X-Admin-Token: $BOT_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "AC1:my-app",
    "publicKey": "<yukarıdaki base64 raw public key>",
    "allowList": ["user:11111111-1111-1111-8111-111111111111"],
    "ratePerHour": 100,
    "perRecipientPerDay": 500,
    "expiresInDays": 90
  }'
# -> 201 {"kid":"k_...","name":"AC1:my-app"}
```

**Alan sınırları (fail-closed):** `name` 1–128 char; `allowList` 1–256 girdi,
her biri `user:<uuid>` veya `group:<token>`, tekrarsız, boş liste = "hiçbir
şeye izinli değil" (her şeye değil); `ratePerHour` 1–10000; `perRecipientPerDay`
1–10000; `expiresInDays` 1–365.

Diğer admin komutları:
```bash
# listele (private materyal DÖNMEZ)
curl --unix-socket /run/bot/bot-admin.sock http://localhost/admin/clients -H "X-Admin-Token: $T"
# iptal
curl --unix-socket /run/bot/bot-admin.sock -X DELETE "http://localhost/admin/clients/<kid>" -H "X-Admin-Token: $T"
# anahtar döndür (önce yeni oluşturur, sonra eskiyi iptal eder — client credential'sız kalmaz)
curl --unix-socket /run/bot/bot-admin.sock -X POST "http://localhost/admin/clients/<kid>/rotate" \
  -H "X-Admin-Token: $T" -H "Content-Type: application/json" -d '{"newPublicKey":"<base64>"}'
# acil durdurma (tüm /v1/send'ler 503)
curl --unix-socket /run/bot/bot-admin.sock -X POST http://localhost/admin/emergency/stop -H "X-Admin-Token: $T"
curl --unix-socket /run/bot/bot-admin.sock -X POST http://localhost/admin/emergency/resume -H "X-Admin-Token: $T"
```

---

## 5. Mesaj gönder: `POST /v1/send`

**Zorunlu header'lar:**
- `Authorization: Bearer <az önce anlatılan JWT>`
- `X-Idempotency-Key: <benzersiz string, <=128 char>` (aynı anahtarla retry → tek gönderim)
- `Content-Type: application/json`

**Gövde:**
```json
{
  "recipientRef": "user:<uuid>",
  "plaintextBase64": "<base64( göndermek istediğin ham metin baytları )>",
  "messageType": "text"
}
```

- `recipientRef`:
  - Bire bir: `user:<uuid>` (geçerli UUID).
  - Grup: `group:<43-karakter opak routing token>` **ve** `recipientUserIds`
    alanı grubun üye UUID'leriyle dolu (≤256, tekrarsız, hepsi geçerli UUID,
    hepsi allow-list'te). Grup token'ı tek başına yetki değildir.
- `plaintextBase64`: bot bunu alır ve alıcıya Signal ile **şifreler**. Yani
  bot process'i düz metni görür (linked-device güven modeli); ağ ve sinyal
  sunucusu göremez.
- `messageType`: opsiyonel, varsayılan `"text"` (`"image"` vb.).

**Örnek:**
```bash
BODY='{"recipientRef":"user:1111...","plaintextBase64":"'"$(printf 'merhaba' | base64)"'","messageType":"text"}'
BH=$(printf '%s' "$BODY" | openssl dgst -sha256 -binary | basenc --base64url | tr -d '=')
# JWT'yi $BH ile üret (bkz. §6 kod örneği), sonra:
curl --unix-socket /run/bot/bot-public.sock -X POST http://localhost/v1/send \
  -H "Authorization: Bearer $JWT" \
  -H "X-Idempotency-Key: $(uuidgen)" \
  -H "Content-Type: application/json" \
  --data-binary "$BODY"
```

**Yanıtlar:**

| Kod | Anlam |
|---|---|
| `202 {"messageId","status":"queued"}` | Kabul edildi, teslim kuyruğa alındı |
| `200 <önceki cevap>` | Idempotency: aynı key daha önce tamamlanmış, aynı cevap |
| `409 idempotency_pending` | Aynı key hâlâ işleniyor |
| `401 auth_failed` (+`reason`) | JWT geçersiz (imza/exp/replay/body-hash…) |
| `403 recipient_not_allowed` | Alıcı allow-list dışında |
| `429 rate_limit` (+`layer`,`Retry-After`) | Rate limit (client/recipient/global) |
| `400 invalid_private_routing` | Geçersiz recipientRef / grup paketi |
| `400 json_parse_failed` / `X-Idempotency-Key header zorunlu` | Girdi hatası |
| `503 emergency_stop` | Acil durdurma aktif |
| `413 body_too_large` | Gövde 256KB üstü |

---

## 6. Uçtan uca istemci örneği (Python)

```python
import base64, hashlib, json, time, uuid, requests_unixsocket
from cryptography.hazmat.primitives.serialization import load_pem_private_key
# pip install pyjwt[crypto] requests-unixsocket cryptography

import jwt  # PyJWT

KID = "k_...."                       # admin'in verdiği kid
PRIV = load_pem_private_key(open("bot_client.pem","rb").read(), password=None)
SOCK = "http+unix://%2Frun%2Fbot%2Fbot-public.sock"  # /run/bot/bot-public.sock url-encoded

def b64url_nopad(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def send(recipient_uuid: str, text: str):
    body = json.dumps({
        "recipientRef": f"user:{recipient_uuid}",
        "plaintextBase64": base64.b64encode(text.encode()).decode(),
        "messageType": "text",
    }, separators=(",", ":")).encode()          # baytları SABİTLE
    bh = b64url_nopad(hashlib.sha256(body).digest())
    now = int(time.time())
    token = jwt.encode(
        {"aud": "securechat-bot-api", "iat": now, "exp": now + 55,
         "jti": str(uuid.uuid4()), "bh": bh},
        PRIV, algorithm="EdDSA", headers={"kid": KID, "typ": "JWT"},
    )
    s = requests_unixsocket.Session()
    r = s.post(f"{SOCK}/v1/send",
               data=body,                        # AYNI baytlar
               headers={"Authorization": f"Bearer {token}",
                        "X-Idempotency-Key": str(uuid.uuid4()),
                        "Content-Type": "application/json"})
    r.raise_for_status()
    return r.json()

print(send("11111111-1111-1111-8111-111111111111", "merhaba"))
```

Kritik nokta: `bh` için hash'lenen baytlar ile POST edilen baytlar **birebir
aynı** olmalı (yeniden serialize etme → hash uyuşmaz → 401 body_hash_mismatch).

---

## 7. Rate limit ve idempotency davranışı

- **3 katman** (aşıldığında 429 + `Retry-After`):
  1. client başına saat: `ratePerHour`
  2. alıcı başına gün: `perRecipientPerDay`
  3. global: 1000/dakika (acil fren)
- Grup fanout'unda her alıcı **1 birim** tüketir (tek istekle limit
  amplifikasyonu yapılamaz).
- **Idempotency:** aynı `X-Idempotency-Key` ile retry aynı sonucu döner,
  mesaj iki kez gitmez. Kısmi grup fanout'unda ilerleme takip edilir; retry
  yalnız eksik kalan alıcılara gider.

---

## 8. Netleşmesi gereken ürün kararları (senin onayın)

Kod hazır ve sertleştirilmiş; şu operasyonel kararlar senin:

1. **Ağa açma modeli.** Varsayılan: Unix socket (yalnız aynı host) + istenirse
   SSH tünel. İnternete açık mTLS **yalnız gerçekten gerekiyorsa**. — Senin
   kullanımın: uygulaman aynı makinede mi (socket yeter) yoksa uzaktan mı
   (tünel/mTLS gerekir)?
2. **Bot host'u.** Ayrı VM (önerim, izolasyon) vs mevcut sinyal sunucusuyla
   aynı host. — Onayın?
3. **İlk caller use-case.** Kritik değil (allow-list zaten per-client), ama
   ilk client'ın hangi kişilere/gruplara yazacağını netleştir → allow-list.

Bu üçü netleşince: sistemd hardening + tünel/mTLS konfigini ve senin
uygulamana özel istemci kütüphanesini (Dart/Python/…) çıkarabilirim.

---

## 9. Kill switch (birden fazla)

- `systemctl stop bot-api` (process)
- admin `POST /admin/emergency/stop` (tüm /v1/send → 503)
- `DELETE /admin/clients/<kid>` (tek client iptal)
- linked device'ı SecureChat istemcisinden sil (bot identity'yi düşür)

---

İlgili kaynak: `bot-api/src/main/kotlin/com/securechat/botapi/` — auth
(`EdDsaJwtVerifier`), send (`SendPipeline`), admin (`ClientCrudRoutes`),
transport (`listener/UnixSocketBridge`). Test kapsamı: `EdDsaJwtVerifierTest`,
`SendEndpointTest`, `AdminApiTest`, `BotRateLimitAndIdempotencyTest`.
