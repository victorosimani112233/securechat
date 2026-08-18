-- A registration grant is a one-time credential, but its "already used" marker
-- lived only in the persistence-free, `allkeys-lru` Redis. A restart or an
-- eviction inside the grant's 15 minute lifetime made a consumed grant
-- replayable, which is exactly the window an account claim must not have.
--
-- Privacy: the row holds a keyed blind index of the grant's random JTI and the
-- moment it stops being replayable. There is no account, e-mail, phone or
-- directory reference, so the table cannot link a registration to a person;
-- the retention worker removes rows once they expire.

CREATE TABLE IF NOT EXISTS registration_grant_use (
    grant_index TEXT PRIMARY KEY,
    expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_registration_grant_expiry
    ON registration_grant_use(expires_at);

COMMENT ON TABLE registration_grant_use IS
    'Durable single-use marker for registration grants; carries no account link';
