-- Credential invalidation was Redis-only while that Redis is deliberately
-- persistence-free and runs with `allkeys-lru`. A restart or an eviction
-- therefore turned "revoked" back into "valid": logged-out refresh tokens
-- became usable again and a deleted account could refresh into new tokens.
-- Authentication safety state has to survive both, so it moves to PostgreSQL.
--
-- Privacy: both columns are opaque 128-bit random values, not counters and
-- not timestamps. A database snapshot therefore reveals no rotation count,
-- no account age and no activity ordering — only that a value exists. They
-- carry no relationship to any other account.
--
--   credential_epoch    invalidates every token of the account at once
--                       (logout, security event)
--   refresh_generation  binds a refresh token to the single newest rotation;
--                       replaying a superseded refresh token fails closed

ALTER TABLE users
    ADD COLUMN credential_epoch TEXT NOT NULL
        DEFAULT encode(gen_random_bytes(16), 'hex'),
    ADD COLUMN refresh_generation TEXT NOT NULL
        DEFAULT encode(gen_random_bytes(16), 'hex');

COMMENT ON COLUMN users.credential_epoch IS
    'Opaque random; rotating it invalidates every issued token for the account';
COMMENT ON COLUMN users.refresh_generation IS
    'Opaque random; only the newest refresh token generation is accepted';
