-- Kurtarma kimligi libsignal Curve25519'dan vodozemac Ed25519 imzalama
-- anahtarina tasindi. Protokol etiketi artik 'olm'. Kolon VARCHAR(2) idi
-- ('v1'/'v2') ve CHECK yalniz onlari kabul ediyordu; genislet ve 'olm' ekle.
-- Eski degerler ('v1'/'v2') kabul edilmeye devam eder; mevcut satirlar bozulmaz.
ALTER TABLE users ALTER COLUMN recovery_identity_protocol TYPE VARCHAR(8);

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_recovery_identity_protocol_check;

ALTER TABLE users ADD CONSTRAINT users_recovery_identity_protocol_check
    CHECK (recovery_identity_protocol IN ('v1', 'v2', 'olm'));
