-- Privacy hardening: the V4/V5 compatibility columns made it possible for a
-- later regression to persist raw account UUID relationships again.  They are
-- reconstructible delivery/session state, but this migration still refuses to
-- delete or silently rewrite it.  Operators upgrading a populated pre-V14
-- database must first run the V13 release once so its fail-closed startup
-- converters seal every row, then deploy V14.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM fcm_tokens
        WHERE user_id IS NOT NULL
           OR user_index IS NULL
           OR token NOT LIKE 'v4:%'
    ) THEN
        RAISE EXCEPTION
            'V14 refused: migrate every push token to opaque v4 storage before dropping user_id';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM bot_signal_session
        WHERE recipient_user_id IS NOT NULL
           OR recipient_index IS NULL
    ) THEN
        RAISE EXCEPTION
            'V14 refused: migrate every bot session to an opaque recipient index before dropping recipient_user_id';
    END IF;
END
$$;

DROP INDEX IF EXISTS idx_fcm_legacy_user;
DROP INDEX IF EXISTS idx_fcm_private_user;
ALTER TABLE fcm_tokens DROP COLUMN user_id;
ALTER TABLE fcm_tokens ALTER COLUMN user_index SET NOT NULL;
CREATE UNIQUE INDEX idx_fcm_private_user ON fcm_tokens(user_index);

DROP INDEX IF EXISTS idx_bot_session_legacy_recipient;
DROP INDEX IF EXISTS idx_bot_session_private_recipient;
ALTER TABLE bot_signal_session DROP COLUMN recipient_user_id;
ALTER TABLE bot_signal_session ALTER COLUMN recipient_index SET NOT NULL;
CREATE UNIQUE INDEX idx_bot_session_private_recipient
    ON bot_signal_session(recipient_index, device_id);

COMMENT ON COLUMN fcm_tokens.user_index IS
    'Purpose-separated HMAC index; raw account UUID storage is structurally impossible';
COMMENT ON COLUMN bot_signal_session.recipient_index IS
    'Purpose-separated HMAC index; raw recipient UUID storage is structurally impossible';
