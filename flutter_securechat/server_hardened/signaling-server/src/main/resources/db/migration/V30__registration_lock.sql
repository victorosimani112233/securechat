-- Kayit kilidi PIN'i (istege bagli).
--
-- E-posta kodu tek basina hesabi yeni bir cihaza tasiyabiliyordu. PIN
-- acikken kimlik degistiren kurtarma ayrica PIN kaniti ister. PIN ve
-- istemcide turetilen kanit sunucuda saklanmaz; yalniz kanitin sunucu
-- anahtariyla HMAC'i (kor indeks) tutulur.
ALTER TABLE users ADD COLUMN registration_lock_verifier VARCHAR(64);
ALTER TABLE users ADD COLUMN registration_lock_failures INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN registration_lock_until TIMESTAMPTZ;
