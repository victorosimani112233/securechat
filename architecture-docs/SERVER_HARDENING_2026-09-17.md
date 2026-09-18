# Sunucu sertlestirme turu — 2026-09-17

Bu tur, Sealed Sender / anonim mailbox calismasi sonrasi sunucuda kalan
guvenlik aciklarini ve best-practice sapmalarini kapatir. E2EE sinirina
dokunulmadi: sunucu hicbir noktada mesaj icerigini goremez, cozemez ve
saklamaz.

## Kapatilan guvenlik aciklari

### 1. Anonim relay uzerinden yukseltmeli Redis tuketimi

`enforceReliableQueueLimits`, kuyruk sinirlarini hesaplamak icin alicinin
bekleyen butun ciphertext'ini (1000 kayda / 50 MB'a kadar) Redis'ten uygulamaya
cekiyordu — sadece uzunluklarini toplamak icin. Anonim relay kimlik dogrulamasi
istemedigi ve mailbox basina 600 istek/dk'ya izin verildigi icin, capability'yi
bilen tek bir taraf dakikada on GB'larca Redis trafigi ve ayni miktarda JVM
copu uretebiliyordu.

Sinir artik Redis icinde tam sayi defterinden hesaplanir
(`deliveryToken -> "<byte>:<itemKey>"`). Payload ag uzerinden hic gecmez ve
maliyet kuyruk boyutundan bagimsizdir.

Ayni desen gecici sinyal/dosya kuyruklarinda da vardi ve orada bir yazim
basina elli kereye kadar tekrarlaniyordu; o da tek Lua turuna indirildi.

### 2. Kuyruk tasmasinda bekleyen mesajlarin silinmesi

Tasmada **en eski** kayitlar siliniyordu. Anonim relay ile birlestiginde bu,
capability'yi bilen herkesin alicinin bekleyen butun mesajlarini iki dakikadan
kisa surede temizletebilmesi demekti — kimlik dogrulamasi, engelleme veya iz
olmadan.

Davranis fail-closed'a cevrildi: kuyruk doluysa bekleyen ciphertext korunur,
**yeni** mesaj `503` ile reddedilir ve gonderen yeniden dener.

### 3. Rotasyon sonrasi mailbox ele gecirme

`sealed_sender_mailboxes.mailbox_index` UNIQUE'ti ve rotasyonda satir
guncellendigi icin eski indeks serbest kaliyordu. Rotasyondan once
capability'yi ogrenmis bir peer, eski adresi kendi mailbox'i olarak
kaydedip oraya gonderilen zarflari toplayabilirdi. Icerigi cozemez, fakat
kimin-ne-zaman metadatasini elde eder ve mesajlari sessizce dusururdu.

`V22` ile emekli indeksler otuz gun tombstone'lanir. Tombstone satiri hicbir
hesaba bagli degildir (`mailbox_index`, `retired_until`), bu yuzden yeni bir
sosyal grafik yuzeyi olusturmaz ve suresi dolunca retention worker tarafindan
silinir.

### 4. Trust root ozel anahtarinin relay'de bulunmasi

Sealed Sender trust root public key'i mobil binary'ye pinlidir. Ozel anahtar
internete bakan relay'de durdugu surece, relay'i ele geciren biri istedigi
hesap adina gecerli sender certificate uretebilir ve bu **ancak yeni bir
uygulama surumuyle** geri alinabilirdi.

Sunucu artik cevrimdisi imzalanmis bir server certificate ile calisir
(`SEALED_SENDER_SERVER_CERTIFICATE` + `SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY`).
Baslangicta sertifikanin pinli kok tarafindan imzalandigi dogrulanir.
`ProductionDeploymentPolicy`, ortamda trust root ozel anahtari bulursa
sunucuyu baslatmaz. Uretim araci:
`com.securechat.signaling.tools.SealedSenderOfflineKeygen`.

### 5. Post-quantum'u atlatan klasik prekey yolu

`GET /api/v1/users/{userId}/prekeys` kullanici token'i ile acikti ve PQXDH
olmayan, Sealed Sender tasimayan klasik bir bundle donuyordu. WebSocket'teki
downgrade korumasi yalnizca `SEALED:v1` cercevesini kapsadigi icin bu, V2
korumasini uygulama katmaninda etkisiz kilan sessiz bir yan yoldu.

V1 fetch artik yalniz servis assertion'i kabul eder. Bot (henuz PQXDH
konusmuyor) calismaya devam eder; istemciler birbirini dusuremez. Red,
bundle'in var olup olmamasindan bagimsizdir, yani hesap varligi oracle'i de
olusmaz.

### 6. Redis'in sessizce key atmasi

Redis `allkeys-lru` ile calisiyordu: bellek baskisinda TTL'i dolmamis herhangi
bir key atilabilir. Iki sessiz sonucu vardi — teslim edilmemis ciphertext
kaybolur ve rate limit pencereleri sifirlanir. Ikincisi saldirganin kuyruklari
doldurarak tetikleyebilecegi bir bypass'tir.

Politika `noeviction` yapildi; butun key'lerimiz zaten TTL tasiyor ve kuyruklar
uygulama tarafinda sinirli. `RedisEphemeralPolicy` tahliye eden bir politika
gorurse sunucu baslamaz.

## Best-practice duzeltmeleri

| Konu | Onceki durum | Simdi |
|---|---|---|
| Bloklayan I/O | JDBC/Jedis Netty event-loop'unda; eszamanlilik cekirdek sayisi kadar | Ayrilmis `BlockingIo` havuzu; event-loop yalniz ag olaylari |
| Jedis havuzu | `testOnBorrow=true` — her odunc almada fazladan PING | `testWhileIdle` ile arka planda dogrulama |
| Prekey fetch | Hedefin `users` satiri butun fetch boyunca `FOR UPDATE` | Kilitsiz varlik kontrolu; `SKIP LOCKED` yeniden anlamli |
| `modern_one_time_prekeys` | PK ile birebir ayni ikinci indeks | Kaldirildi (`V22`) — yazim basina tek indeks |
| Teslim ACK'i | `MULTI` + ayri `ZCARD`/`DEL` | Tek atomik Lua; boyut defteri de temizlenir |
| Credential onbellegi | Sinirsiz `ConcurrentHashMap` | 50.000 hesap tavani + stale tahliyesi |
| Guvenlik basliklari | HSTS yok | `Strict-Transport-Security` eklendi |
| Mailbox kayit hatalari | Eskimis generation ve bicim hatasi ayni kodda | `409` / `400` ayrildi |

## Mesaj yasam dongusu (degismedi, netlestirildi)

1. Gonderen cihaz mesaji libsignal PQXDH + Double Ratchet ile sifreler.
2. Zarf Sealed Sender ile sarilir; relay istegi JWT ve gonderen UUID tasimaz.
3. Sunucu ciphertext'i **acmadan ve bicimini dogrulamadan** alicinin
   RAM-only Redis kuyruguna koyar. PostgreSQL'e mesaj yazilmaz.
4. Alici bagliysa WebSocket'ten iletilir; degilse generic FCM wake-up gider.
5. **Alici mesaji kalici yerel deposuna yazip ACK gonderdigi anda sifreli
   kopya Redis'ten tek atomik adimda silinir.**
6. ACK gelmezse kayit TTL ile duser (varsayilan 15 dk, tavan 1 saat).
7. Hesap silindiginde butun kuyruk kopyalari ve mailbox kaydi temizlenir.

## Kapsanmayan, bilinen sinirlar

- **Bot hala klasik X3DH konusuyor.** Bot'un PQXDH'ye tasinmasi ayri bir is
  kalemidir; o tamamlanana kadar `signed_prekeys`/`one_time_prekeys` tablolari
  ve V1 upload yolu gereklidir.
- **Tek sunucuda IP/zaman korelasyonu.** Relay teslim icin hedef mailbox'i,
  baglanti kaynagini ve yaklasik zamani islem aninda gorur. Bunu kapatmak icin
  ayri operatorde oblivious ingress veya mix relay gerekir.
- **Ilk temas authenticated'dir.** Capability/prekey bootstrap'i sunucu
  tarafindan korele edilebilir.
- **Tek sunuculu OPRF** operatore karsi sozluk saldirisina acik kalir.
- **E-posta OTP telefon sahipligini kanitlamaz.**

Bu sinirlar `SEALED_SENDER_METADATA_PRIVACY.md` icinde ayrintili olarak
kayitlidir ve "sunucu kimin kiminle konustugunu hicbir kosulda ogrenemez"
garantisi verilmemektedir.
