-- Bot API kaldirildi. Send-only bot servisi hic yayina alinmadi ve vodozemac
-- istemcilerinin cozemedigi eski Signal V3 bicimiyle sifreliyordu; ayrica
-- GPL signal-protocol-java'ya bagliydi. Tablolari dusurulur.
--
-- Tek DROP ifadesi: tablolar arasindaki bagimliliklari Postgres kendi
-- siralar. Indeksler tabloyla birlikte duser. `bot_identity` -> `users`
-- RESTRICT FK'si de tabloyla gider; boylece hesap silme artik bot
-- kimligine takilmaz.
DROP TABLE IF EXISTS
    bot_signed_prekey,
    bot_one_time_prekey,
    bot_signal_session,
    bot_control,
    bot_peer_identity,
    bot_identity,
    api_client;
