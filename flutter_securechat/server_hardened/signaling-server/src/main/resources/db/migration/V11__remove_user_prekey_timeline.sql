-- A consumed user one-time prekey is never needed by the server again. Keeping
-- consumed_at/created_at exposes session-bootstrap timing. Active public key
-- material remains, while historical timing columns are removed.
DROP INDEX IF EXISTS idx_otpk_user_unconsumed;
ALTER TABLE one_time_prekeys DROP COLUMN IF EXISTS consumed_at;
ALTER TABLE one_time_prekeys DROP COLUMN IF EXISTS created_at;
CREATE INDEX IF NOT EXISTS idx_otpk_user_available
    ON one_time_prekeys(user_id);

ALTER TABLE signed_prekeys DROP COLUMN IF EXISTS created_at;
