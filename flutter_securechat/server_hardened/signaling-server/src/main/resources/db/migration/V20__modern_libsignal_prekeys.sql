-- Rust libsignal/PQXDH public bundle namespace.
--
-- V1 and V2 identities are intentionally separate: their serialized key
-- formats and session protocols are incompatible. No private key or message
-- content is stored here. One-time EC+Kyber pairs are deleted in the same SQL
-- statement that returns them, and no consumption timestamp is retained.

CREATE TABLE modern_prekey_bundles (
    user_id                  UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    identity_public_key      BYTEA NOT NULL CHECK (octet_length(identity_public_key) BETWEEN 16 AND 128),
    registration_id         INTEGER NOT NULL CHECK (registration_id BETWEEN 1 AND 16380),
    signed_prekey_id         INTEGER NOT NULL CHECK (signed_prekey_id BETWEEN 0 AND 16777215),
    signed_prekey_public     BYTEA NOT NULL CHECK (octet_length(signed_prekey_public) BETWEEN 16 AND 128),
    signed_prekey_signature  BYTEA NOT NULL CHECK (octet_length(signed_prekey_signature) BETWEEN 32 AND 128)
);

CREATE TABLE modern_one_time_prekeys (
    user_id                  UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    key_id                   INTEGER NOT NULL CHECK (key_id BETWEEN 0 AND 16777214),
    ec_public_key            BYTEA NOT NULL CHECK (octet_length(ec_public_key) BETWEEN 16 AND 128),
    kyber_public_key         BYTEA NOT NULL CHECK (octet_length(kyber_public_key) BETWEEN 512 AND 4096),
    kyber_signature          BYTEA NOT NULL CHECK (octet_length(kyber_signature) BETWEEN 32 AND 128),
    PRIMARY KEY (user_id, key_id)
);

CREATE TABLE modern_last_resort_kyber_prekeys (
    user_id                  UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    key_id                   INTEGER NOT NULL CHECK (key_id BETWEEN 0 AND 16777215),
    public_key               BYTEA NOT NULL CHECK (octet_length(public_key) BETWEEN 512 AND 4096),
    signature                BYTEA NOT NULL CHECK (octet_length(signature) BETWEEN 32 AND 128)
);

CREATE INDEX modern_one_time_prekeys_user_key
    ON modern_one_time_prekeys (user_id, key_id);
