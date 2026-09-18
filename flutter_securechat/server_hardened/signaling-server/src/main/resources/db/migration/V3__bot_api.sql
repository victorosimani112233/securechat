-- V3: Bot API client registry + bot Signal identity/session store
--
-- Bot-api modulu icin gerekli schema. Bot, admin kullanicinin gondermek
-- istedigi otomasyon mesajlari icin ayri bir Signal user gibi davranir.
-- API caller'lar Ed25519 keypair ile authenticate olur (api_client tablosu).
--
-- ONEMLI: bot-api kendi Flyway calistirmaz. Sadece bu tablolari okur/yazar.
-- Bu migration'un signaling-server tarafindan calistirildigini varsayar.

-- =========================================================================
-- api_client: kayitli her bot/script (admin'in farkli otomasyonlari)
-- =========================================================================
CREATE TABLE IF NOT EXISTS api_client (
    client_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- kid: JWT header'inda gorunur. Opak, sunucu uretir, kullaniciya gosterilir.
    kid                 VARCHAR(64) UNIQUE NOT NULL,
    name                VARCHAR(128) NOT NULL,
    -- Ed25519 public key — raw 32 byte
    public_key          BYTEA NOT NULL,
    -- Allow-list: "user:<uuid>" veya "group:<group_id>" stringleri
    allow_list          TEXT[] NOT NULL DEFAULT '{}',
    rate_per_hour       INTEGER NOT NULL DEFAULT 50,
    per_recipient_per_day INTEGER NOT NULL DEFAULT 500,
    expires_at          TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,
    revoke_reason       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at        TIMESTAMPTZ
);
-- Aktif (revoked olmayan) client'lar icin hizli kid lookup
CREATE INDEX IF NOT EXISTS idx_api_client_kid_active
    ON api_client(kid) WHERE revoked_at IS NULL;

-- =========================================================================
-- bot_identity: bot user'inin Signal identity'si (SINGLETON, id=1)
-- =========================================================================
CREATE TABLE IF NOT EXISTS bot_identity (
    id                          INTEGER PRIMARY KEY CHECK (id = 1),
    bot_user_id                 UUID NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    registration_id             INTEGER NOT NULL,
    identity_public_key         BYTEA NOT NULL,
    -- AES-256-GCM ile BOT_MASTER_KEY altinda sifrelenmis private key
    identity_private_key_enc    BYTEA NOT NULL,
    identity_private_key_nonce  BYTEA NOT NULL,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rotated_at                  TIMESTAMPTZ
);

-- =========================================================================
-- bot_signal_session: bot'un her recipient ile kurdugu Signal session'i
-- Send-only oldugumuz halde session state Double Ratchet icin gerekli.
-- =========================================================================
CREATE TABLE IF NOT EXISTS bot_signal_session (
    recipient_user_id   UUID NOT NULL,
    device_id           INTEGER NOT NULL DEFAULT 1,
    session_record      BYTEA NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (recipient_user_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_bot_session_updated ON bot_signal_session(updated_at);

-- =========================================================================
-- bot_one_time_prekey: bot'un kendi one-time prekey havuzu
-- libsignal store contract'i icin gerekli; bot register olurken bundle yukler.
-- =========================================================================
CREATE TABLE IF NOT EXISTS bot_one_time_prekey (
    key_id              INTEGER PRIMARY KEY,
    public_key          BYTEA NOT NULL,
    private_key_enc     BYTEA NOT NULL,
    private_key_nonce   BYTEA NOT NULL,
    consumed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bot_otpk_unconsumed
    ON bot_one_time_prekey(key_id) WHERE consumed_at IS NULL;

-- =========================================================================
-- bot_signed_prekey: bot'un signed prekey'i (rotate edilebilir)
-- =========================================================================
CREATE TABLE IF NOT EXISTS bot_signed_prekey (
    key_id              INTEGER PRIMARY KEY,
    public_key          BYTEA NOT NULL,
    private_key_enc     BYTEA NOT NULL,
    private_key_nonce   BYTEA NOT NULL,
    signature           BYTEA NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================================
-- BOT_API_* event'leri icin partial index (audit_log uzerinde)
-- Mevcut audit_log tablosu degismez; sadece query performansi icin index.
-- =========================================================================
CREATE INDEX IF NOT EXISTS idx_audit_botapi
    ON audit_log(event_type, created_at DESC)
    WHERE event_type LIKE 'BOT_API_%';
