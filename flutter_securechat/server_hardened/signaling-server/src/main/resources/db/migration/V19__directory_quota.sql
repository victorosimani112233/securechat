-- Kalici private-directory OPRF kotasi (P2-02).
--
-- Kota daha once yalniz Redis sliding window ile tutuluyordu. Redis bu
-- dagitimda kasten kalicisizdir (RDB kapali, bkz. RedisEphemeralPolicy);
-- restart ya da bellek baskisi tum kotalari sifirliyordu. Bir hesap
-- Redis'i dusurebildigi ya da yalnizca bekledigi surece gunluk aday
-- sinirini istedigi kadar tekrarlayabiliyordu.
--
-- Gizlilik: satir ham user_id degil blind index tasir, yalniz gun kovasi
-- ve sayac tutulur, davranis zaman cizelgesi olusturacak bir zaman damgasi
-- gecmisi yoktur ve satirlar iki gunden eski olunca silinir.
CREATE TABLE IF NOT EXISTS directory_quota (
    account_index TEXT PRIMARY KEY,
    day_bucket    INTEGER NOT NULL,
    used          INTEGER NOT NULL,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_directory_quota_day
    ON directory_quota (day_bucket);
