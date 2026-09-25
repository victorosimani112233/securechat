# Toplu Grup Dosyasi Anahtar Durumu Duzeltmesi

## Neden

Her dosya oncesinde SenderKey dagitimi yapiliyor. Kontrol mesajlari dosya
parcalarindan once islenebiliyor. libsignal_protocol_dart 0.8.2 icindeki
GroupSessionBuilder.process, ayni anahtar kimligi icin bile kaydin basina
yeni durum ekliyor. Son dagitim daha ileri bir sayac tasidiginda onceki
dosyanin sayaci eski gorunuyor ve DuplicateMessageException olusuyor.

## Degisiklik

SignalProtocolCryptoService.processSenderKeyDistribution, mevcut grup ve
gonderici kilidi altinda kayitli anahtar kimligini kontrol ediyor:

- Ayni kimlik ve ayni imza anahtari: mevcut zincir ve bekleyen mesaj
  anahtarlari korunur; dagitim durumu yeniden yazmaz.
- Ayni kimlik fakat farkli imza anahtari: hata verilir, kayit degistirilmez.
- Yeni kimlik: mevcut kutuphane uzerinden normal anahtar donusumu yapilir.

Sifreleme algoritmasi, paket bicimi, sunucu ve parca boyutlari degismedi.
Dosyalari gecikmeyle gonderme veya tekrar kontrolunu devre disi birakma yok.
Mevcut ileri-sayac siniri ve anahtar saklama sinirlari korunuyor.

## Testler

Ilk dort regresyon testi duzeltmeden once basarisiz, sonra basarili:
ileri sayacli tekrar dagitimi, atlanan mesaj anahtarlarinin korunmasi,
imza anahtari cakismasi ve anahtar donusumu. Eski dagitimin tuketilmis
mesajlari yeniden cozdurememesi de kontrol edilir.

Dort ek entegrasyon senaryosunda gercek MediaMessageService,
IncomingMessageHandler ve Signal sifrelemesi kullanilir. 280, 6590 ve
41540 baytlik uc dosya birlikte gonderilir; tum kontrol mesajlari once
islenir. Normal/tek gosterimlik ve duz/ters dosya gelis sirasinda alinan
baytlar, dosya adlari, veritabani kayitlari ve aciklama kontrol edilir.

Sonuc: sifreleme, grup medya uyeligi/yasam dongusu, gelen mesajlar ve
medya testlerinden olusan yedi dosyada **74/74 test gecti**. Buna 20,4 MiB
birebir ve grup aktarim testleri de dahil. Degisen iki Dart dosyasinda
statik analiz temiz. Sonraki tam tarama sonucu asagidadir.

## Dagitim ve Sinirlar

Android ve iOS ayni Dart duzeltmesini alir. Alicilarin guncellenmesi gerekir;
sunucu JAR'i degismez. Onceden dusmus dosyalar yeniden gonderilmelidir.
Bu degisiklik grup aramasi hatasini veya cevrimdisi dosya aktariminin
ACK/yeniden gonderim eksigini cozmez. Fiziksel Android sonuclari asagida;
iOS teslimi dogrulandi sayilamaz.

## 1.0.101 Fiziksel Android Tekrari

Iki Samsung'da versionName 1.0.101 / versionCode 2101 dogrulandi.
A = S4A, B = SJK ile biten cihaz. Uygulama verileri korunarak guncellendi.

- A -> B, ayni secimde TXT + M4A + MP4: uc dosya da 11:23:31'de alindi.
  Alicida dosyalar acildi; Paylas uzerinden gecici, ag izni olmayan QA
  aracina verilerek SHA-256 hesaplandi. Ucu de kaynakla eslesti.
- B -> A, ayni uc dosya: 11:27:13-14'te alindi. Alicida uc dosyanin
  SHA-256 degeri tekrar kaynakla eslesti. Iki yonde de onceki
  DuplicateMessageException gorulmedi.
- A -> B, ayni secimde iki tek gosterimlik PNG: 11:30:16 ve 11:30:19'da
  her biri 432282 bayt, 9/9 parca ile tamamlandi. Ikisinin korumali
  goruntuleyicisi acildi; kapatildiktan sonra ikisi de Acildi durumuna
  gecti. Tuketilen ilk karta tekrar dokununca goruntuleyici acilmadi.
  Korumayi kaldirarak ekran goruntusu veya disari aktarim yapilmadi;
  uygulamanin ozel dosya alanindan silinmesi bu fiziksel testte okunmadi.
  Sunum icin 10:39'da birakilan onceki tek gosterimlik ornege dokunulmadi.

Kaynak SHA-256 degerleri:

| Dosya | Bayt | SHA-256 |
| --- | --- | --- |
| Sunum_Ajandasi.txt | 280 | 7579d4d1893a793e0c0ffd3168a7a65866fd370e72efc69d2c3e11164093bcb6 |
| Sunum_Sesi.m4a | 6590 | 6b43b07cd75dd9d8f797c8954be14b4c7fbc135aebcf3bcc203bb49c907b522d |
| Sunum_Videosu.mp4 | 41540 | 7630335d776ab674afb16d58905fe32dfc468b4f28f0bec37753ae3549c95f08 |

### Buyuk Toplu Aktarim: Basarisiz / Takilma

A -> Elcim Sunum (uc uye: iki Android ve iOS), ayni secimde 600 KiB ve
20,4 MiB gonderildi. Iki Android de on planda ve mobil internete bagliydi.
600 KiB, 11:32:13'te 13/13 parca ve 614400 bayt ile tamamlandi.
20,4 MiB icin alicida 11:32:15'te 0 indeksli frame, 11:32:16'da 1/436
ilerleme goruldu. 11:37'ye kadar yeni 32-parcalik ilerleme veya tamamlanma
olayi yoktu. Log her parcayi yazmadigi icin tam olarak yalniz bir parca
alindigi iddia edilmez. Gonderici tum parcalari yerel sokete yazmis olsa
da bu alicinin teslim aldiginin kaniti degil.

B -> A kontrol mesaji 11:35'te hemen geldi; A -> B kontrol mesaji alicida
gorulmedi. Onceki DuplicateMessageException bu denemede gorulmedi.
Sunucunun /health endpoint'i kullanilan sertifika public-key pin'i
dogrulanarak sorgulandi ve status=ok dondu. Eski SSH master oturumu komutlara
yanit vermedi; yeni baglanti kimlik dogrulamasi gerektirdiginden canli
sunucu logu okunamadi. Yeni yonetim baglantisi kullanicidan istendi.

Kodda WebSocketRoutes gelen frame'leri sirayla handleMessage'e veriyor;
ConnectionManager.routeMessage ise recipientSession.send cagrisina sure
siniri koymuyor. Yavas bir aliciya yazarken gondericinin sirasi tikanabilir.
Bu, gozleme uyan bir hipotezdir; canli sunucu izi olmadan kesin neden
olarak isaretlenmez. Sunucu kodu veya calisan JAR degistirilmedi.

### Yeni SSH Oturumu ve Birebir Karsilastirma

Sonradan acilan yonetim oturumuyla calisan surec ve log kontrol edildi.
Surum `403b85c-dirty-media-transfer-20260924`, migrasyon V23 idi.
Janus URL/gizli anahtar yapilandirmasinin olmadigi goruldu; degerler
rapora veya istemciye kopyalanmadi. Eski loglarda Janus baslatma hatasi
vardir; bu tek basina buyuk dosya takilmasinin nedeni degildir.

11:32 civarindan kalan bir TCP baglantisi uzun sure cevap alamiyordu.
Bunun yavas bir alici mi yoksa gonderici uplink'i mi oldugu kanitlanmadi.
Dolayisiyla sirali server fan-out hipotezi kesin tani olarak sunulmaz.
Gonderici yeniden one gelince bekleyen kontrol metni ulasti, eski yarim
dosya kendiliginden tamamlanmadi.

Ayni 20,4 MiB dosya birebir A -> B gonderiminde 11:45:47-11:46:30
arasinda 164/164 parca ile tamamlandi. B'de 11:47:40'ta olculen SHA-256:
`4875e70520577a238cf6c784c4802c1e7fd44cf4ef52d6a7dc096d89f1a540e8`.
Bu kaynakla aynidir. Birebir basari, buyuk grup aktarimini gecti yapmaz.

### Test Taramasi

1.0.101 kaynaklariyla tum Flutter testleri yeniden calistirildi:
**965/965 gecti** (1 dakika 59 saniye). Onceki taramada gorulen SQLite
kilit hatasi bu turda tekrarlanmadi; bu, aralikli riskin giderildigi
anlamina gelmez. Fiziksel buyuk toplu aktarim yukaridaki nedenle gecti
olarak isaretlenmez. iOS alimi bu bilgisayardan dogrulanmadi.

APK SHA-256:
`49ec00bcf40d7e2eeb0c372949164819f8d96d65db60e67bd1f932e7beaa0dbb`.

Test sonunda gecici QA hash araci iki telefondan kaldirildi; sarjda
ekrani acik tutma degerleri eski hallerine dondu (A: 0, B: 15).
Hesaplar, uygulama verileri ve kisisel sohbetler silinmedi.
