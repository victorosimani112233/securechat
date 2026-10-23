-- libsignal (v1) prekey tablolari kaldirildi.
--
-- Istemci kripto cekirdegi vodozemac'a (Olm + Megolm) tasindi ve hicbir
-- istemci artik libsignal bundle'i yuklemiyor ya da okumuyor. Sunucu ise bu
-- tablolardaki eski anahtarlari `/api/v1/users/{id}/prekeys` yanitinda
-- servis etmeye devam ediyordu: Olm kimligine bagli olmayan ikinci bir
-- kimlik yuzeyi. Kalan satirlar eski libsignal hesaplarinin acik
-- anahtarlari; dusurulmeleri gizli veri kaybi degildir.
--
-- `users.identity_public_key` / `registration_id` bilerek kalir: kurtarma
-- akisi bu kolonlari okur.

DROP TABLE IF EXISTS one_time_prekeys;
DROP TABLE IF EXISTS signed_prekeys;
