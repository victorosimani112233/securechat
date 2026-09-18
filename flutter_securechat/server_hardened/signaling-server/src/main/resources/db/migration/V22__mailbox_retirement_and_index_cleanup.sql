-- V22: mailbox capability geri alinamaz sekilde emekliye ayrilir ve
-- modern prekey tablosundaki gereksiz indeks kaldirilir.
--
-- 1) Emekli mailbox tombstone'u
--
-- `sealed_sender_mailboxes.mailbox_index` UNIQUE'tir ve rotasyonda satir
-- guncellenir; eski indeks bu anda serbest kalirdi. Bir peer daha once
-- ogrendigi capability'yi kendi mailbox'i olarak kaydedip o adrese gonderilen
-- zarflari toplayabilir, icerigi cozemese de kimin-ne-zaman metadatasini
-- alabilir ve mesajlari sessizce dusurebilirdi.
--
-- Tombstone yalniz amac-ayrimli HMAC indeksini ve bir sona erme zamanini
-- tutar: hesap bagi yoktur, bu yuzden kimin hangi mailbox'i biraktigi
-- tablodan cikarilamaz. Kayit, gonderenlerin eski capability'yi unutmasi icin
-- gereken sureden sonra temizlenir.
CREATE TABLE sealed_sender_retired_mailboxes (
    mailbox_index VARCHAR(43) PRIMARY KEY,
    retired_until TIMESTAMPTZ NOT NULL
);

CREATE INDEX sealed_sender_retired_mailboxes_expiry
    ON sealed_sender_retired_mailboxes (retired_until);

REVOKE ALL ON sealed_sender_retired_mailboxes FROM PUBLIC;

-- 2) Gereksiz indeks
--
-- `modern_one_time_prekeys_user_key` ile PRIMARY KEY (user_id, key_id)
-- birebir ayni kolon sirasina sahiptir. Ikinci indeks hicbir sorguya hizmet
-- etmez; yalniz en buyuk tablonun her yazimini iki kez indeksler ve depolamayi
-- gereksiz buyutur.
DROP INDEX IF EXISTS modern_one_time_prekeys_user_key;
