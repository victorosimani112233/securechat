# Aktif Olarak Paylasilan Signaling JAR Incelemesi

Sonraki islem: Bu rapordaki orijinal JAR degistirilmeden, JAR'a ozel
davranislar mevcut yerel duzeltmelerle birlestirildi. Guncel kaynak ve
ayri artefaktin kaydi:
[SERVER_JAR_MERGE_2026-09-21.md](SERVER_JAR_MERGE_2026-09-21.md).
Asagidaki bulgular orijinal JAR'a aittir; yeni JAR'a otomatik uygulanmaz.

## Kimlik ve kapsam

- Girdi: `/home/user497/Desktop/signaling-server-all.jar`.
- Kullanici bu dosyanin canli sunucudaki aktif JAR oldugunu belirtti. Uzak
  process veya uzak dosyanin hash'i bu incelemede bagimsiz dogrulanmadi.
- Boyut: 86,393,228 bayt.
- SHA-256:
  `ae850bb2f310c4c38adb90b526ca860ee27be76fd2047d4216162b1347fc5630`.
- Manifest main sinifi: `com.securechat.signaling.ApplicationKt`.
- `build-info.properties`: `commit=` ve `builtAt=` bos,
  `migrationTarget=V22`. Bu son alan, canli veritabaninin migrasyon durumunun
  kaniti degildir.
- ZIP sinif tarihlerinde 21 Eylul 2026, 10:26 ve FCM degisikliklerinde 10:57
  gorunuyor. Bunlar saat dilimi/uretim ortami belirsiz arsiv tarihleridir;
  yazar, gercek duzenleme zamani veya deployment zamani olarak kullanilamaz.

## Yontem

JAR calistirilmadi, uygulama siniflari initialize edilmedi. CFR 0.152 ile
statik decompile ve JDK `javap -c -p` ile bytecode incelemesi yapildi.
CFR'nin Kotlin coroutine kodunu yapilandiramadigi yerlerde Java ciktisindaki
`Decompilation failed` bir uygulama hatasi sayilmadi; bytecode esas alindi.
Arac [resmi CFR sayfasindan](https://www.benf.org/other/cfr/) indirildi.

GitHub fetch sonrasinda `main` ve `github-codemagic/main`,
`bc210a45674f2162197003434c64d0cf2ccad50a` commit'indeydi. Bu commit'in
`flutter_securechat/server_hardened` agaci, mevcut calisma dosyalarina
dokunulmadan gecici dizine acildi ve offline `:signaling-server:compileKotlin`
ile basariyla derlendi. Bu derleme sunucuyu baslatmadi.

`com/securechat/signaling/` altindaki tum siniflar ZIP API'siyle okunup,
derlenen referanstaki siniflarin SHA-256 degerleriyle karsilastirildi:

| Sonuc | Sayi |
| --- | ---: |
| JAR uygulama siniflari | 428 |
| Referans uygulama siniflari | 428 |
| Birebir ayni sinif | 379 |
| Farkli sinif | 49 |
| Yalniz bir tarafta bulunan sinif | 0 |

49 farkli sinif, Kotlin'in uretilmis ic siniflari dahil yalniz uc kaynak
grubunda toplaniyor: `FcmTokenStore.kt`, `FcmPushSender.kt`, `HttpRoutes.kt`.
49 ayri kaynak dosya degistigi anlamina gelmiyor; satir/debug bilgisi
degisiklikleri de sinif hash'ini degistiriyor. Ucuncu taraf bagimliliklar,
tum kaynak dosyalarinin metni ve sunucu disi konfigurasyon bu bytecode
esitligi iddiasinin kapsaminda degil.

## JAR'da zaten bulunan, GitHub main'de olmayan degisiklikler

### Ayni token icin ipucu anahtarini koruma

`FcmTokenStore.registerToken`, yeni istekte anahtar yoksa onceki tokenin ayni
olup olmadigina bakiyor. Ayniysa onceki `pushHintKey` korunuyor; farkliysa
eski anahtar aktarilmiyor. Kayitta yalniz durum etiketi yaziliyor:
`hint_key=received`, `preserved`, `dropped_token_changed` veya `absent`.

**Onceki bulgunun duzeltmesi:** Anahtarsiz ayni-token yenilemesinin anahtari
silmesi, yerel GitHub referansinda vardi; paylasilan aktif JAR'da bu temel
durum onceden duzeltilmis. Bu nedenle bu kusur canli JAR'daki devam eden
arama sorununun dogrulanmis nedeni olarak gosterilemez.

### FCM tani kayitlari

- `HttpRoutes` kayit isteginde `hint_key_field=present/absent` yaziyor.
- `FcmPushSender` anahtar eksikse `Ipucu anahtari bulunamadi` uyarisi veriyor.
- Sifreli `k` eklendiginde `Sifreli tur ipucu eklendi` kaydi yaziliyor.
- Token/anahtar degerleri bu ek satirlarda aciga basilmiyor.

Dolayisiyla disarida yapilan duzenleme gercekten JAR'a yansimis; ancak bu
degisiklikler kontrol edilen GitHub main kaynaklarinda yok. Kimin yaptigi
JAR'dan tespit edilemiyor.

## JAR'da eksik kalan duzeltmeler

### 1. Arka plan baglantisi arama paketi tuketebiliyor

`ConnectionManager`, `WebSocketRoutesKt`, `MessageTypes` ve ilgili uretilmis
siniflar GitHub referansiyla bytebyte ayni. Bu JAR'da:

- `X-SecureChat-Call-Capable` sozlesmesi ve mesaj odakli baglanti ayrimi yok.
- `addConnection` her kabul edilen baglantida `deliverOfflineMessages` cagirir.
- `routeMessage` normal arama paketini alicinin herhangi bir acik soketine
  gonderir; bu yol basariliysa arama push yoluna girmez.
- `deliverOfflineMessages` teklif icin mevcut 30 saniyelik yas kontrolunden
  sonra sokete gonderir; mesaj odakli baglanti icin atlama kosulu yoktur.
- Bytecode'da `send` cagrisi offset 551, sonrasindaki kuyruk silme islemi
  offset 676-693'tedir. `deliverOfflineMessages$3.invoke`, `Jedis.zrem`
  cagirir. Arama isleyicisinden ayri teslim ACK'i beklenmez.

Bu, CallManager bulunmayan arka plan mesaj isolate'inin teklifi almasi ve
teklifin on plandaki arama ekranina kalmamasi riskini dogrular. Her saha
denemesinin bu yoldan gittigi, canli kontrollu deneme olmadan soylenemez.

### 2. Kayit guncellemesi ve okuma atomik degil

JAR ayni-token anahtar korumasini iceriyor; fakat `get` -> DB yazma -> `put`
sirasi per-kullanici atomik guncelleme degil. Suresi dolmus onceki kaydin
anahtarini korumadan once retention kontrolu de yapilmiyor.
Gonderici tokeni ve anahtari ayri `tokenLookup` / `pushHintKeyLookup`
cagrilarinda okuyor. Eszamanli kayit degisikliginde tutarsiz eslesme riski
devam ediyor. Yereldeki yeni yama, cache guncellemesini serilestiriyor ve
token/anahtari tek savunmali kopyadan okuyor.

### 3. Arama kontrolu yeni arama push'unu bastirabiliyor

JAR'da `call_control` ile `sdp_offer` / `group_call_invite` ayni
`lastCallPushTime` haritasini ve 3000 ms sinirini kullaniyor. Kontrolun
sifreli turu `m`, yeni gelen aramanin turu `c`; ilk kontrol push'u sonraki
arama ipucunu bastirabilir. Yerel yamadaki ayri kontrol kovasi JAR'da yok.

### 4. iOS VoIP push hatti yok

Incelenen FCM gondericisinde APNs turu `background`, oncelik `5` ve
`content-available` kullaniliyor. Bu, PushKit/VoIP APNs gonderimi degil.
Bu durum iOS kapali uygulama gelen arama yoluyla ilgilidir; iPhone'da
on planda CallKit arama baslatma hatasinin tek basina aciklamasi degildir.

### 5. Eski token hatasi yeni kaydi silebilir (yerelde de kalan risk)

JAR'da ve mevcut yerel yamada FCM gecersiz token hatasinin ardindan kayit
yalniz aliciya gore silinir. Eski tokena gonderim devam ederken yeni token
kaydedilirse, eski gonderimin hatasi yeni kaydi silebilir. Silmede basarisiz
gonderimin tokeniyle guncel tokenin eslesmesini denetleyen kosul yoktur.
JAR `sendWakeUpPush` bytecode offset 547-568; yerel `FcmPushSender.kt`
icindeki `tokenRemover(recipientId)` yolu. Bu incelemede kod degistirilmedi;
yerel yamanin bu yaris kosulunu da cozdugu iddia edilmiyor.

## Korunan mevcut gizlilik davranisi

JAR'da data payload `type=securechat_wake_v2` ve anahtar varsa sifreli `k`
iceriyor. Teklif/grup daveti `c`, diger uygun uyandirmalar `m` olarak
AES-GCM icinde iletiliyor. Caller ID, telefon, SDP veya acik mesaj turu
bu data alanlarina eklenmiyor. `PushHintCipher` referansla birebir ayni.
Arama push TTL'i 30 saniye. Bunlar JAR'daki statik kod bulgularidir;
FCM'nin kabul ettigi veya cihaza teslim ettigi anlamina gelmez.
Sifreli `k`, sifir metadata anlamina gelmez: saglayici hedef tokeni, zaman,
oncelik ve TTL'i gorur. Arama ve mesaj TTL'lerinin farkli olmasi da trafik
siniflandirmasina ipucu verebilir; mevcut yama bunu degistirmiyor.

## Sonraki adim ve degisiklik siniri

- Sirf GitHub main'i derleyip canliya yuklemek, bu JAR'a ozel anahtar koruma
  duzeltmesini geri alabilir. Mevcut yerel yeni yama temel korumayi zaten
  icerir ve concurrency/retention denetimini ekler; JAR'a ozel tani kayitlari
  ise birebir ayni formatta degildir. Bir sonraki birlestirmede bunlar
  bilerek korunmali veya yeni kayitlarla eslestirilmelidir.
- Asil eksik arka plan arama teslimi ve kontrol push siniri duzeltmeleri,
  uygun istemciyle birlikte derlenip kontrollu olarak denenmeli.
- Bu incelemede uygulama/sunucu kaynak kodu degistirilmedi, JAR degistirilmedi,
  sunucuya deployment veya restart yapilmadi. Yalniz bu rapor ve onceki
  rapora kanit guncellemesi eklendi.
- Onceki **159 sunucu testi yerel yeni yamaya aittir**. Aktif JAR calistirilip
  bu testlerden gecirilmis gibi yorumlanmamalidir.
- Tekrarlanabilir inceleme ara dosyalari gecici dizinde:
  `/tmp/securechat-jar-review-Ps0wna/` (`class-comparison.tsv`, decompile,
  bytecode ve temiz referans derleme kaydi). Gecici dosyalar kalici arsiv degildir.
