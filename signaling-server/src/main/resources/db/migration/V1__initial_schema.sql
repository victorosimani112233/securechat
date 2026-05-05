-- V1: Initial schema (Flyway managed)
-- Bu dosya Flyway tarafindan ilk deployment'ta calistirilir.
-- Sonraki migrasyonlar V2__*.sql, V3__*.sql olarak eklenmelidir.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users
CREATE TABLE IF NOT EXISTS users (
    user_id UUID PRIMARY KEY,
    phone_hash VARCHAR(128) UNIQUE NOT NULL,
    encrypted_phone TEXT,
    registered_at BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
    last_seen_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_hash);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at) WHERE last_seen_at IS NOT NULL;

-- FCM tokens
CREATE TABLE IF NOT EXISTS fcm_tokens (
    user_id UUID PRIMARY KEY,
    token TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fcm_updated ON fcm_tokens(updated_at);

-- Group members
CREATE TABLE IF NOT EXISTS group_members (
    group_id VARCHAR(128) NOT NULL,
    user_id UUID NOT NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id);

-- Audit log
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
