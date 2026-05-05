# SecureChat Backend Production-Ready Migration

> **Kullanım:** Bu doküman Claude Code'a verilecek master prompt'tur. Her FAZ ayrı bir agent invocation olarak çalıştırılabilir veya tek seferde sırayla yürütülebilir. Her faz tamamlandığında acceptance criteria'lar manuel veya otomatik doğrulanmalı, geçilmeden bir sonraki faza geçilmemelidir.

---

## 0. GENEL BAĞLAM (TÜM AGENT'LAR İÇİN OKUNACAK)

### Proje
**SecureChat** — Signal Protocol (libsignal-android) tabanlı uçtan uca şifreli mesajlaşma uygulaması. Mevcut backend Ktor (Kotlin) üzerinde çalışıyor, WebSocket signaling + REST API hibrit mimari kullanıyor. Frontend Android (Kotlin/Compose). WebRTC ile sesli/görüntülü arama, FCM ile push bildirim destekli.

### Mevcut Sunucu
- **Donanım:** 40GB SSD, 8GB RAM, 4 CPU core (single VM)
- **OS:** Linux (Ubuntu/RHEL muhtemel)
- **Network:** Tek IP, public erişim, TURN sunucusu aynı makinede

### Hedef
- **10.000 kayıtlı kullanıcı, 5.000 eşzamanlı bağlantı** taşıyacak production-ready backend
- **Veri kalıcılığı garantisi** (sunucu restart = sıfır veri kaybı)
- **Güvenlik sertleştirmesi** (rate limiting, dinamik TURN credential, brute-force koruması)
- **Zero-downtime migration** (mevcut kullanıcıları kaybetmeden geçiş)
- **Backwards compatible** (Android client'larında protokol değişikliği YAPMA — sadece transport ve persistence katmanını değiştir)

### Kritik Kurallar (DEĞİŞTİRME)
1. **Signal Protocol implementasyonuna DOKUNMA.** libsignal-android, Double Ratchet, X3DH, PreKey bundle yönetimi ne olursa olsun mevcut hâlinde kalacak.
2. **WebSocket signaling mesaj formatları aynı kalacak.** Sadece sunucu içi storage/routing değişiyor.
3. **API endpoint contract'ları (request/response JSON şemaları) aynı kalacak.** Yeni endpoint eklenebilir, mevcutlar değiştirilemez.
4. **E2E şifreleme garantileri korunacak.** Sunucu hiçbir zaman plaintext mesaj görmeyecek; offline queue'da sadece şifreli payload tutulacak.

### Teknoloji Seçimleri (KESİNLEŞMİŞ)
- **Veritabanı:** PostgreSQL 16 (TimescaleDB değil — bu klasik relational workload)
- **Cache/Queue:** Redis 7
- **Migration tool:** Flyway
- **Connection pool:** HikariCP
- **Observability:** Prometheus + Grafana (Loki opsiyonel)
- **Reverse proxy:** Nginx (TLS termination + rate limiting layer 1)
- **Container:** Docker + Docker Compose
- **SFU (Faz 6):** Janus Gateway (mediasoup ve Pion alternatif olarak değerlendirildi, Janus seçildi — daha olgun WebRTC desteği)

### Çalışma Düzeni
- Repository root'tan başla. Önce `tree -L 3 -I 'node_modules|build|.gradle'` ile mevcut yapıyı çıkar.
- Her dosya değişikliğinden önce mevcut dosyayı oku ve mevcut convention'lara uy.
- Her faz kendi git branch'inde geliştirilecek: `migration/phase-1-infra`, `migration/phase-2-persistence`, vb.
- Her faz sonunda `CHANGELOG.md` güncellenecek ve PR açılacak şekilde commit edilecek.

---

## FAZ 1 — INFRASTRUCTURE AGENT

**Branch:** `migration/phase-1-infra`
**Süre tahmini:** 0.5-1 gün
**Bağımlılık:** Yok (ilk faz)

### Görev
Production-grade altyapı bileşenlerini Docker Compose ile orkestre et. PostgreSQL, Redis, Nginx, Prometheus, Grafana çalışır halde olsun. Hiçbir veri migration'ı YAPMA — sadece altyapı.

### Yapılacaklar

1. **`infra/docker-compose.yml` oluştur:**
   - `postgres:16-alpine` — port 5432 (sadece internal network'e expose, host'a değil)
     - Volume: `postgres_data:/var/lib/postgresql/data`
     - Healthcheck: `pg_isready -U securechat`
     - `shared_buffers=2GB`, `max_connections=200`, `effective_cache_size=4GB` (8GB RAM için)
   - `redis:7-alpine` — port 6379 (internal only)
     - Volume: `redis_data:/data`
     - `--appendonly yes --appendfsync everysec --maxmemory 1gb --maxmemory-policy allkeys-lru`
     - Healthcheck: `redis-cli ping`
   - `nginx:alpine` — port 443 (host'a expose), 80 (redirect to 443)
     - TLS sertifikaları için volume mount: `./nginx/certs:/etc/nginx/certs:ro`
     - WebSocket proxy konfigürasyonu (Upgrade/Connection header'ları)
     - Layer-1 rate limiting (`limit_req_zone` ile IP bazlı, 100 req/min)
   - `prometheus:latest` — port 9090 (internal)
     - Scrape: backend (port 8080/metrics), postgres-exporter, redis-exporter, node-exporter
   - `grafana:latest` — port 3000 (internal, Nginx üzerinden /grafana ile expose)
   - `postgres-exporter`, `redis-exporter`, `node-exporter` (metrics collector'lar)

2. **`infra/postgres/init.sql` — initial DB ve user yarat:**
   ```sql
   CREATE DATABASE securechat;
   CREATE USER securechat WITH ENCRYPTED PASSWORD 'CHANGE_ME_IN_ENV';
   GRANT ALL PRIVILEGES ON DATABASE securechat TO securechat;
   ```
   Şifre `.env` dosyasından okunacak, `init.sql` template kullan.

3. **`infra/nginx/securechat.conf` oluştur:**
   - HTTP→HTTPS redirect
   - HTTPS server block: TLS 1.2/1.3, modern cipher suite
   - `/api/` → backend:8080
   - `/ws` → backend:8080 (WebSocket upgrade)
   - `/grafana/` → grafana:3000 (basic auth)
   - Rate limit zones: `api_zone` (100r/m), `auth_zone` (10r/m for `/api/v1/users/check`)
   - Connection limits: `limit_conn_zone $binary_remote_addr zone=conn_limit:10m`, max 50 conn/IP

4. **`.env.example` oluştur:**
   ```
   POSTGRES_PASSWORD=
   REDIS_PASSWORD=
   GRAFANA_ADMIN_PASSWORD=
   TURN_SECRET=
   JWT_SECRET=
   ENV=production
   ```

5. **`infra/prometheus/prometheus.yml` — scrape config'leri**

6. **`infra/grafana/provisioning/` — dashboard JSON'ları:**
   - PostgreSQL dashboard (connection pool, query latency, locks)
   - Redis dashboard (memory, ops/sec, evictions)
   - Backend app dashboard (HTTP latency, WebSocket connection count, error rate)
   - Node-level dashboard (CPU, RAM, disk, network)

7. **`infra/Makefile` veya `infra/scripts/`:**
   - `make up` / `make down` / `make logs` / `make backup-db` / `make restore-db`
   - `backup-db`: `pg_dump` ile sıkıştırılmış yedek, tarih damgalı, `./backups/` dizinine
   - **CRON tabanlı günlük yedek için sistemd timer veya cron örneği dokümante et** (host üzerinde çalışacak)

8. **`infra/README.md`:**
   - Kurulum adımları
   - `.env` doldurma talimatları
   - TLS sertifika nasıl koyulur (Let's Encrypt veya self-signed)
   - Backup/restore prosedürü
   - Monitoring erişim URL'leri

### Acceptance Criteria
- [ ] `docker compose up -d` ile tüm servisler healthy state'e geçiyor (`docker compose ps` ile doğrulanabiliyor)
- [ ] PostgreSQL'e `psql -h localhost -U securechat -d securechat` ile bağlanılabiliyor (parola env'den)
- [ ] Redis'e `redis-cli -a $REDIS_PASSWORD ping` PONG dönüyor
- [ ] Nginx üzerinden `https://localhost/health` 200 dönüyor (basit bir static health endpoint)
- [ ] Grafana `https://localhost/grafana/` ile erişilebilir, dashboard'lar görünüyor
- [ ] `make backup-db` ile `./backups/securechat-YYYYMMDD-HHMMSS.sql.gz` dosyası oluşuyor
- [ ] `make restore-db FILE=...` ile yedek geri yükleniyor
- [ ] Prometheus targets sayfasında tüm exporter'lar UP

### Rollback Plan
- `docker compose down -v` (volume'ları sil, sıfırdan başla)
- Mevcut backend hâlâ JSON tabanlı çalışıyor olduğundan production etkilenmez

---

## FAZ 2 — PERSISTENCE AGENT

**Branch:** `migration/phase-2-persistence`
**Süre tahmini:** 2-3 gün
**Bağımlılık:** Faz 1 tamamlanmış olmalı.

### Görev
`UserRegistry`, `FcmTokenStore`, ve offline mesaj kuyruğunu kalıcı storage'a taşı. **Dual-write pattern** kullan: ilk aşamada hem JSON/RAM hem de PostgreSQL/Redis'e yaz, doğrulama sonrası JSON/RAM kaldır.

### Yapılacaklar

#### 2.1 Schema Tasarımı (`db/migrations/V1__initial_schema.sql`)

```sql
-- Users table
CREATE TABLE users (
    user_id UUID PRIMARY KEY,
    phone_number VARCHAR(32) UNIQUE NOT NULL,
    public_identity_key BYTEA NOT NULL,
    registration_id INTEGER NOT NULL,
    display_name VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ
);
CREATE INDEX idx_users_phone ON users(phone_number);
CREATE INDEX idx_users_last_seen ON users(last_seen_at) WHERE last_seen_at IS NOT NULL;

-- PreKeys (Signal Protocol)
CREATE TABLE prekeys (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    key_id INTEGER NOT NULL,
    public_key BYTEA NOT NULL,
    is_signed BOOLEAN NOT NULL DEFAULT FALSE,
    signature BYTEA,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, key_id, is_signed)
);
CREATE INDEX idx_prekeys_user_unconsumed ON prekeys(user_id) WHERE consumed_at IS NULL;

-- FCM tokens
CREATE TABLE fcm_tokens (
    user_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    device_id VARCHAR(255),
    platform VARCHAR(16) NOT NULL DEFAULT 'android',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_fcm_updated ON fcm_tokens(updated_at);

-- Groups (basic metadata, üyeler ayrı tabloda)
CREATE TABLE groups (
    group_id UUID PRIMARY KEY,
    name VARCHAR(255),
    created_by UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE group_members (
    group_id UUID NOT NULL REFERENCES groups(group_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    role VARCHAR(16) NOT NULL DEFAULT 'member',
    PRIMARY KEY (group_id, user_id)
);
CREATE INDEX idx_group_members_user ON group_members(user_id);

-- Audit log
CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID,
    event_type VARCHAR(64) NOT NULL,
    metadata JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_user_time ON audit_log(user_id, created_at DESC);
CREATE INDEX idx_audit_event_time ON audit_log(event_type, created_at DESC);
```

#### 2.2 Backend Bağımlılık Eklemeleri (`server/build.gradle.kts`)
- `org.postgresql:postgresql:42.7.x`
- `com.zaxxer:HikariCP:5.x`
- `org.flywaydb:flyway-core:10.x`, `flyway-database-postgresql`
- `org.jetbrains.exposed:exposed-core:0.50.x` (veya tercih ettiğin ORM — JOOQ tercih ediliyorsa onu kullan, mevcut kod stiline uygun olanı seç)
- `redis.clients:jedis:5.x` veya `io.lettuce:lettuce-core:6.x`

#### 2.3 Connection Pool Konfigürasyonu (`server/src/main/kotlin/.../db/Database.kt`)
- HikariCP: `maximumPoolSize=20`, `minimumIdle=5`, `connectionTimeout=30000`, `idleTimeout=600000`, `maxLifetime=1800000`, `leakDetectionThreshold=60000`
- Flyway migration startup'ta otomatik çalışsın
- Health check endpoint: DB ve Redis ping

#### 2.4 UserRegistry Migration
- Yeni `UserRepository.kt` arabirimi:
  - `findByPhoneNumber(phone: String): User?`
  - `findById(userId: UUID): User?`
  - `save(user: User): User`
  - `updateLastSeen(userId: UUID, ts: Instant)`
- Eski `UserRegistry.kt` `UserRepository`'yi delegate edecek **dual-write modunda**:
  - Önce DB'ye yaz, sonra JSON dosyasına yaz (best-effort, hata olsa da DB persist)
  - Read'ler önce DB'den, fallback JSON
- **Migration script: `scripts/migrate_user_registry.kts`**
  - `user_registry.json`'ı oku → tüm kullanıcıları DB'ye `INSERT ... ON CONFLICT DO NOTHING` ile aktar
  - PreKey verisi de varsa `prekeys` tablosuna geçir
  - Sonunda count doğrulaması: JSON kayıt sayısı == DB kayıt sayısı
- Doğrulama sonrası **2.7 adımında** JSON yazma kaldırılacak

#### 2.5 FcmTokenStore Migration
- Yeni `FcmTokenRepository.kt`:
  - `upsert(userId: UUID, token: String, deviceId: String?)`
  - `getByUserId(userId: UUID): String?`
  - `deleteByUserId(userId: UUID)`
  - `deleteStale(olderThan: Duration)` — 60+ gündür güncellenmemişler
- Eski `FcmTokenStore.kt` aynı şekilde dual-write
- In-memory map'i tamamen kaldır (Faz 2 sonunda)

#### 2.6 Offline Message Queue → Redis
- Redis veri modeli:
  - **Sorted set** kullan: `offline_queue:{userId}` — score = timestamp_ms
  - Her entry JSON encoded: `{"id": "msg-uuid", "payload": "<base64-encrypted>", "from": "sender-uuid", "ts": 1234567890, "type": "DM|GROUP"}`
  - **Server hiçbir zaman plaintext görmüyor — sadece şifreli payload relay**
  - TTL: kullanıcı başına queue 14 gün (`EXPIRE offline_queue:{userId} 1209600`)
  - Max queue size: 1000 entry/user → push sırasında `ZREMRANGEBYRANK 0 -1001` ile en eskiyi at
- Yeni `OfflineQueueRepository.kt`:
  - `enqueue(userId: UUID, message: EncryptedMessage)`
  - `dequeueAll(userId: UUID): List<EncryptedMessage>` (kullanıcı bağlandığında çağrılacak)
  - `peek(userId: UUID, limit: Int): List<EncryptedMessage>`
  - `size(userId: UUID): Long`
- ConnectionManager'da in-memory `ConcurrentHashMap` kuyruğu kaldırılacak — direkt Redis'e yazılacak

#### 2.7 Cleanup (Dual-Write'ı Kapat)
- `user_registry.json` artık sadece okunabilir backup olarak duracak — yazma KAPATILDI
- `git mv user_registry.json user_registry.json.legacy.backup` ile arşivle
- In-memory map'ler tamamen kaldırıldı
- `UserRegistry.kt` artık sadece `UserRepository`'ye thin wrapper

#### 2.8 Test
- Unit test: `UserRepositoryTest` — H2 veya Testcontainers PostgreSQL ile
- Integration test: full registration flow + WebSocket bağlantı + offline message + reconnect
- Migration test: synthetic 10K kullanıcılı `user_registry.json` üretip migration script'i çalıştır, count + sample data doğrula

### Acceptance Criteria
- [ ] Flyway migration'ları temiz DB üzerinde başarıyla uygulanıyor (`./gradlew flywayMigrate`)
- [ ] Mevcut JSON `user_registry.json` migration script'i ile DB'ye eksiksiz aktarılıyor (count match)
- [ ] Sunucu restart sonrası tüm kullanıcılar, FCM token'lar ve offline kuyrukta bekleyen mesajlar korunuyor
- [ ] 1000 kullanıcılı load test'te (locust/k6) DB connection pool exhaustion yok, p99 latency < 200ms
- [ ] Offline kullanıcıya mesaj gönderildiğinde Redis sorted set'inde görünüyor; kullanıcı bağlandığında alıyor
- [ ] Redis memory kullanımı 1GB altında (10K kullanıcı senaryosunda)
- [ ] `user_registry.json` artık güncellenmiyor (timestamp değişmiyor)

### Rollback Plan
- Feature flag: `USE_DB_PERSISTENCE=false` ile eski JSON path'ine geri dön (Faz 2 boyunca dual-write açık tutulur, son adıma kadar geri dönülebilir)
- DB rollback için Flyway `flywayUndo` veya snapshot restore

---

## FAZ 3 — SECURITY AGENT

**Branch:** `migration/phase-3-security`
**Süre tahmini:** 1-2 gün
**Bağımlılık:** Faz 1 (Redis gerekli rate limit için)

### Görev
TURN credential'ları dinamik HMAC tabanlı yap, rate limiting katmanını uygula, brute-force koruması ekle, audit log'u devreye al.

### Yapılacaklar

#### 3.1 Dinamik TURN Credential (RFC 8489 — Long-Term Credential)
- TURN sunucu config'inde shared secret kullan (coturn ise `use-auth-secret` + `static-auth-secret`)
- Backend'de yeni endpoint: `GET /api/v1/ice/config` (auth gerekli)
- Algoritma:
  ```
  expiry = unix_now + 24*3600
  username = "{expiry}:{userId}"
  password = base64(hmac_sha1(TURN_SECRET, username))
  ```
- Response:
  ```json
  {
    "iceServers": [
      {"urls": "stun:185.48.182.124:3478"},
      {
        "urls": "turn:185.48.182.124:3478",
        "username": "1735689600:user-uuid",
        "credential": "base64hash"
      }
    ],
    "ttl": 86400
  }
  ```
- Android client'ta `PeerConnectionManager` her arama başlangıcında bu endpoint'ten taze credential çekecek (24 saatlik cache local'de)
- Hardcoded credential'ları **client kod tabanından TAMAMEN KALDIR** — release APK'da grep ile `securechat123` aranıp 0 sonuç çıkmalı

#### 3.2 Redis-Backed Rate Limiter
- `RateLimiter.kt` — token bucket veya sliding window:
  - Key formatı: `ratelimit:{endpoint}:{identifier}` (identifier = userId varsa, yoksa IP)
  - Limit'ler:
    - `/api/v1/users/check` → **10 req/dakika per IP, 100 req/saat per IP**
    - `/api/v1/auth/register` → **5 req/saat per IP**
    - `/api/v1/auth/verify` → **10 req/saat per IP** (SMS verify code)
    - WebSocket message rate → **100 msg/saniye per userId**, aşılırsa connection drop + audit log
    - `/api/v1/ice/config` → **30 req/saat per userId**
- 429 response'unda `Retry-After` header'ı dön
- Nginx layer-1 rate limit zaten var (Faz 1) — bu uygulama katmanı, daha granüler

#### 3.3 Phone Number Enumeration Koruması
- `/api/v1/users/check` — mevcut tasarımı incele:
  - Eğer numara varlık bilgisi düz dönüyorsa: **constant-time response + dummy hash hesapla**
  - Daha iyisi: **PSI (Private Set Intersection)** veya **bloom filter** ile "muhtemel hit" dön
  - Pragmatik orta yol: rate limit + monitoring (anormal pattern'de IP block)
- Audit log'a tüm `users/check` çağrıları kaydedilsin (IP, sorgulanan numara hash'i, timestamp)

#### 3.4 Brute-Force Koruması
- SMS verify code endpoint:
  - Aynı telefon numarasına 5 yanlış denemede 1 saatlik kilit
  - Redis key: `verify_attempts:{phone}` — counter, TTL 3600
- Kilit aşılırsa Slack/email alarm (opsiyonel webhook)

#### 3.5 Input Validation Sertleştirmesi
- Tüm REST endpoint'lerde request body schema validation (kotlinx.serialization strict mode)
- Phone number: E.164 format regex
- UUID parse: invalid input 400 dön
- WebSocket mesaj boyutu max 64KB (binary), 16KB (text)

#### 3.6 Audit Log Aktivasyonu
- Şu eventler log'lansın:
  - `USER_REGISTERED`, `USER_LOGIN`, `LOGIN_FAILED`
  - `RATE_LIMIT_HIT` (endpoint + identifier)
  - `WS_CONNECTION_ESTABLISHED`, `WS_CONNECTION_DROPPED` (sebebi ile)
  - `TURN_CREDENTIAL_ISSUED`
  - `OFFLINE_QUEUE_OVERFLOW` (kullanıcının kuyruğu max'a ulaştı)
- IP, userId, metadata JSONB olarak `audit_log` tablosuna

#### 3.7 Secrets Management
- Tüm secret'lar `.env` üzerinden — code'da kesinlikle hardcoded olmayacak
- `.env.example` güncel kalacak ama gerçek `.env` `.gitignore`'da
- README'de "production'da Vault/AWS SSM kullanılması önerilir" notu

### Acceptance Criteria
- [ ] APK decompile sonrası grep `securechat123` 0 sonuç dönüyor
- [ ] `/api/v1/ice/config` çağrısı geçerli geçici credential dönüyor, 24 saat sonra eski credential reject ediliyor
- [ ] `/api/v1/users/check` endpoint'ine 11 ardışık istek atıldığında 429 dönüyor
- [ ] WebSocket'te saniyede 200 mesaj gönderen client connection drop oluyor, audit log'a yazılıyor
- [ ] 5 yanlış SMS verify denemesi sonrası kilit aktif, doğru kod bile reject ediliyor (1 saat boyunca)
- [ ] Audit log tablosunda son 24 saatin event'leri SELECT edilebiliyor
- [ ] OWASP ZAP veya benzeri tool ile temel scan'da kritik bulgu yok

### Rollback Plan
- Rate limiter feature flag ile kapatılabilir (`RATE_LIMIT_ENABLED=false`)
- TURN credential dinamik endpoint çalışmazsa client fallback static credential kullanmaz — bağlantı başarısız olur, ama bu **doğru davranış** (eski credential'ı kullanmaya geri dönülmeyecek)

---

## FAZ 4 — MESSAGING AGENT

**Branch:** `migration/phase-4-messaging`
**Süre tahmini:** 2-3 gün
**Bağımlılık:** Faz 2 (Redis offline queue gerekli)

### Görev
Grup mesaj relay sunucu tarafına alınsın, signal buffer büyütülsün, typing indicator broadcast'ten target'e çevrilsin, WebSocket lifecycle iyileştirmesi yapılsın.

### Yapılacaklar

#### 4.1 Server-Side Group Message Relay
- Yeni signaling mesaj tipi: `GROUP_MESSAGE_FANOUT` (mevcut `GROUP_MESSAGE` ile geriye uyumlu kalsın)
- Akış:
  1. Sender, sunucuya tek bir `GROUP_MESSAGE_FANOUT` mesajı gönderir: `{groupId, ciphertextPerRecipient: {userId1: blob1, userId2: blob2, ...}}` — Sender Keys yapısında her recipient için ayrı şifreli payload
  2. Sunucu `group_members` tablosundan üyeleri çeker (cache: Redis `group_members:{groupId}` TTL 5 dk)
  3. Online üyelere WebSocket üzerinden push eder
  4. Offline üyelere Redis offline_queue'ya yazar
- **Sunucu hiçbir zaman plaintext görmüyor** — sadece "kim hangi şifreli blob'u alacak" routing'i yapıyor
- Sender artık offline olsa da grup mesajı kayıp olmuyor (sunucu fanout'u yapıyor)

#### 4.2 Signal Buffer Büyütme
- `SignalingClient.kt` (server-side):
  - `extraBufferCapacity = 64` → **`512`**
  - `onBufferOverflow = DROP_OLDEST` → **`SUSPEND`** (backpressure ile)
  - Eğer SUSPEND mümkün değilse `BUFFER` ve overflow durumunda audit log

#### 4.3 Typing Indicator Targeting
- Mevcut `recipientId="broadcast"` davranışını kaldır
- DM'de: typing indicator sadece konuşulan peer'a gider (`recipientId={peerUserId}`)
- Grupta: typing indicator sadece o gruptaki online üyelere gider (`groupId={groupId}` + sunucu fanout)
- Client tarafında: ekran/sohbet odasından çıkan kullanıcı tarafından typing alınmıyor (server bunu enforce eder)

#### 4.4 WebSocket Lifecycle
- **Idle timeout:** 5 dakika ping/pong yoksa connection drop. Client her 30 sn ping atacak.
- **Heartbeat:** Server her 60 sn ping atar, 90 sn'de pong gelmezse drop
- **Graceful shutdown:** SIGTERM aldığında:
  1. Yeni bağlantı kabul etmeyi bırak
  2. Tüm aktif client'lara `SERVER_SHUTDOWN` mesajı gönder (client reconnect öncesi 5 sn bekleyecek)
  3. 30 sn aktif mesaj drain'i için bekle
  4. Connection'ları kapat
  5. DB connection pool'unu kapat
  6. Process exit
- **Connection limit:** sunucu başına max 6000 eşzamanlı WebSocket (8GB RAM güvenli aralık), aşılırsa 503 dön

#### 4.5 Presence Optimization
- Mevcut: presence update tüm online kullanıcılara broadcast (raporda "5K user × typing = 5K frame/sn" sorunu)
- Yeni: presence sadece **kullanıcının kontak listesindeki user'lara** push edilir
- `user_contacts` tablosu yoksa eklenmeli (kullanıcı başına kontaklar — şifrelenmiş olabilir, ama userId mapping sunucuda olmalı)
- Client kontak listesini ilk kayıtta sunucuya iletir (sadece userId'ler, isim/telefon değil)

#### 4.6 Test
- Load test (k6): 5000 eşzamanlı WebSocket, dakikada 100 mesaj/user, 30 dakika sürdür
- 100 üyeli grup mesaj testi: tek `GROUP_MESSAGE_FANOUT` → 100 üyeye fanout latency p99 < 500ms
- Graceful shutdown testi: load test sırasında SIGTERM → mesaj kaybı 0

### Acceptance Criteria
- [ ] 100 kişilik grupta sender'ın offline olduğu durumda mesaj tüm üyelere ulaşıyor (sender geri online olduğunda gönderim onay alıyor)
- [ ] Signal buffer overflow audit log'da görünmüyor (normal trafikte)
- [ ] Typing indicator sadece ilgili peer/grup üyelerine gidiyor (Wireshark/log ile doğrulanabilir)
- [ ] 6000 eşzamanlı bağlantıda RAM kullanımı 6GB altında
- [ ] Graceful shutdown sırasında 0 mesaj kaybı (k6 test sonucu ile)
- [ ] Idle 6 dakika sonra connection otomatik düşüyor

### Rollback Plan
- `GROUP_MESSAGE_FANOUT` feature flag ile devre dışı bırakılabilir, eski client-side fanout devreye girer

---

## FAZ 5 — CLIENT OPTIMIZATION AGENT

**Branch:** `migration/phase-5-client-opt`
**Süre tahmini:** 1-2 gün
**Bağımlılık:** Yok (server'dan bağımsız, paralel yürütülebilir)

### Görev
Android client'ta mesaj pagination, N+1 query fix, Room DB index'leri.

### Yapılacaklar

#### 5.1 Paging 3 Entegrasyonu
- `androidx.paging:paging-runtime:3.x` ekle
- `MessageDao` değişikliği:
  ```kotlin
  @Query("SELECT * FROM messages WHERE conversation_id = :convId ORDER BY timestamp DESC")
  fun getPagedMessages(convId: String): PagingSource<Int, Message>
  ```
- ViewModel: `Pager(config = PagingConfig(pageSize = 50, prefetchDistance = 10))`
- Compose UI: `LazyColumn` içinde `items(lazyPagingItems)`
- 100K mesaj limiti tamamen kaldırılsın (artık gerek yok)

#### 5.2 N+1 Query Fix (Conversation List)
- Mevcut sorun:
  ```kotlin
  conversationDao.getAllImmediate().forEach { conv ->
      contactNameResolver.resolveDisplayName(conv.peerId)
  }
  ```
- Çözüm: Tek JOIN query
  ```kotlin
  @Query("""
      SELECT c.*, ct.display_name AS resolved_name
      FROM conversations c
      LEFT JOIN contacts ct ON c.peer_id = ct.user_id
      ORDER BY c.last_message_at DESC
  """)
  fun getConversationsWithNames(): Flow<List<ConversationWithName>>
  ```

#### 5.3 Room Index'leri
- `messages` tablosu:
  - `@Index(value = ["conversation_id", "timestamp"])` — sohbet listeleme için composite
  - `@Index(value = ["sender_id"])`
  - `@Index(value = ["status"])` — undelivered mesajlar için
- `conversations` tablosu:
  - `@Index(value = ["peer_id"])` — DM lookup
  - `@Index(value = ["last_message_at"])` — sıralama için
- Migration script: `Migration_X_to_Y` ile production DB'lerinde index oluştur

#### 5.4 Memory Profiling
- Android Studio profiler ile mesaj listesi açıkken RAM kullanımı ölç
- Hedef: 100K mesajlı sohbette RAM artışı 100MB'tan az

### Acceptance Criteria
- [ ] 100K mesajlı bir conversation açıldığında uygulama 1 saniye içinde ilk 50 mesajı gösteriyor
- [ ] Scroll ile geriye doğru gittikçe sayfalar lazy load oluyor (network/disk delay görünür değil)
- [ ] 500 conversation'lı listede ekran açılışı < 500ms
- [ ] LeakCanary ile leak detect edilmiyor

### Rollback Plan
- Paging 3 sorunlu olursa eski LazyColumn + manual offset/limit pattern'e geri dön (ama 100K limit'i 1000'e düşür)

---

## FAZ 6 — WEBRTC SFU AGENT (OPSİYONEL — 5+ KİŞİ GRUP ARAMA İÇİN)

**Branch:** `migration/phase-6-sfu`
**Süre tahmini:** 4-7 gün
**Bağımlılık:** Faz 1-4 tamamlanmış olmalı.

> **Not:** Eğer kullanım senaryonda grup arama 5 kişiyi geçmiyorsa bu fazı **SKIP ET**. Mesh topology 5 kişiye kadar sorunsuz çalışır. SFU eklemek mimari complexity'yi ciddi artırır.

### Görev
Janus Gateway'i Docker üzerinde kur, signaling protocol'ünü Janus'a bridge et, Android client'ı SFU mode'a uyumla. **DM aramalar (1-1) hâlâ peer-to-peer mesh'te kalsın** — sadece grup aramalarda SFU devreye girsin.

### Yapılacaklar

#### 6.1 Janus Gateway Kurulumu
- `infra/janus/docker-compose.override.yml`:
  - `canyan/janus-gateway` veya official Janus image
  - VideoRoom plugin enable
  - Admin API enabled, password protected
  - WebSocket transport (8188), Admin WS (7188)
  - STUN/TURN config (mevcut TURN'a point eder)

#### 6.2 Backend Bridge
- Yeni service: `JanusOrchestrator.kt`
  - Grup arama başladığında Janus'a yeni VideoRoom oluştur (room_id = groupId)
  - Üyelere "join VideoRoom X" signaling mesajı gönder (E2E session sırasında)
  - Arama bitince room destroy et
- DTLS-SRTP zorunlu, Janus'ta RTP unencrypted akmayacak

#### 6.3 Client Migration
- `PeerConnectionManager`:
  - Grup büyüklüğü ≥ 4 → SFU mode (tek PeerConnection Janus'a)
  - Grup büyüklüğü < 4 → Mesh mode (mevcut davranış)
- Janus VideoRoom subscriber/publisher pattern uygula

#### 6.4 Test
- 10 kişilik grup arama: tüm üyeler birbirini görüyor + duyuyor
- 20 kişilik grup arama: çalışıyor (mesh'te imkansızdı)
- Bandwidth ölçüm: SFU mode'da kullanıcı upload bandwidth'i 1 stream ile sınırlı (mesh'teki gibi N-1 değil)

### Acceptance Criteria
- [ ] 10+ kişilik grup arama stabil çalışıyor
- [ ] Mesh mode (≤3 kişi) hâlâ çalışıyor (regression yok)
- [ ] Bandwidth kullanımı SFU mode'da ~1Mbps upload/user (mesh'teki gibi N×1Mbps değil)

### Rollback Plan
- Feature flag `USE_SFU=false` ile tüm gruplarda mesh mode'a geri dön

---

## GENEL TEST STRATEJİSİ (TÜM FAZLAR İÇİN)

### Test Katmanları
1. **Unit test** — yeni eklenen her sınıf için (Repository, RateLimiter, vb.)
2. **Integration test** — Testcontainers ile gerçek PostgreSQL + Redis instance'ları
3. **Load test** — k6 veya Gatling ile 5000 eşzamanlı kullanıcı senaryosu
4. **Chaos test** — Faz tamamlandığında: sunucu restart, DB bağlantı kopması, Redis crash → recovery doğrulanmalı

### Load Test Senaryoları (k6)
- **Scenario A — Normal usage:** 5000 user, dakikada 10 mesaj/user, 1 saat sürdür
- **Scenario B — Burst:** 1000 user 10 sn'de bağlanır, hepsi 100 kişilik gruba mesaj gönderir
- **Scenario C — Recovery:** Test sırasında server restart → mesaj kaybı = 0 olmalı

### CI/CD
- Her PR'da: lint + unit test + integration test (Testcontainers)
- Main'e merge'de: load test minimal scenario + Docker image build + staging deploy
- Manuel approve sonrası production deploy

---

## GÜVENLİK CHECKLIST (DEPLOYMENT ÖNCESİ)

- [ ] `.env` production'da güçlü secret'larla dolduruldu (`openssl rand -base64 32`)
- [ ] PostgreSQL ve Redis sadece internal Docker network'te (host'a port expose YOK)
- [ ] Nginx TLS 1.2 minimum, modern cipher suite (Mozilla SSL Config Generator önerisi)
- [ ] HSTS header (`max-age=31536000; includeSubDomains`)
- [ ] Tüm secret'lar `.gitignore`'da, repo'ya commitlenmemiş (git-secrets ile pre-commit hook)
- [ ] Backup şifreli storage'a (LUKS, S3 SSE, vb.)
- [ ] Monitoring alert'leri kurulu: high error rate, DB connection exhausted, disk > 80%, Redis OOM
- [ ] Log retention policy: audit log 90 gün, app log 30 gün
- [ ] DDoS basic protection: Cloudflare veya VPS provider firewall
- [ ] APK için ProGuard/R8 enabled (release build)
- [ ] Dependency vulnerability scan (Snyk, OWASP Dependency Check) CI'da

---

## DOKÜMANTASYON ÇIKTILARI

Her faz tamamlandığında ilgili dokümanlar güncellensin:
- `docs/architecture.md` — yeni mimari diyagramı (mermaid)
- `docs/runbook.md` — operasyon prosedürleri (restart, backup, restore, rotate secrets)
- `docs/migration-log.md` — her fazın tamamlanma tarihi, karşılaşılan sorunlar, çözümler
- `CHANGELOG.md` — semantic versioning ile değişiklik kaydı

---

## CLAUDE CODE'A TALİMATLAR

1. **Faz sırasına KESİNLİKLE uyulacak.** P0 işler (Faz 1-3) atlanmadan P1+ işlere geçilmeyecek.
2. Her faz başlangıcında bu dokümanın ilgili bölümünü tekrar oku.
3. Mevcut codebase'i `tree -L 3` ve key dosyaları okuyarak öğren — varsayım yapma.
4. Test yazılmadan production kodu yazma (TDD önerilir).
5. Her faz sonunda **acceptance criteria'ları kullanıcıya raporla** — geçmediyse devam etme.
6. Belirsizlik olduğunda kullanıcıya sor — özellikle:
   - Mevcut JSON şemasında beklenmeyen alan görürsen
   - Mevcut tested behavior değişecekse
   - Faz 6 (SFU) gerekli mi belirsizse
7. Her commit message'ı conventional commits formatında: `feat(persistence): add UserRepository`, `chore(infra): docker compose v2 upgrade`
8. Code review için her PR'da:
   - Ne değişti
   - Neden değişti
   - Nasıl test edildi
   - Rollback nasıl yapılır
