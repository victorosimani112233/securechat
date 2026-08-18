-- Privacy hardening: even keyed-pseudonymous event rows form a behavioral
-- timeline. Abuse prevention remains enforced by RAM-only Redis rate limits;
-- operations receive identity-free aggregate counters only.
DROP TABLE IF EXISTS audit_log;
