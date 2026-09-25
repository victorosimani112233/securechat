# Etkilesim ve Kontrollu Monkey Testi (1.0.101 - 1.0.103)

Bu test turunda yuklenen surum: **1.0.103 (2103)**, iki fiziksel Android.
Sonraki **1.0.104 (2104)** mesgul arama duzeltmesi ve yukleme sonucu:
[Mesgulken Gelen Aramalar](BUSY_CALL_NOTIFICATION_2026-09-25.md).
Bu rapor tum olasi durumlarin veya iOS'un eksiksiz onayi degildir.

Test ortami: iki fiziksel Samsung Android 16, APK 1.0.101 (2101).
iOS bu bilgisayara bagli degil. Tum sonuclar bu iki Android'e aittir.
Test once bulgu toplama, sonra duzeltme ve regresyon sirasi ile yapilir.

## Sinirlar

Rastgele hesap silme, sohbet temizleme, rehber silme, gercek kisilere
kontrolsuz gonderim ve guvenlik ayarlarini gevsetme yok. Ekran korumasi
kaldirilmaz. Test gonderimleri yalniz bilinen test hesaplarina yapilir.
Gizli anahtarlar, tokenlar, telefon numaralari ve kisisel icerikler bu
rapora yazilmaz. Degistirilen cihaz/uygulama tercihleri geri alinir.

## Matris

| Alan | Senaryo | Durum |
| --- | --- | --- |
| Gezinme | Dort sekme, geri, kaydirma, kontrollu rastgele olaylar | Tur tamam; klavye odagi hatasi |
| Rehber | Arama, sonuc yok, tus takimi, yeni sohbet | Tur tamam; yanlis bos-sonuc metni |
| Grup olusturma | Bos ad, ad girisi, arama, secim, secimi kaldirma, olusturma | Iki test hesabi ile gecti |
| Toplu mesaj | Bos mesaj/alici, arama, coklu secim, test hesabina teslim | Canli gecti; hata enjeksiyonunda kismi sonuc hatasi |
| Planli mesaj | Alici, saat, olusturma, duzenleme ve gecmis | UI gecti; teslim acik, servis/gizlilik hatalari |
| Ayarlar | Dil, ses listesi, tema, gizlilik alt ekranlari | Tur tamam; semantik sinir hatasi |
| Hesap kurtarma | Form acilis ve geri | Gezinme denendi; dogrulama/e-posta gonderimi denenmedi |
| Depolama | Sohbet listesi, ayrintilar, geri | Gecti; veri silinmedi |
| Yedekleme | Parola kurallari, gecersiz giris, iptal | Form gecti; gercek yedekleme/geri yukleme denenmedi |
| Aramalar | Kayit filtreleri, sesli/goruntulu, bitirme, grup | Birebir baglandi; grup basarisiz |
| Sohbet | Uzun mesaj, tepki, anket, menu | Tepki gecti; ilk anket oyu hatasi; diger islemler kismi kapsam |
| Dosyalar | Kucuk toplu, tek gosterimlik, buyuk birebir/grup | Ayri dosya raporunda |

## Baslangic Bulgulari

- Kucuk toplu dosyalar iki yonde SHA-256 ile dogrulandi; tek gosterimlik
  iki gorsel alindi ve tekrar acilmadi.
- Buyuk toplu grup aktarimi 20,4 MiB dosyada takildi. Ayni dosya daha
  sonra birebir gonderimde 11:46:30'da 164/164 parca ile tamamlandi;
  11:47:40'taki alici SHA-256 kaynakla eslesti.
- Sunucunun eski TCP baglantilarindan biri uzun sure yanit alamiyor.
  Tekrar baglaninca bekleyen metin ulasiyor; eksik dosya otomatik
  tamamlanmiyor. Kesin neden ayirma testi ve teslim protokolu takibi acik.
- Sunucuda Janus gizli anahtar/URL ayarlari yok. Eski loglarda Janus
  baslatma hatasi grup arama kapanisini etkiliyor. Sunucu degistirilmedi.
- Baslangic tam otomatik tarama: 965/965 test gecti. Bu fiziksel
  etkileşimlerin veya iOS'un tumunun basarili oldugu anlamina gelmez.

## Bulunan Hatalar

Ilk tur tamamlandi; asagidaki bulgular duzeltmeden once kaydedildi.

1. Kapali plani duzenlemek plani etkinlestiriyor ve tekrar zamanliyor.
   Iki servis regresyon testi mevcut kodda basarisiz oldu.
2. Toplu gonderimde ikinci alicinin istisnasi ilk basarili alicinin sonucunu
   kaybettiriyor. Hata enjeksiyonlu test mevcut kodda basarisiz oldu.
3. Bekleyen planlar kilitli sohbetin icerigini onizlemede ve duzenlemede
   yetkilendirme olmadan gosterebiliyor (kod incelemesi).
4. Plan kaydet dugmesinde devam eden islem korumasi yok (kod incelemesi).
5. Ayarlarin gruplanmis satirlari ayri erisilebilirlik sinirlari tasimiyor;
   tema dugmesinin Android bounds'u desen/tam ekran anahtarlarini kapsiyor.
6. Yeni grupta ilk eylemi anket oyu olan uye oy veremedi. Ayni uye ilk
   metin mesajini gonderdikten sonra oy calisti; iki cihazda toplam 1 oldu.
7. Planli gonderim 11:56:59'da gecmiste Gonderildi oldu, alicida gozukmedi.
   Arka plan gondericisi kalici guvenilir kuyruga bagli degil; yerel socket
   kabulunu teslim kaniti sayamayiz. Kesin olay nedeni henuz kanitlanmadi.
8. Grup sesli arama Baglanti kurulamadi ile bitti. Canli sunucudaki Janus
   yapilandirmasi eksik; bu turda sunucu degistirilmedi.

Gozlemler: eski/yeni hesapli ayni isimli alicilar secicide ayirt edilmiyor.
Kriptografik kimlikleri otomatik birlestirmek guvenli bir cozum degildir.
Sekme degisimi sorunu gibi gorunen bazi otomasyon vuruslari acik klavyeye
ve sistem navigasyonuna denk geldi. Bunlar dogrulanmis uygulama hatasi
olarak sayilmadi; klavye kapatildiginda sekmeler degisti.

## Fiziksel Tur Sonuclari

- Her cihazda 30 kontrollu rastgele dongu tamamlandi (seed 101).
  Ilk B denemesi 16 donguden sonra okunmamis rozeti nedeniyle test secicisi
  hatasiyla durdu; duzeltilen secici ile 30 dongu yeniden calistirildi.
  Bu sayilar tek tek dokunma sayisi degildir. Rota ziyaretleri her alt
  islemin fonksiyonel olarak dogrulandigi anlamina gelmez.
- Toplu mesajda bos icerik/alici engellendi, arama ve coklu secim calisti.
  Iki alici icin gonderildi sonucu alindi; B'de gercek metin goruldu.
  iOS alicinin gercek teslimi bu oturumda kontrol edilemedi.
- Plan olusturma, duzenleme ve gecmis kaydi calisti; gercek teslim acik.
- Yeni grup bos ad/alici kontrolleri, arama, secim rozeti ve kaldirma
  denendi. QA101 Etkilesim grubu iki bagli test hesabiyla olusturuldu.
  Grup metni alindi. Anket ilk-oy hatasi yukarida ayri kaydedildi.
- Tepkiyi basparmaktan kalbe degistirince tek kalp/tek kisi kaldi;
  karsi cihazda da ayni sonuc goruldu. Mesaj menu alt secenekleri erisildi.
- Uzun mesaja Daha fazlasini gor dugmesi geldi ve genisletme denendi.
  Genisleme sonrasi daraltma bu turda ayrica dogrulanmadi.
- A'da dil English/Sistem ve tema Acik/Koyu degisimi yapilip geri alindi.
  Bildirim sesi secim listesi acildi; sesin isitilmesi dogrulanmadi.
- Depolamada sohbet listesi ve bos medya ayrintisi acildi; veri silinmedi.
  Yedek parolasi kisa/eslesmeyen iken dugme kapali, 9 karakterli eslesen
  parolalarda acik. Islem iptal edildi; kisisel yedek disa aktarilmadi.
- Birebir sesli/goruntulu arama iki cihazda baglandi ve sure ilerledi.
  Uygulama ici cevaplama, sessiz/sesi ac, hoparlor, kamera/cevir ve bitirme
  denendi. Uzaktan ses kalitesi veya korumali goruntunun pikselleri
  dogrulanmadi. Aramalar test sonunda bitirildi.
- Iki cihazin Android crash buffer'inda tur sonunda kayit yok.

## Duzeltme Sonrasi

- Son kodla tam test: **1003/1003 gecti**, 1 dakika 54 saniye.
  `flutter test --no-pub --reporter expanded`; yerel cikti
  `/tmp/securechat-qa102-tests-final.log`.
- `flutter analyze --no-pub`: **No issues found**.
- Kapali plan duzenleme, toplu gonderimde kismi hata, kilitli plan
  onizleme/duzenleme, cift kaydetme, ayarlar satir sinirlari, sekme
  degisiminde klavye odagi ve rehberde yanlis bos-arama metni duzeltildi.
- Kilitli plan duzenleyicisi arka planda temizleniyor. Alici secimi
  degistirilse bile orijinal sohbetin kilitlenmesi icerigi kapatiyor.
- Ilk grup eylemi anket oyu olabilir: oy oncesi mevcut SenderKey dagitilir.
  Gercek Signal ile ilk oy, secenek degistirme ve anahtar dagitimi
  basarisizken guvenli tekrar senaryolari gecti.
- Arka plan gondericisi mevcut sifreli yerel kalici kuyruga baglandi.
  Makbuz bekleme suresi sinirli; makbuz gelmezse ciphertext saklanir.
  Bekleme suresi tum gorevin veya platform kapanisinin ust siniri degildir.
  Ana uygulama acikken worker'in yazdigi kayit da yeniden gonderilebilir.
  Ayri isolate ile kalicilik, yeniden acilis ve dogru/yanlis makbuz testleri
  gecti. Gecmiste Gonderildi hala alicida okundu/teslim edildi demek degildir.
- Calisan plan gorevi kendisini iptal etmiyor; tekrar plani calisana
  ekleniyor. Kullanici iptali ve diger gorevlerin davranisi korunuyor.
- Onceki ara tam kosuda duzeltme henuz eklenmeden yuklenmis kendini-iptal
  testi basarisizdi. Yukaridaki temiz tam kosu tum degisikliklerden sonra
  yeniden alindi; basarisiz test atlanmadi.
- Yeni cihaz adayi: 1.0.102 (2102), Android ARM32 + ARM64. Fiziksel tekrar
  sonuclari asagiya eklenecek.

## 1.0.102 Cihaz Tekrari

- Iki telefona `adb install -r` ile yuklendi; paket surumu 1.0.102 / 2102.
  Mevcut test sertifikasi korundu, hesap/veri silinmedi.
- QA102 Ilk Oy grubunda A hic metin gondermeden B'nin anketine oy verdi.
  12:35'te iki cihazda da Toplam 1 oy goruldu. Onceki hata tekrarlanmadi.
- B rehberinde bulunmayan isim aramasi Sonuc bulunamadi sonucunu verdi.
  Ayarlar'a yatay kaydirinca klavye kapandi (`mInputShown=false`).
- Tema/desen/tam ekran erisilebilirlik dikdortgenleri birbirinden ayrildi:
  y=973-1175, 1175-1378, 1378-1597. Tema merkezine dokunmak tema secimini
  acti; desen anahtarina denk gelmedi. Secim degistirilmeden kapatildi.
- APK SHA-256:
  `b6feedc47cf97cf67b12c180b5f1e0bc24093e91e6c37f4f343363c6fe17e478`.
  Bu test dagitimi Android debug test sertifikasi ile imzalidir;
  magazaya yayim imzasi degildir.
- 12:39'a kurulan `QA102 planli gercek teslim` mesaji alici sohbetinde
  12:39 zamaniyla goruldu. Alici Ayarlar'dayken Sohbet rozeti 1 oldu.
  Gonderen uygulama yeniden baslatilmadi. Gecmis de ayni calismayi kaydetti.
- Ek regresyon: rehber aramasindan Ayarlar'a kaydirirken klavye kapansa
  da tema penceresini iptal edince eski rehber arama odagi geri geldi
  (`mInputShown=true`). Bu nedenle 1.0.102 son aday sayilmadi; ek odak
  duzeltmesi ve yeni cihaz tekrari gerekiyor.

## Son Ek Kontroller

- Tema dialogu kapatilirken gizli sekmenin tekrar odak almasi icin yeni
  regresyon testi once basarisiz oldu. Etkin olmayan sayfalar ExcludeFocus
  ile odak alamaz yapildi; 37 ilgili test gecti.
- Ardindan tam paket yeniden calistirildi: **1004/1004 gecti**, 1 dakika
  57 saniye (`/tmp/securechat-qa103-tests.log`).
- Medya onizleme Gonder dugmesine erisilebilir etiket eklendi. Bu son
  tek-satirlik UI degisikliginden sonra ilgili dosyada 6/6 test gecti;
  bunlardan biri yeni etiket testidir. Ilk etiket testi fiksturunde sahte
  saat altinda dosya I/O beklemesi vardi; fikstur saf belge metadatasiyla
  duzeltildi. Bu bekleme uygulama hatasi degildi.
- Planli mesaja gonderende Okundu makbuzu geldi. Mesaj Bilgisi ekraninda
  Grj-2 adi ve teslim/okundu bilgileri goruldu. Yildizlayip ana menudeki
  Yildizli Mesajlar'dan tiklayinca ayni sohbet mesajina donuldu.
- Yalniz A/B uyeli QA102 Ilk Oy grubunda 20,4 MiB dosya **436/436**
  parca ile alindi. Alicida 21390950 baytlik dosyanin SHA-256 degeri
  `4875e70520577a238cf6c784c4802c1e7fd44cf4ef52d6a7dc096d89f1a540e8`
  olarak olculdu; kaynakla ayni. Onceki uc-uyeli kesinti bu basariyla
  giderilmis sayilmaz; baglanti kopmasinda aktarimin devam ettirilmesi acik.

## 1.0.103 Sonuc ve Temizlik

- Iki telefonda 1.0.103 / 2103 paket bilgisi dogrulandi.
- B'de rehber aramasi -> Ayarlar'a kaydir -> tema dialogu -> iptal tekrar
  yapildi. Dialog kapandiktan sonra `mInputShown=false`; Sohbet sekmesine
  dokunma hemen calisti. Onceki klavye geri-acilma hatasi tekrarlanmadi.
- Son statik analiz temiz. Iki cihazda crash buffer bos.
- QA hash uygulamasi kaldirildi; gecici UI XML dosyalari temizlendi.
  Sarjda ekran-acik ayarlari A:0, B:15 degerlerine geri alindi.
  Test mesajlari/gruplari inceleme icin birakildi; hesaplar ve veriler korunuyor.
- Son APK: `build/app/outputs/flutter-apk/elcim-1.0.103-arm32-arm64-signed.apk`.
  SHA-256: `004bc931f809f1c18133b54a09302363f1be31128651d357b35b5a8e55b07daf`.
  ARM32/ARM64, mevcut test sertifikasi ile imzali.
- Sunucu kodu/JAR'i, canli yapilandirma ve Git uzak dali bu turda
  degistirilmedi. Kaynak duzeltmeleri yerel calisma agacindadir.

## Acik Kalanlar

- Canli grup aramasi basarisiz; sunucunun Janus yapilandirmasi ve arama
  akisi ayri kabul testinden gecmeli.
- Buyuk grup dosyasi iki Android ile hash dogrulamasindan gecti, ancak
  onceki uc uyeli kesinti ve kopan aktarimin otomatik devam etmesi acik.
- iOS fiziksel derleme, teslim, ses kalitesi ve arka plan davranisi bu
  Linux oturumunda dogrulanmadi.
- Hesap silme, gercek kurtarma e-postasi, kisisel verili yedegi geri
  yukleme, OS izinlerini geri alma ve tum ag/kilit senaryolari fiziksel
  olarak denenmedi. Bu sinirlar monkey testi ile gizlenmez.
