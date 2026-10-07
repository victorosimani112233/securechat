-- Olm tek kullanimlik anahtar kimlikleri TAMSAYI DEGIL.
--
-- V26 `key_id INTEGER` ile yazilmisti; bu libsignal aliskanligiydi. Olm'da
-- anahtar kimligi vodozemac tarafindan uretilir ve kabloda base64 bir dize
-- olarak gorunur (`sc_account_generate_one_time_keys` ciktisi
-- `{base64KeyId: base64Key}` seklinde bir eslemedir). Tamsayiya zorlamak
-- icin base64'u cozup u64 okumak gerekirdi; bu hem kirilgan hem de
-- istemcinin kimligi ile sunucunun sakladigi kimligi birbirinden
-- ayirabilen bir donusum ekler.
--
-- Kimligin dogru saklanmasi kozmetik degil: catisma tespiti ona dayaniyor.
-- Kimlik kaybolur veya bozulursa, "ayni kimlik farkli materyalle geldi"
-- durumu tespit edilemez ve sunucu yeni yuklemeyi sessizce yutar — bu
-- projede daha once P0 ureten sekil tam olarak budur.
--
-- V26 cok yeni ve bu tablolar henuz uretimde kullanilmadi; yine de yerinde
-- duzeltme yerine ayri migration tercih edildi, cunku V26'nin herhangi bir
-- ortamda uygulanmis olup olmadigini varsaymak yanlis olur.

ALTER TABLE olm_one_time_prekeys
    ALTER COLUMN key_id TYPE TEXT USING key_id::TEXT;
