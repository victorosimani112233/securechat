-- Address-book SHA-256 values are low entropy and must not be visible to the
-- server during discovery. Existing rows already hold a server-HMAC blind
-- index; keep those rows marked with a NULL key id until the account itself
-- performs a bounded migration. New rows store only finalized blind-RSA OPRF
-- tokens tied to the dedicated directory key id.

ALTER TABLE users RENAME COLUMN phone_hash TO directory_token;
ALTER TABLE users ADD COLUMN directory_key_id VARCHAR(64);

DROP INDEX IF EXISTS idx_users_phone;
CREATE INDEX idx_users_directory_key
    ON users(directory_key_id)
    WHERE directory_key_id IS NOT NULL;

COMMENT ON COLUMN users.directory_token IS
    'Finalized private-directory OPRF token; legacy HMAC index only when key id is NULL';
COMMENT ON COLUMN users.directory_key_id IS
    'SHA-256 id of the dedicated directory OPRF public key';
