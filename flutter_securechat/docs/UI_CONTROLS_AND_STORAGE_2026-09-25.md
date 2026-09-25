# Depolama, Sohbet ve Ana Sayfa Duzenlemeleri

## Kullanici Akislari

- Depolama normalde goruntuleme modunda acilir. Gorsel uygulama ici
  goruntuleyicide; diger dosyalar mevcut yerel dosya acma mekanizmasinda acilir.
  Sag ustteki cop simgesi secim modunu acar. Secim kutulari, tumunu sec ve
  alttaki sil dugmesi bu modda gorunur. Silme yine onay ister; iptal secimi
  temizler ve normal goruntulemeye doner.
- Tek gosterimlik, ertelenmis, suresi dolmus, silinmis ve yetkisiz kilitli
  icerik bu yeni acma yoluyla goruntulenemez. Dosya acilmadan once guncel
  kayit ve yerel dosya yolu tekrar kontrol edilir.
- iOS sohbetinde klavye gorunurken ust cubukta klavye kapatma simgesi vardir.
  Mesaj listesini suruklemek veya yazi alaninin disina dokunmak da klavyeyi
  kapatir. Taslak kaybolmaz. Uzun basma menusunun klavye kapatmasi korunur.
- Tepki menusunden ek emoji yazma/klavye secenegi kaldirildi. Hazir emojiler
  kalir; beyaz kalp gercek beyaz kalp karakteri olarak gonderilir. Eski kirmizi
  kalp tepkileri hala okunabilir. Bir kullanici ayni mesaja tek tepki birakir.
- Birebir mesajlarin tepki etiketinde sayi yoktur. Gruplarda sayi korunur.
- Sohbette gecerli sabitlenmis mesaj varken baska bir mesaji sabitleme secenegi
  gizlenir. Veritabani ve gelen sifreli kontrol yolu da bu kurali uygular.
  Yeni sabitlemeden once eskisinin kaldirilmasi gerekir. Grup yoneticisi
  yetkisi korunur; suresi dolmus/silinmis mesaj yeni sabitlemeyi engellemez.
- Ana sayfada bugunku mesajlar HH:mm, eski mesajlar dd.MM.yyyy olarak
  gosterilir. UTC deger once cihaz yerel saatine donusturulur.
- Ana sayfa filtreleri kaydirma olmadan tek satirdadir. Normal yazi boyutunda
  dort etiket 320 pikselde de gorunur. Cok buyuk erisilebilirlik yazisinda
  yazi kucultmek veya ikinci satira gecmek yerine adlari ekran okuyucu ve
  ipucunda korunan dort anlamli simge kullanilir.
- Anket onizlemesi anket simgesi ve yerellestirilmis "Anket" etiketidir;
  soru/secenek JSON'u ana sayfaya veya yeni bildirim ozetine tasinmaz.
  Eski kayitlar da tur bilgisine gore guvenli etiketle gosterilir.
- Gelen aramalar filtresi, kullanicinin son tercihiyle cevapsiz ve
  gelen/mesgul kayitlari dahil tum gelen aramalari gosterir. Cevapsiz
  filtresi bu kayitlari ayrica gostermeye devam eder; durum renkleri korunur.
- Arama kaydina uzun basinca onayla yerel silme yapilabilir. Diger kayitlar
  veya karsi tarafin gecmisi silinmez; acik listeler canli yenilenir.

## iOS Onizleme ve Sinirlar

Dosya URI'leri yerel yola cozulur. Eski iOS uygulama kapsayici yollarindan
yalnizca bilinen ozel medya alt dizini mevcut medya dizinine eslenir.
Rastgele dosya adi aramasi, uzak URI, dizin disina cikis veya sembolik bag
uzerinden ozel medya kokunden cikis kabul edilmez. Gecmis mesajlar yeniden
yazilmaz. Bunlar yerel dosya testleriyle sinanir; fiziksel iPhone sonucu veya
HEIC gibi cihaz codec'lerinin dogrulamasi yerine gecmez.

Tek sabitleme kuralinin yerel eszamanlilik korumasi vardir. Ancak iki bagimsiz
cihazin tam ayni anda farkli mesajlari sabitlemesi durumunda mevcut protokolde
ortak siralama bulunmadigi icin hangi mesajin kazandigi cihazlarda farkli
olabilir. Bu calismada wire protokolu veya sunucu degistirilmedi. Kismi ya da
sonucu belirsiz gonderimde ikinci bir pin gonderilmesini engellemek icin yerel
sabitleme yeri korunur; kullanici acikca kaldirabilir.

## Dogrulama

Son sabit kaynakla `flutter test --no-pub --concurrency=4`: **1202 test gecti**.
Sonraki kullanici tercihiyle Gelen filtresine cevapsizlar yeniden dahil edildi;
filtre ve arama kaydi silme testleri tekrar calistirildi: **11 test gecti**.
Ilk turda buyuk yazi boyutundaki tarih sutununda gorulen tasma giderildi;
tarih sutunu genisligi sinirlandi, yazi boyutu kucultulmedi. Yeni medya
testinin eksik bekleme API'si de tamamlandi ve tam test paketi tekrar kosuldu.
1.0.107 (2107) iki Android cihaza veri silmeden kuruldu. iOS cihaz dogrulamasi
yapilmadi. Kilitli ekran medya teslim ayrintilari
`BACKGROUND_MEDIA_DELIVERY_2026-09-25.md` dosyasindadir.

- Sohbet kontrolleri: beyaz kalp secimi, birebir/grup sayaclari, pin menusunun
  durumu, iOS temali klavye kapatma ve taslak koruma.
- Ana sayfa: 320/390/768 piksel, normal ve iki kat yazi, TR/EN/AR, tek satir
  filtre, secim islemleri, tam tarih ve anket ozetleri.
- Arama: silme onayi/iptali, hata/yeniden deneme, kalicilik, canli liste,
  filtre ve grup geri arama rotalari.
- Sabitleme: yerel paralel islem, iki veritabani ornegi, gelen kontrol,
  yetkisiz grup uyesi, acikca kaldirma, gonderim hatalari ve beyaz kalbin
  sifreli kontrol mesajinda degismeden korunmasi.
- Depolama: goruntuleme/secim ayrimi, medya korumalari, dosya yolu
  cozumleme, kapsayici degisimi, silme ve paylasilan dosya korumasi.

Fiziksel iOS derlemesi/cihaz testi bu Linux ortaminda yapilmadi. Bu turdaki
`flutter analyze --no-pub` kod uyarisi raporlamadi fakat analiz sunucusu
`Too many open files` nedeniyle basarili cikmadi; temiz analiz sayilmadi.

## Son Paket

Gelen filtresinde cevapsizlari da gosteren 1.0.108 (2108), R5GL2452S4A ve
R5GL2452SJK cihazlarina `adb install -r` ile kuruldu; iki cihazda paket surumu
sorgulanarak dogrulandi. Hesap/sohbet verileri silinmedi.

- APK: `build/app/outputs/flutter-apk/elcim-1.0.108-arm32-arm64-signed.apk`
- ARM32 + ARM64 release derlemesi, mevcut yerel Android Debug test imzasi.
- SHA-256: `919c1298e95661ab098ed98d454095334b701bef1401c329b296508d14bb7718`
