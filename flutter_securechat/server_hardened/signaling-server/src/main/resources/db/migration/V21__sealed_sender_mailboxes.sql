-- A mailbox is a self-owned anonymous-delivery endpoint, not a contact edge.
-- Raw mailbox IDs and write capabilities are never persisted. The server keeps
-- only purpose-separated HMAC indexes needed to authorize and route delivery.
CREATE TABLE sealed_sender_mailboxes (
    user_id UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    mailbox_index VARCHAR(43) NOT NULL UNIQUE,
    write_key_index VARCHAR(43) NOT NULL,
    protocol_version SMALLINT NOT NULL CHECK (protocol_version = 1),
    generation INTEGER NOT NULL CHECK (generation BETWEEN 1 AND 2147483647)
);

REVOKE ALL ON sealed_sender_mailboxes FROM PUBLIC;
