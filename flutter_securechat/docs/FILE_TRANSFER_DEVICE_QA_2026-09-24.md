# Dosya aktarimi ve mesaj bosluklari: 1.0.95

## Yapilan degisiklikler

- Gelen mesaj balonunda baslangic/ust/bitis/alt bosluk 12/8/12/6 oldu.
  Giden balonun 16/10/14/8 boslugu korundu. Kisa metinler dar kalir;
  uzun metin, buyuk yazi ve RTL duzeni icin regresyon testleri eklendi.
- FileTransferManager alici tarafinda cozme veya disk hatalarini sessizce
  yutuyordu. Hatalar artik mevcut guvenli raporlayiciya tip ve stack ile
  iletilir. Teshis derlemesinin konsol kaydi dosya icerigi, anahtar,
  telefon, UUID veya ham exception mesaji yazmaz. Gonderim exception'lari
  da raporlanir. Raporlayici hata verse bile aktarim temizligi devam eder.
- Gercek Signal/X3DH/SenderKey aktarim testlerine 21.390.950 bayt
  (yaklasik 20,4 MiB) birebir ve grup dosyalari eklendi. Her cercevenin
  256 KiB sinirini asmadigi ve alicinin dosyayi byte-byte ayni aldigi
  kontrol edilir. Bu yerel testler canli sunucu teslim kaniti degildir.

## Fiziksel cihaz denemesi

ADB bu oturumda yalnizca bir Samsung SM-S731B gordu. Ikinci cihaz
baglanmasi istendi; iki fiziksel cihazli test matrisi tamamlanamadi.
Mevcut cihaz 1.0.93'ten once 1.0.94'e, sonra 1.0.95 (2095)'e
`adb install -r` ile guncellendi. Uygulama verileri silinmedi.

Kisisel dosyalar yerine iki rastgele test dosyasi olusturuldu:

| Dosya | Bayt | SHA-256 |
| --- | ---: | --- |
| elcim-qa-600kb.bin | 614400 | 00a21b1bd4f9121d9a1de497a29315db887c07f3935613281d74724ad47cfb5c |
| elcim-qa-20_4mib.bin | 21390950 | 4875e70520577a238cf6c784c4802c1e7fd44cf4ef52d6a7dc096d89f1a540e8 |

Dosyalar cihazdaki Download dizinine kopyalanip uygulamanin Dosya secicisi
ve onizleme/onay akisi kullanildi. Birebir denemede iki dosya birlikte secildi.

| Senaryo | Gonderici sonucu | Alici sonucu |
| --- | --- | --- |
| Grup, 600 KiB, 1.0.94 | Gonderildi | Dogrulanamadi |
| Grup, 20,4 MiB, 1.0.95 | Gonderildi | Dogrulanamadi |
| Birebir, 20,4 MiB, 1.0.95 | Gonderildi | Dogrulanamadi |
| Birebir, 600 KiB, 1.0.95 | Gonderildi | Dogrulanamadi |

Gonderici logunda bu denemeler sirasinda aktarim exception'i veya fatal
hata gorulmedi. Gonderildi, istemcinin sokete yazmayi tamamladigi anlamina
gelir; alici dosyasinin olustugunu veya butunlugunu kanitlamaz.
Gercek alicinin on/arka plan durumu ve kurulu surumu denetlenemedi.

## Sunucu kaynak incelemesi

Bu tur sunucu kodu veya canli sunucu degistirilmedi. Kaynakta dogrulanan,
ancak bildirilen hatanin kesin nedeni oldugu canli logla kanitlanmayan riskler:

- Cevrimdisi dosya kuyrugu alici basina 10 MiB ve 1000 kayit ile sinirli.
  Sifreleme/kodlama ek yukunden dolayi ham dosya kapasitesi daha dusuktur.
  Limit asilinca eski parcalar silinir; gonderene eksik parca yaniti gitmez.
- Dosya parcalari icin uctan uca parca ACK/yeniden gonderim protokolu yoktur.
  Soket send basarisi, alici diske yazmadan once baglanti koparsa yeterli degildir.
- Sunucunun hesap basina 50 metin cercevesi/saniye sinirini ACK ve kontrol
  mesajlari da tuketir. Flutter dosya cercevelerini 50 ms aralikla gonderir;
  bu testlerde rate-limit kaynakli kopma gozlenmedi.

Kalici guvenilirlik icin limitleri koruyan ACK/yeniden gonderim mekanizmasi
gerekir; siniri sinirsiz yapmak veya yalniz RAM kuyrugunu buyutmek cozum degildir.

## Kalan cihaz matrisi

- Iki Android acikken her iki yonde birebir/grup 600 KiB ve 20,4 MiB.
- Alinan dosyanin boyut/SHA-256 eslesmesi; belge ve gorsel olarak gonderim.
- Alici arka planda/kapaliyken teslim; baglanti kesilip yeniden kurulmasi.
- Grup uyelerinden biri cevrimdisiyken diger uyenin teslimi.
- Tek gosterimlik medya, aciklama, tekrar gonderim ve dosya seciciden donus.

Dosya aktarimi sorunu cozuldu olarak isaretlenmedi.

## Otomatik dogrulama

- Padding/etkilesim/medya testleri: 48 test gecti.
- Signal protokolu ve dosya limit testleri: 23 test gecti. Bu turdaki
  100 MiB testleri paket boyutu/gonderim testidir; fiziksel cihaz teslimi degildir.
- Degisen Dart giris noktalari ve testlerinde statik analiz: 5 dosya, 0 tani.
- Release APK derlemesi, imza dogrulamasi ve cihazda 2095 surum kontrolu gecti.
- iOS derlemesi veya fiziksel iPhone testi bu tur yapilmadi.
