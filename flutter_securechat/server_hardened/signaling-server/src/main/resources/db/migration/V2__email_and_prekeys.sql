-- V2: Email kolonu ekle ve PreKey bundle store
-- Email adresi + Signal Protocol prekey/identity key tablolari

-- Users tablosuna email + identity key kolonlari ekle
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS email VARCHAR(255),
    ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS identity_public_key BYTEA,
    ADD COLUMN IF NOT EXISTS registration_id INTEGER;

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;

-- Signed PreKey — kullanicinin imzali tek pre-key'i (Signal Protocol)
CREATE TABLE IF NOT EXISTS signed_prekeys (
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    key_id INTEGER NOT NULL,
    public_key BYTEA NOT NULL,
    signature BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, key_id)
);

-- One-Time PreKeys — tek kullanimlik pre-key havuzu (Signal Protocol)
CREATE TABLE IF NOT EXISTS one_time_prekeys (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    key_id INTEGER NOT NULL,
    public_key BYTEA NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, key_id)
);
CREATE INDEX IF NOT EXISTS idx_otpk_user_unconsumed ON one_time_prekeys(user_id) WHERE consumed_at IS NULL;
