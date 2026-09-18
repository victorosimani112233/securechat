# Sealed Sender ve metadata gizliligi

## Kapsam

Bu degisiklik dogrudan mesajlarin, teslim/okundu makbuzlarinin, ozel sohbet
kontrollerinin ve grup fan-out zarflarinin gonderici hesap kimligi tasimadan
relay edilmesini saglar. Mesaj icerigi resmi libsignal PQXDH/Double Ratchet ile
E2EE'dir; resmi libsignal Sealed Sender zarfi gonderici kimligini sunucudan
saklar.

Bu, "sunucu hic metadata goremez" iddiasi degildir. Relay teslimat icin hedef
mailbox'i, baglanti kaynagini, yaklasik zamani ve boyut kovasini islem aninda
gorur. Kod bunlari kalici uygulama loguna yazmaz; ham mailbox/write capability
degerlerini PostgreSQL veya Redis key'lerine koymaz. Kaynak IP ve zaman
korelasyonunu da gizlemek icin ayri bir oblivious proxy/Tor siniri gerekir.

## Protokol akisi

1. Her cihaz 256-bit rastgele `mailboxId` ve `writeKey` uretir. Degerler
   cihazdaki sifreli modern Signal state'inde tutulur.
2. Cihaz kendi mailbox'ini JWT ile kaydeder. Sunucu ham degerleri atar; yalniz
   amac-ayrimli HMAC indekslerini, kullanici bagini ve monoton generation'i
   saklar.
3. Ilk authenticated Signal mesaji gondericinin mailbox capability'sini E2EE
   plaintext icinde tasir. Sunucu capability'yi okuyamaz.
4. Alici capability'yi sifreli yerel depoya yazar. Sonraki mesaj resmi sender
   certificate ile Sealed Sender'a sarilir.
5. Istemci `SEALED:v1:<mailbox>:<writeKey>:<ciphertext>` yerel zarfini
   WebSocket'e gondermez. Ayri HTTPS relay istegi yalniz mailbox, ciphertext ve
   teslim kimligini tasir; JWT ve sender UUID tasimaz.
6. Sunucu ciphertext'i alicinin RAM-only, ACK tabanli Redis kuyruguna
   `senderId=sealed` olarak koyar. FCM/APNs yalniz generic wake-up uretir.
   Alici ACK gonderdigi anda sifreli kopya Redis'ten tek atomik adimda
   silinir; ACK gelmezse kayit TTL ile duser. Kuyruk sinirina ulasilmissa
   bekleyen mesajlar korunur ve **yeni** mesaj 503 ile reddedilir: anonim
   relay kimlik dogrulamasi istemedigi icin, tasmada en eskiyi silmek
   capability'yi bilen herkese alicinin kuyrugunu temizletme imkani verirdi.
7. Alici sender certificate imzasini pinned trust root ile dogrular, gercek
   sender UUID'sini cihazda cikarir ve receipt'i ogrendigi mailbox'a yeniden
   Sealed Sender ile yollar.

Authenticated WebSocket uzerinden `SEALED:v1` gonderimi downgrade/linkleme
girisimidir ve sunucuda reddedilir. Bir peer icin mailbox capability
ogrenildikten sonra istemci identified transport'a sessizce geri donmez.

## Rotasyon ve tekrar teslim

- Capability `generation` alani 1'den baslar ve yalniz artar.
- Rotasyonda birakilan mailbox indeksi `sealed_sender_retired_mailboxes`
  tablosunda otuz gun tombstone'lanir ve bu sure boyunca hicbir hesap
  tarafindan yeniden kaydedilemez. Aksi halde rotasyondan once capability'yi
  ogrenmis bir peer eski adresi kendi uzerine alip oraya gonderilen zarflari
  toplayabilir, icerigi cozemese de kimin-ne-zaman metadatasini elde eder ve
  mesajlari sessizce dusururdu. Tombstone satiri hesapla iliskili degildir.
- Istemci basarili self-registration'i alti saat onbellekler; reconnect bu sure
  dolunca ayni generation'i idempotent olarak yeniden kaydeder. Bu, server state
  restore/kaybi sonrasi ayni process icinde kendini onarir.
- Ayni generation + ayni anahtar idempotenttir; ayni generation + farkli
  anahtar cakisma olarak reddedilir; eski generation rollback'tir.
- HTTP yaniti kaybolursa ayni ciphertext ayni 256-bit teslim kimligiyle tekrar
  gider. Sunucunun Lua enqueue islemi duplicate retry'da TTL'i uzatmaz.
- Alici ciphertext'i kalici depoya yazip islemeden transport ACK gondermez.
  Uygulama mesaji icin E2EE `DELIVERED` receipt ayrica gereklidir.

## Boyut ve zaman gizliligi

Gonderim zamani ve mailbox capability E2EE ic metadatadadir. Relay kendi alma
zamanini yine bilir. Ic frame 1, 4, 16, 64 veya 128 KiB kovalarina doldurulur;
bu nedenle kucuk mesajlarin tam uzunlugu ciphertext boyundan cikmaz. 96 KiB
uzerindeki dogrudan plaintext ve 256 KiB uzerindeki relay ciphertext'i
fail-closed reddedilir.

## Anahtarlar ve build girdileri

Trust root **cevrimdisi** kalir. Sunucunun calismak icin trust root ozel
anahtarina ihtiyaci yoktur: yalniz trust root tarafindan bir kez imzalanmis
server certificate ve ona karsilik gelen server ozel anahtari gerekir.

Sebep: trust root public key'i mobil binary'ye pinlidir. Ozel anahtar relay'de
dursaydi, relay'i ele geciren biri istedigi hesap adina gecerli sender
certificate uretebilir ve bu ancak yeni bir uygulama surumuyle geri
alinabilirdi. `ProductionDeploymentPolicy`, ortamda
`SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY` bulursa sunucuyu baslatmaz.

Relay'e verilen degerler:

- `SEALED_SENDER_SERVER_CERTIFICATE` — cevrimdisi imzalanmis sertifika
- `SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY` — sertifikanin dogrulandigi pinli kok
- `SEALED_SENDER_SERVER_PRIVATE_KEY` — sender certificate imzalama anahtari

Sunucu acilirken sertifikanin gercekten pinli kok tarafindan imzalandigini
dogrular; yanlis eslenmis bir set sessizce yuklenmez.

Uretim araci (ag baglantisi olmayan bir makinede):

```bash
java -cp signaling-server-all.jar \
  com.securechat.signaling.tools.SealedSenderOfflineKeygen /secure/offline/sealed-sender
```

Arac dosyalari `0600` olusturur. `trust_root_private_key` cevrimdisi kasada
kalir ve sunucuya hicbir kosulda kopyalanmaz. Yazdigi 33-byte public root mobil
release'e su public build girdisiyle pinlenir:

```text
SECURECHAT_SEALED_SENDER_TRUST_ROOT=<base64-public-key>
```

Codemagic'te bu deger iki workflow'a acik
`securechat_sealed_sender_public_config` grubundan verilir. Private key'ler
Codemagic'e, Git'e veya mobil bundle'a konmaz. iOS ve Android ayni protokolu
kullanir; iOS'a ozel kriptografik fallback yoktur.

## Degisen baslica sinirlar

- `V21__sealed_sender_mailboxes.sql`: mailbox HMAC indeksleri ve generation.
- `V22__mailbox_retirement_and_index_cleanup.sql`: emekli mailbox tombstone'u
  ve `modern_one_time_prekeys` uzerindeki gereksiz ikinci indeksin kaldirilmasi.
- `AnonymousMailboxStore.kt`: self-registration, rollback korumasi ve sabit
  yetki sorgusu.
- `SealedSenderCertificateIssuer.kt`: 24 saatlik resmi sender certificate.
- `HttpRoutes.kt`: mailbox/capability/certificate ve anonim relay endpointleri.
- `ConnectionManager.kt`: sender kimligi icermeyen ACK tabanli teslim kuyrugu.
- `anonymous_mailbox.dart`: capability, certificate pinning ve anonim HTTP
  transportu; credential tasiyan isteklerde redirect reddi ve bounded response.
- `modern_signal_protocol_crypto_service.dart`: resmi Sealed Sender sifreleme,
  cozumleme, capability degisimi ve boyut padding'i.
- `incoming_message_handler.dart`: dis `senderId` yerine certificate ile
  dogrulanan kimlik, gercek peer'e receipt ve duplicate ACK.

## Kalan metadata riski

Sunucu hedef mailbox'in hangi hesaba teslim edilecegini bilmek zorundadir.
Ilk capability degisimi ve pre-key fetch'i authenticated bootstrap oldugu icin
ilk temas iliskisi sunucu tarafindan korele edilebilir. Sonraki relay
isteklerinde hesap credential'i yoktur fakat IP/zaman korelasyonu teorik olarak
gonderen ile aliciyi eslestirebilir. Bu riski daha da dusurmenin sirasi:

1. Ayri operator/bolgede oblivious ingress proxy veya Tor benzeri transport.
2. Private-contact-discovery icinden tek kullanimlik mailbox capability teslimi.
3. Zaman karistirma ve cover traffic; gecikme, pil ve bant genisligi maliyeti
   nedeniyle kullanici tarafindan acilabilen bir mod olmali.

Bu sinirlar kurulmadan "sunucu gonderici-alici iliskisini hicbir kosulda
ogrenemez" garantisi verilmez.
