-- V7: group membership is a social graph. Raw group IDs and account UUIDs
-- must not remain in PostgreSQL. Runtime startup performs keyed-index + AEAD
-- conversion because privacy keys are intentionally unavailable to SQL.

ALTER TABLE group_members DROP CONSTRAINT IF EXISTS group_members_pkey;
ALTER TABLE group_members ADD COLUMN id BIGSERIAL;
ALTER TABLE group_members ADD COLUMN group_index VARCHAR(64);
ALTER TABLE group_members ADD COLUMN user_index VARCHAR(64);
ALTER TABLE group_members ADD COLUMN user_id_enc TEXT;
ALTER TABLE group_members ALTER COLUMN group_id DROP NOT NULL;
ALTER TABLE group_members ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE group_members ADD CONSTRAINT group_members_pkey PRIMARY KEY (id);

DROP INDEX IF EXISTS idx_group_members_user;
DROP INDEX IF EXISTS idx_group_members_group;

CREATE UNIQUE INDEX idx_group_members_private_pair
    ON group_members(group_index, user_index)
    WHERE group_index IS NOT NULL AND user_index IS NOT NULL;
CREATE INDEX idx_group_members_private_group
    ON group_members(group_index)
    WHERE group_index IS NOT NULL;
CREATE INDEX idx_group_members_private_user
    ON group_members(user_index)
    WHERE user_index IS NOT NULL;

-- Exists only for the startup conversion window and controlled rollback.
CREATE UNIQUE INDEX idx_group_members_legacy_pair
    ON group_members(group_id, user_id)
    WHERE group_id IS NOT NULL AND user_id IS NOT NULL;
