-- Privacy hardening: group membership is device-owned E2EE state.
-- The signaling server no longer retains even blind-indexed/encrypted social
-- graph rows. Live sender/recipient identifiers exist only while routing.
DROP TABLE IF EXISTS group_members;
