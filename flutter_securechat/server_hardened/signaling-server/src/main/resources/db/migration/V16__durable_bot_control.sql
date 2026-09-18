-- The bot emergency stop was a single TTL-less key in a Redis instance that
-- deliberately runs without persistence and with `allkeys-lru`. A restart or
-- memory pressure therefore lifted the stop on its own: an operator control
-- meant to hold until explicitly cleared could fail open unattended.
--
-- Privacy: one boolean of operator state. No account, message, timing or
-- relationship data; a database snapshot reveals only whether sending is
-- currently halted.

CREATE TABLE IF NOT EXISTS bot_control (
    id              INTEGER PRIMARY KEY CHECK (id = 1),
    emergency_stop  BOOLEAN NOT NULL DEFAULT FALSE
);

INSERT INTO bot_control(id, emergency_stop)
VALUES (1, FALSE)
ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE bot_control IS
    'Durable operator control for the bot send pipeline; survives cache loss';
