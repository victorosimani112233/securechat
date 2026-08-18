-- Push retention needs a day bucket, not an exact activity timestamp.
ALTER TABLE fcm_tokens ADD COLUMN IF NOT EXISTS registered_on DATE;
UPDATE fcm_tokens
SET registered_on = COALESCE(registered_on, updated_at::date, CURRENT_DATE);
ALTER TABLE fcm_tokens ALTER COLUMN registered_on SET DEFAULT CURRENT_DATE;
ALTER TABLE fcm_tokens ALTER COLUMN registered_on SET NOT NULL;
DROP INDEX IF EXISTS idx_fcm_updated;
ALTER TABLE fcm_tokens DROP COLUMN IF EXISTS updated_at;
CREATE INDEX IF NOT EXISTS idx_fcm_registered_on
    ON fcm_tokens(registered_on);
