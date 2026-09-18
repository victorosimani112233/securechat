-- The bot accepted any identity key the prekey endpoint returned:
-- `isTrustedIdentity` was unconditionally true and no peer identity was ever
-- stored. A compromised signaling process, database or internal network could
-- therefore swap a recipient's identity key and the bot would encrypt to the
-- attacker without any warning. Using the Signal transport does not by itself
-- give authenticated end-to-end encryption; an identity pin does.
--
-- Privacy: the row holds a purpose-separated blind recipient index and the
-- peer's *public* identity key sealed under BOT_MASTER_KEY. No raw account
-- UUID, no timestamp and no message relationship is stored, so the table
-- cannot rebuild a contact graph or an activity timeline.

CREATE TABLE IF NOT EXISTS bot_peer_identity (
    recipient_index     TEXT NOT NULL,
    device_id           INTEGER NOT NULL,
    identity_key_sealed BYTEA NOT NULL,
    PRIMARY KEY (recipient_index, device_id)
);

COMMENT ON TABLE bot_peer_identity IS
    'Trust-on-first-use pin of a recipient identity key; rotation needs an explicit operator approval';
