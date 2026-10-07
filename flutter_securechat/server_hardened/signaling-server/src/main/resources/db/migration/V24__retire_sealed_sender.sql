-- Sealed Sender mimarisi kaldirildi.
--
-- Istemci kripto cekirdegi vodozemac'a (Olm + Megolm, Apache-2.0) tasiniyor
-- ve o yiginda sealed sender'in karsiligi yok. Sunucu tarafi yazilmisti ama
-- hicbir istemci hic cagirmadi; kalmasi iki somut maliyet uretiyordu:
--
--   1. `/api/v2/sealed-sender/messages` kullanilmayan bir ANONIM giris
--      noktasiydi. Kimsenin izlemedigi bir anonim ingress, kullanilan bir
--      endpoint'ten daha kotudur.
--   2. `ProductionDeploymentPolicy` cevrimdisi imzalanmis bir trust root
--      sertifikasi sart kosuyordu; bu, production profiline gecisin
--      oniindeki engellerden biriydi. Mimari gidince engel de gidiyor.
--
-- Trust root ve server anahtarlari artik hicbir amaca hizmet etmiyor;
-- `PurposeSeparatedSecrets` zorunlu listesinden de cikarildi.

DROP TABLE IF EXISTS sealed_sender_retired_mailboxes;
DROP TABLE IF EXISTS sealed_sender_mailboxes;
