-- V2 (PQXDH) prekey yolu kaldirildi.
--
-- Bu yol Rust libsignal'in post-quantum bundle'i icin yazilmisti ve sunucu
-- tarafi tamamlanmisti, ama HICBIR istemci cagirmadi: ne Flutter istemcisi
-- ne bot-api'de tek bir `/api/v2` cagrisi vardi. Istemci kripto cekirdegi
-- vodozemac'a (Olm + Megolm) tasindigi ve vodozemac post-quantum
-- tasimadigi icin bu yolun bir gelecegi de yok.
--
-- Kaldirilmasinin iki somut guvenlik getirisi var:
--
--   1. IKINCI BIR PREKEY NAMESPACE'I ortadan kalkti. Iki namespace varken
--      saldirgan "oteki" namespace'i baslatip kendi kimligini oraya
--      dikebiliyordu; `PreKeyIdentityGuard.checkOtherNamespace` tam bu
--      capraz kontrol icin vardi. Tek namespace kalinca o saldiri sinifi
--      yapisal olarak imkansiz ve capraz kontrol de kaldirildi.
--   2. Kimlik artik tek kaynaktan okunuyor. `RecoveryAuthService` hesap
--      kimligini once `users`'tan okuyup sonra bu tablodan GECERSIZ
--      kiliyordu; iki kaynagin ayrilabildigi her yer bir tutarsizlik
--      firsatidir.
--
-- Tablolar bos olmadan dusurulurse veri kaybi olur; ama istemci hic
-- yuklemedigi icin production'da bos olmalari beklenir. `DROP TABLE`
-- yine de kasitli olarak kosulsuz: yarim kalmis bir v2 kaydinin ayakta
-- kalmasi, kimligi iki yerden okumaya devam etmekten daha kotu.

DROP TABLE IF EXISTS modern_one_time_prekeys;
DROP TABLE IF EXISTS modern_last_resort_kyber_prekeys;
DROP TABLE IF EXISTS modern_prekey_bundles;

-- ---------------------------------------------------------------------------
-- Olm (vodozemac) prekey materyali.
--
-- Eklemeli: libsignal kolonlari YERINDE kaliyor. Canli sunucuda calisan
-- istemci hala libsignal konusuyor; v1 cevabinin seklini degistirmek onu
-- aninda bozardi. Istemci cevrildikten sonra eski kolonlar ayri bir
-- migration ile dusurulur.
--
-- Kimlik NEREDE durur sorusu bu tasarimin merkezinde:
--
--   * Olm kimlik anahtari ve Ed25519 imza anahtari `users` SATIRINDA durur,
--     yani libsignal kimligiyle AYNI yerde. Boylece hesabin tek bir kimlik
--     konumu olur. Az once kaldirilan capraz-namespace saldirisi
--     (`checkOtherNamespace`) tam olarak kimligin iki tabloda
--     tutulabilmesinden dogmustu; onu geri getirmemek icin kimlik
--     bolunmuyor.
--   * Yalniz tek kullanimlik anahtar HAVUZU ayri tabloda. Havuz kimlik
--     tasimaz, dolayisiyla ayri olmasi bir kimlik yuzeyi yaratmaz. Ayri
--     olmasi gerekiyor cunku Olm anahtarlari 32 bayt, libsignal anahtarlari
--     tur onekiyle 33 bayt; ayni havuzda karistirilirsa libsignal
--     `Curve.decodePoint` 32 baytlik bir anahtarla patlar.

ALTER TABLE users ADD COLUMN IF NOT EXISTS olm_identity_key BYTEA;
ALTER TABLE users ADD COLUMN IF NOT EXISTS signing_public_key BYTEA;

-- Olm tek kullanimlik anahtar havuzu.
CREATE TABLE IF NOT EXISTS olm_one_time_prekeys (
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    key_id      INTEGER NOT NULL,
    public_key  BYTEA NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, key_id)
);
CREATE INDEX IF NOT EXISTS olm_one_time_prekeys_user_idx
    ON olm_one_time_prekeys (user_id);
REVOKE ALL ON olm_one_time_prekeys FROM PUBLIC;

-- Fallback (last-resort) anahtari: hesap basina bir satir.
--
-- Tek kullanimlik havuz bosaldiginda oturum kurulumu buradan surer. Bu yol
-- OLMASA havuz bosken bundle bos doner ve gonderen hic oturum kuramaz —
-- "No valid sessions" dongusunun sinifi tam budur.
--
-- Imza ZORUNLU (NOT NULL). Tehdit modeli dikkatle soylenmeli: sunucu kendi
-- fallback anahtarini koyarsa mesaji OKUYAMAZ, cunku oturum kurulumu
-- alicinin kimlik anahtariyla da DH yapar ve o ozel anahtar sunucuda
-- yoktur. Yapabildigi sey mesaji alicinin cozemeyecegi hale getirmek. Yani
-- imzasiz fallback bir MITM araci degil, sessiz ve kalici bir TESLIM REDDI
-- aracidir; sahada teshisi en pahali hata sinifi.
CREATE TABLE IF NOT EXISTS olm_fallback_keys (
    user_id     UUID PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    public_key  BYTEA NOT NULL,
    signature   BYTEA NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
REVOKE ALL ON olm_fallback_keys FROM PUBLIC;
