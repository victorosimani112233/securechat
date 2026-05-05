-- SecureChat PostgreSQL — initial schema
-- Bu dosya signaling-server kodunun ihtiyac duydugu tablolari olusturur.
-- Database.ensureSchema() backup mekanizmasidir; kanonik sema burasi.

-- Extension'lar
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- USERS — Kullanici kayit/kesfi
-- UserRegistry.kt: user_id, phone_hash, encrypted_phone, registered_at kolonlarini kullanir
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    user_id UUID PRIMARY KEY,
    phone_hash VARCHAR(128) UNIQUE NOT NULL,
    encrypted_phone TEXT,
    registered_at BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
    last_seen_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_hash);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at) WHERE last_seen_at IS NOT NULL;

-- ============================================================
-- FCM TOKENS
-- FcmTokenStore.kt: user_id, token, updated_at kolonlarini kullanir
-- ============================================================
CREATE TABLE IF NOT EXISTS fcm_tokens (
    user_id UUID PRIMARY KEY,
    token TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fcm_updated ON fcm_tokens(updated_at);

-- ============================================================
-- GROUP MEMBERS — Grup uyelik bilgisi (server-side fanout icin)
-- GroupMemberStore.kt: group_id (VARCHAR), user_id (UUID), joined_at kolonlarini kullanir
-- group_id "group_xxx" formatinda string oldugu icin VARCHAR (UUID degil)
-- ============================================================
CREATE TABLE IF NOT EXISTS group_members (
    group_id VARCHAR(128) NOT NULL,
    user_id UUID NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);

-- ============================================================
-- AUDIT LOG — Guvenlik olaylari (login, FCM register, rate-limit hit, vs.)
-- AuditLog.kt: user_id, event_type, metadata (JSONB), ip_address (INET), created_at
-- ============================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID,
    event_type VARCHAR(64) NOT NULL,
    metadata JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_user_time ON audit_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_event_time ON audit_log(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_log(created_at);

-- ============================================================
-- TEMIZLIK NOTLARI
-- ============================================================
-- audit_log buyumeye meyilli — pg_cron veya cron ile temizleme:
--   DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL '90 days';
--
-- Veya partitioning (uretim icin onerilir):
--   CREATE TABLE audit_log (...) PARTITION BY RANGE (created_at);
