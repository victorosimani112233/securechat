-- V8: Remove precise behavioral timestamps that are not required for
-- authorization, retention, key lifecycle, or account deletion.

DROP INDEX IF EXISTS idx_users_last_seen;
ALTER TABLE users DROP COLUMN IF EXISTS registered_at;
ALTER TABLE users DROP COLUMN IF EXISTS last_seen_at;

ALTER TABLE group_members DROP COLUMN IF EXISTS joined_at;

ALTER TABLE api_client DROP COLUMN IF EXISTS last_used_at;

DROP INDEX IF EXISTS idx_bot_session_updated;
ALTER TABLE bot_signal_session DROP COLUMN IF EXISTS updated_at;
