-- V4: bot Signal sessions must not expose recipient UUIDs or raw ratchet
-- records at rest. Runtime startup performs the keyed-index + AEAD backfill
-- because HMAC/encryption keys are intentionally unavailable to PostgreSQL.

ALTER TABLE bot_signal_session
    ADD COLUMN IF NOT EXISTS recipient_index VARCHAR(64);

ALTER TABLE bot_signal_session
    DROP CONSTRAINT IF EXISTS bot_signal_session_pkey;

ALTER TABLE bot_signal_session
    ALTER COLUMN recipient_user_id DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_bot_session_private_recipient
    ON bot_signal_session(recipient_index, device_id)
    WHERE recipient_index IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_bot_session_legacy_recipient
    ON bot_signal_session(recipient_user_id, device_id)
    WHERE recipient_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bot_session_updated
    ON bot_signal_session(updated_at);

-- Encrypted api-client display names are longer than their plaintext form.
ALTER TABLE api_client
    ALTER COLUMN name TYPE TEXT;

-- Registration e-mail is used only in the short-lived one-time JWT and is
-- never an account profile field. Remove dormant columns and any legacy data.
DROP INDEX IF EXISTS idx_users_email;
ALTER TABLE users DROP COLUMN IF EXISTS email;
ALTER TABLE users DROP COLUMN IF EXISTS email_verified;
