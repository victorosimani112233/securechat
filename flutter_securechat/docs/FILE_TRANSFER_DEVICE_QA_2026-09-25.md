# Iki Android ile dosya aktarimi incelemesi

## Dogrulanan hatalar

1. Otomatik indirme tercihi bir dosyaya izin vermeyince istemci, agdan
   zaten alinmis dosyanin tek kopyasini siliyordu. Birebir ve grupta 600 KiB
   dosya karti geldi; gruptaki dosya acilinca `Medya dosyasi bulunamadi`
   goruldu. Bu bir sunucu desifre sorunu degil, istemci veri kaybiydi.
2. 20,4 MiB dosya denemesinde gonderici Android `Belirlediginiz sinira
   ulastiginiz icin mobil veri kullanimi duraklatildi` uyarisi verdi.
   Alicinin 436 parcadan 256 parcayi tamamladigi, 256 indeksli sonraki
   parcayi aldigi goruldu; akis burada durdu. Kota kullanici adina kaldirilmadi.
3. Gonderici dosyanin yerel koruma kopyasinin adini zarf icine yaziyordu;
   alicida asil dosya adina dahili mesaj kimligi ekleniyordu.

## Duzeltmeler

- Alinmis dosya otomatik indirme tercihi yuzunden silinmez. Tercih izin
  vermiyorsa `isMediaPreviewDeferred` saklanir; sohbet ve ortak medya
  ekranlari resim/video onizlemesini otomatik yuklemez. Kullanici acinca
  guncel kayit atomik kontrol edilir ve onizleme etkinlesir.
- Eski kayitlar yeni alan olmadan yuklenebilir. Bayrak yeniden baslatmada
  korunur. Sureli/silinmis/tuketilmis tek gosterimlik kayit acilmaz;
  sohbet kilidi ve tek gosterimlik tuketim kontrolleri korunur.
- Sesli mesajlarin mevcut dogrudan acilma davranisi korunur.
- Aktarim zarfinda orijinal dosya adi kullanilir; yerel koruma yolu degismez.
- Yalniz `SECURECHAT_LOCAL_DIAGNOSTICS=true` derlemelerinde SC-FILE parca
  sayaci yazilir. Icerik, anahtar, telefon, kullanici kimligi veya dosya adi
  yazilmaz. Hatayi yutan alici yolu mevcut guvenli raporlayiciya baglandi.

Onemli sinir: mevcut protokol parcalari once gonderir, tercih kontrolunu
alindiktan sonra yapar. Bu duzeltme bant genisligi tasarrufu saglayan gercek
bir on-indirme onay protokolu DEGILDIR. Tercihlerin agdan almayi da durdurmasi
icin teklif/kabul ve yeniden gonderim akisinin ayrica uygulanmasi gerekir.
Onceden silinmis dosyalar bu yama ile geri gelmez; yeniden gonderilmelidir.

## Canli bulgular

- Iki Samsung SM-S731B ADB'de goruldu; uygulama verileri silinmeden once
  1.0.95, sonra parca teshisi icin 1.0.96 kullanildi.
- 600 KiB birebir aktarim: alicida kart ve gondericide Okundu goruldu.
- 600 KiB grup aktarimi: alicida kart ve gondericide Okundu goruldu;
  dosyanin eksik oldugu goruntuleyicide dogrulandi.
- 20,4 MiB grup aktarimi: gonderici 46 saniyede 436 parcayi sokete yazdi;
  alici daha yavas almaya devam etti. Sokete yazmanin tamamlanmasi, son
  alicinin dosyayi aldiginin kaniti degildir. Son deneme cihaz veri kotasinda
  durdu; iki cihazda saglam agla tekrari gereklidir.
- Ag izni olmayan gecici bir Android SHA-256 kontrol araci hazirlandi.
  Yalniz uygulamanin Paylas eylemiyle izin verdigi QA dosyalarini okuyabilir;
  uygulamanin ozel verilerine dogrudan erismez. Silinmis/yarim dosyalarda
  cihazlar arasi SHA-256 eslesmesi yapildi iddia edilmez.

## Sunucu

SSH uzerinden salt okunur kontrol yapildi; servis durdurulmadi ve JAR degismedi.
Calisan surum `403b85c-dirty-media-transfer-20260924`, derleme tarihi
`2026-09-24T13:45:40Z`, migrasyon hedefi V23. Diskteki JAR SHA-256:
`e96a71b3c8a47f040779ab47928417006e2552ccb8e78c589c1910f838f539d6`.

Mesaj yonlendirme sayaclari artiyordu. `queue_full` sayaci 0 idi; bu sayac
guvenilir mesaj kuyruguna aittir, gecici dosya kuyrugunda hic parca
silinmedigini kanitlamaz. Cevrimdisi dosya kuyrugunun 10 MiB siniri ve
parca ACK/yeniden gonderim eksigi onceki rapordaki gibi acik risklerdir.

## Otomatik kontroller

42 odakli test gecti: ertelenmis dosyanin korunmasi, yeniden baslatma,
manuel acma, sahte ses metaverisi, tek gosterimlik tuketim, grup uyeligi
ve sohbet arayuzu dahil. Degisen 10 Dart giris noktasinda statik analiz:
0 tani. Fiziksel iki yonlu, arka plan ve kesinti sonrasi teslim matrisi
tamamlandi olarak isaretlenmedi.

## Ag acildiktan sonraki tekrarlar

Kullanici mobil interneti tekrar acti. 1.0.97 (2097), ardindan yalniz
yerel parca teshisi ayrintisi eklenen 1.0.98 (2098), iki telefona da
`adb install -r` ile kuruldu. Hesap veya uygulama verisi silinmedi.

1.0.97'de fiziksel cihazda dosya acilip, Android Paylas eylemiyle ag izni
olmayan QA aracina verilerek su kontroller yapildi:

| Senaryo | Sonuc |
| --- | --- |
| A -> B, grup, 614400 bayt | Acildi; SHA-256 eslesti |
| B -> A, grup, 614400 bayt | Acildi; SHA-256 eslesti |
| A -> B, birebir, 21390950 bayt | 164/164 parca; acildi; SHA-256 eslesti |
| B -> A, birebir, 614400 bayt | Acildi; SHA-256 eslesti |
| A -> B, grup, 21390950 bayt, paylasim ekranina gecisli | Son parca sokette goruldu; tamamlanma yok |
| A -> B, grup, 21390950 bayt, iki uygulama on planda (1.0.98) | 436/436 parca; acildi; SHA-256 eslesti |

Buyuk birebir dosyada ilk parca 09:55:37, tamamlanma 09:57:14 (telefon
yerel saati). Grup denemesi sirasinda alicida Android paylasim ekrani da
acildi. 1.0.98 tekrarinda iki uygulama on planda tutuldu: ilk parca
10:01:38, tamamlanma 10:03:50. Ayni buyuk dosya bu kez eksiksiz acildi.
Bu sonuc onceki kaybin yasam dongusu gecisiyle ilgili olmasini destekler;
tek basina hangi parcanin hangi noktada kayboldugunu kanitlamaz.

Sentetik dosyalarin SHA-256 degerleri:

- 614400 bayt: `00a21b1bd4f9121d9a1de497a29315db887c07f3935613281d74724ad47cfb5c`
- 21390950 bayt: `4875e70520577a238cf6c784c4802c1e7fd44cf4ef52d6a7dc096d89f1a540e8`

Tum Flutter testleri yeniden calistirildi: **938 test gecti**. Eski
`network_monitor_module_test` ve `voice_note_module_test` beklentileri
artik dosyanin silinmesini degil, baytlarin korunmasini ve onizlemenin
ertelenmesini dogruluyor. 1.0.98 ek teshisinde son parca geldiginde eksik
parca indekslerinin ilk sekizi raporlanir; icerik veya hesap kimligi yoktur.

## Aktif aktarim sirasinda arka plana gecis

Kodda arama disindaki tum arka plan gecislerinde WebSocket'in kapatildigi
dogrulandi. Paylasim/picker gibi harici bir Activity de bu gecisi tetikleyebilir.
Arka plan runtime'inda dosya alicisi bulunmadigi icin kesilen dosya aktariminin
oradan tamamlanacagi varsayilamaz.

1.0.99 duzeltmesi:

- `FileTransferManager.activity` eszamanli gonderimleri ve kismi alimlari
  ayri sayar. Parcalar arasinda alim aktif kalir; eksik son parca icin
  etkinlik en son islenen parcadan 10 dakika sonra sonlanir.
- Yasam dongusu aktif arama VEYA aktif dosya aktarimi varken soketi ve ag
  takibini korur. Arka plana gecince cevrimici bilgisi yine kapatilir.
- Bir aktarimin bitmesi diger aktif aktarimin baglantisini kapatmaz.
  Tamamlama, reddetme, hata ve dispose etkinligi serbest birakir.
- Gonderici etkinligi yerel gonderim suresini kapsar; alicinin tum baytlari
  aldigina iliskin yeni bir ACK protokolu eklenmedi.

Sinirlar: bu degisiklik Android/iOS'un sureci oldurmesini veya askiya almasini
engellemez. Uygulama tamamen kapaliyken baslatilan buyuk dosyalarin teslimi,
kopma sonrasi eksik parca istegi ve kaldigi yerden devam garanti edilmez.
Sunucuya daha fazla ciphertext depolatilmadi veya kuyruk sinirlari
kaldirilmadi. Gercek teslim guvencesi icin ayri bir istemci ACK/yeniden
gonderim protokolu gerekir.

Yeni kapsam: 5 dosya-etkinligi testi ve 11 yasam-dongusu regresyon testi.
Yasam-dongusu dosyasindaki toplam 19 test gecti. Son degisen 5 Dart giris
noktasinda statik analiz: 0 tani.

### 1.0.99 fiziksel sonuc

A = seri numarasi S4A ile biten, B = SJK ile biten Samsung.
B -> A yonunde ayni 21390950 baytlik dosya gruba yeniden gonderildi.
Ilk parca 10:11:19'da alindi. Yaklasik 32 parcadan sonra A'da HOME tusuna
basildi; Android'in on plandaki Activity kaydi LauncherActivity olarak
dogrulandi. Uygulama arka plandayken 10:14:19'da 436/436 parca islendi,
10:14:20'de dosya tamamlandi. Sonra uygulamaya donulup dosya acildi.
10:14:56'daki QA hash sonucu kaynakla ayni:
`4875e70520577a238cf6c784c4802c1e7fd44cf4ef52d6a7dc096d89f1a540e8`.

Aktarim bittikten sonra A'daki uygulama durdurulup yeniden acildi. Ayni
dosya yeniden acildi; 10:16:25'te SHA-256 tekrar eslesti. Yeniden baslatmada
alinan dosyanin yolu ve icerigi korundu.

Bu, baslamis bir alimin uygulama arka plana gectiginde surdugunu kanitlar;
zorla durdurulmus uygulamada yeni aktarim veya ag kesintisinden devam testi
degildir. Iki telefonda da versionName 1.0.99, versionCode 2099 dogrulandi.

### Son test taramasi ve acik risk

Son kodla tam tarama: **953 gecti, 1 basarisiz** (954 toplam).
`cross_runtime_database_test.dart` icindeki bagimsiz isolate yazma yarisi
bir kez `SqliteException(5): database is locked` verdi. Ayni dosya tek
basina tekrar calistirilinca **12/12 gecti**. Hata gizlenmedi veya test
atlatilmadi; tam tarama icin 954/954 basari iddia edilmiyor.

Bu test medya/yasam-dongusu siniflarini olusturmuyor. Degismeyen SQLite
islem yolunda 5 saniyelik kilit bekleme siniri var; yeniden uretim ve
kilit zamanlamasi incelemesi acik takip maddesidir. Aralikli olmasi
zararsiz oldugunu kanitlamaz. Dosya ve yasam-dongusu odakli testleri gecti.

Kurulu APK: `build/app/outputs/flutter-apk/elcim-1.0.99-arm32-arm64-signed.apk`.
ARM32 ve ARM64 birlikte; mevcut test imzasi korunarak uzerine kuruldu.
APK SHA-256: `ea0496028a7e430cba743e04cca614dca4b1535adb21e20f15f9bdd4128dea2b`.

Gecici `com.securechat.qa.filecheck` araci iki telefondan da kaldirildi.
Test icin degistirilen sarjda ekrani acik tutma degerleri onceki hallerine
dondu (A: 0, B: 15). Sentetik Download dosyalari tekrar deneme icin kaldi.
Kisisel mesajlar veya uygulama verileri silinmedi. Commit/push yapilmadi.
