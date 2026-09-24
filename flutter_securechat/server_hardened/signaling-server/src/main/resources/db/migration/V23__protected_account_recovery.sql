-- No plaintext email/UUID or FK linking recovery records to users.
CREATE TABLE account_recovery_bindings (
    account_index CHAR(64) PRIMARY KEY,
    email_index CHAR(64) NOT NULL UNIQUE,
    binding_version VARCHAR(43) NOT NULL,
    sealed_context BYTEA NOT NULL
);
CREATE TABLE account_recovery_challenges (
    challenge_index CHAR(64) PRIMARY KEY,
    purpose VARCHAR(16) NOT NULL CHECK (purpose IN ('enroll', 'login', 'complete')),
    account_index CHAR(64),
    email_index CHAR(64) NOT NULL,
    sealed_context BYTEA NOT NULL,
    proof_hash CHAR(64) NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX account_recovery_challenges_expiry ON account_recovery_challenges(expires_at);
CREATE INDEX account_recovery_challenges_account ON account_recovery_challenges(account_index);
-- Durable, purpose-separated hourly quotas; never raw addresses/IPs.
CREATE TABLE account_recovery_quotas (
    quota_index CHAR(64) PRIMARY KEY,
    used INTEGER NOT NULL CHECK (used > 0),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX account_recovery_quotas_expiry ON account_recovery_quotas(expires_at);
-- Only explicit recovery may set this pin. Both prekey namespaces enforce it.
ALTER TABLE users ADD COLUMN recovery_identity_pin BYTEA;
ALTER TABLE users ADD COLUMN recovery_identity_protocol VARCHAR(2) CHECK (recovery_identity_protocol IN ('v1', 'v2'));
CREATE TABLE account_recovery_receipts (
    challenge_index CHAR(64) PRIMARY KEY,
    account_index CHAR(64) NOT NULL,
    request_hash CHAR(64) NOT NULL,
    sealed_response BYTEA NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX account_recovery_receipts_expiry ON account_recovery_receipts(expires_at);
CREATE INDEX account_recovery_receipts_account ON account_recovery_receipts(account_index);
