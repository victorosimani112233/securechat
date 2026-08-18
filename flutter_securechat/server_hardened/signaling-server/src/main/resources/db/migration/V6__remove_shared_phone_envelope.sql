-- V6: The legacy encrypted_phone value used one application-wide embedded
-- key. A reverse-engineered client could therefore decrypt every captured DB
-- value. The hardened protocol resolves identities only from the device's
-- local contacts and never persists or returns this envelope.

ALTER TABLE users DROP COLUMN IF EXISTS encrypted_phone;
