-- V5: Push token rows must not retain a directly linkable account UUID.
-- Runtime startup derives the keyed blind index and rewrites token ciphertext
-- because the HMAC/AEAD keys are intentionally not available inside PostgreSQL.

ALTER TABLE fcm_tokens DROP CONSTRAINT IF EXISTS fcm_tokens_pkey;
ALTER TABLE fcm_tokens ADD COLUMN id BIGSERIAL;
ALTER TABLE fcm_tokens ADD COLUMN user_index VARCHAR(64);
ALTER TABLE fcm_tokens ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE fcm_tokens ADD CONSTRAINT fcm_tokens_pkey PRIMARY KEY (id);

CREATE UNIQUE INDEX idx_fcm_private_user
    ON fcm_tokens(user_index)
    WHERE user_index IS NOT NULL;

-- Kept only for the bounded startup conversion window. New writes always set
-- user_id=NULL; the application refuses to serve before conversion completes.
CREATE UNIQUE INDEX idx_fcm_legacy_user
    ON fcm_tokens(user_id)
    WHERE user_id IS NOT NULL;
