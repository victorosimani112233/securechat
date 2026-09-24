# 1.0.94 arayuz ve gizlilik duzenlemeleri

## Degisiklikler

- Aramalar: tumu, cevapsiz, gelen, giden, goruntulu ve grup filtreleri.
  Yeni arama kayitlari grup kimligini saklar; gruba geri arama dogru grubu acar.
  Eski gelen grup kayitlarinda grup kimligi yoksa tahminle gruplandirma yapilmaz.
- Ayarlarda Depolama adi ve arama listesindekiyle ayni sohbet yuzeyleri.
- Arama izinleri verilmis olsa da sistem ayarlari acilir. Android pil izni
  zaten verilmisse izin isteme penceresi yerine pil optimizasyon listesi acilir.
  iOS'ta uygulama izinleri yalniz sistem Ayarlar uygulamasindan kaldirilabilir.
- Yeni grup: once ad, sonra arama/coklu secim/avatarli secim rozetleri ve onay.
  Yeni sohbet basligi ayri; ana Rehber basligi ve normal rehber akisi korunur.
- Toplu mesaj: once mesaj diyalogu, sonra ayni alici secici. Kismi basarisizlikta
  yeniden deneme, onceki denemede basarili olan alicilara tekrar gondermez.
- Planli mesajlarda alici arama ve coklu secim. Iptal, onceki taslagi degistirmez.
  Rehberdeki kayitli uygulama kullanicilari icin sohbet ancak onayda olusturulur.
- Okundu paylasimi kapaliyken mesaj yerelde okunur, okunmamis sayaci temizlenir;
  READ kontrolu gonderilmez ve alinan READ yalniz teslim bilgisi sayilir.
  Eski okundu isaretleri de arayuzde teslim isareti olarak gosterilir.
  Tekrar acmak, kapaliyken okunan mesajlari geriye donuk paylasmaz.
- Cevrimici bilgisi son gorulmeden bagimsiz kapatilabilir. Soket kapanmaz;
  mevcut presence protokolunde yayinlanan online degeri false olur. Bu tercih
  sunucudan IP/baglanti metaverisini gizleyen bir anonimlik sistemi degildir.
- Uzun mesajlar sekiz satirlik onizleme ile acilip kapanir; arama sonucunda
  eslesen metin gizlenmez. Gelen/giden balonlarda ic bosluk artirildi.
- Fotograf ve video onizlemesi en-boy oranini korur, kirpilmaz. Dosya yeniden
  sikistirilmaz; yalnizca ekrandaki boyut sinirlanir.
- Mesaj cekmecesi sabit ekran yuksekligi yerine icerigine gore boyutlanir.
  Mevcut klavye unfocus davranisi korunur; alttaki sil eylemi erisilebilir kalir.
- Bes hizli tepki ve sistem klavyesinden emoji girme alani. Tek Unicode
  grapheme kabul edilir (ten rengi, aile, bayrak dahil); normal metin reddedilir.
  Veritabani, gonderim ve alma katmanlari kisi basina tek tepki tutar.
  Farkli emoji eskisini degistirir; aynisini secmek tepkiyi kaldirir.
  Eski uygulamalar yeni, onceden izin listesinde olmayan emojileri gormeyebilir.
- Iletimde uygun olmayan mesajlarin checkbox'i yoktur. Metin veya medya satirina
  dokunmak secimi degistirir; secim sirasinda medya/anket acilmaz.
- Kopyalandi ve medya/ses sifreleniyor/basarili bildirimleri kaldirildi;
  kopyalamada hafif titresim, gonderimde mevcut mesaj durumlari korunur.
  Hata bildirimleri kaldirilmadi.
- Mesaj bilgisinde grup UUID yerine mevcut kisi kimligi/izinli telefon ya da
  Bilinmeyen Uye kullanilir. Yeni telefon ifsasi veya sunucu sorgusu eklenmedi.
- Ana sohbet menusunde sohbetlere gore kategorize yildizli mesajlar.
  Kilitli sohbetlerin icerigi listede gosterilmez; acmak mevcut sohbet kilidi
  dogrulamasindan gecer. Secilen yildizli mesaja sohbet icinde gidilir.

## Tek gosterimlik medya

Alinan tek gosterimlik icerik acilirken atomik olarak tuketilir. Goruntuleyici
kapaninca yonetilen medya dosyasi, kayittaki dosya yolu/aciklama ve gorsel
onbellegi temizlenir. Islem yarida kesilirse acilista ve servis kapanisinda
temizlik yeniden denenir. Kaydin tuketildi bilgisi yeniden acilmayi onlemek
icin tutulur. Normal ve giden medyalar bu temizlikle silinmez.

Bu, fiziksel flash bellekten guvenli silme veya isletim sistemi RAM'ini
sifirlama garantisi degildir. Harici dosya goruntuleyicisinin olusturdugu
kopyalar uygulamanin denetimi disindadir; dis goruntuleme bittiginde uygulamaya
ait dosya temizlenir. Gonderenin galerideki asil dosyasina dokunulmaz.

## Dogrulama ve sinirlar

Arama filtreleri, yerel grup kaydi, tek gosterimlik temizlik, lifecycle,
karsilikli okundu gizliligi, emoji kurali, coklu secim, iletme ve uzun metin
icin otomatik testler eklendi. Secici 320/390/768 genisliklerde ve buyuk
yaziyla ekran goruntuleri uzerinden incelendi. iOS readiness denetimi gecti;
bu Linux ortaminda Xcode derlemesi veya fiziksel iPhone testi yapilmadi.

Genel test turu: 903 test gecti. Son medya duzenlemesinden sonra ek odak
turu: 27 test gecti (dikey/yatay/kare video oranlari dahil). Genel statik
analiz: 318 Dart dosyasinda sifir tani. Onceki yogun eszamanli calistirmada
gorulen SQLite kilit bekleme hatasi, derlemeyle cakismayan genel test
turunda tekrarlanmadi; veritabani zaman asimi ayari degistirilmedi.

Bu paket sunucu kodunu degistirmez. Dosya basi 100 MiB istemci destegi ile
sunucunun cevrimdisi dosya kuyrugu ayni sey degildir: mevcut sunucu kaynaginda
cevrimdisi dosya kuyrugu alici basina 10 MiB'dir. Bildirilen 20,4 MB Android
grup aktarimi hatasinin kesin nedeni henuz canli testle dogrulanmadi.

## Android cihaz guncellemesi

24 Eylul 2026: 1.0.94 (2094), bagli Samsung SM-S731B cihazina veri silmeden
`adb install -r` ile kuruldu. Paket armeabi-v7a ve arm64-v8a icerir; imza,
16 KiB ZIP hizalamasi ve cihazdaki surum dogrulandi. Ilk acilista uygulama
calisiyor; incelenen acilis logunda fatal hata yok ve push kaydi tamamlandi.
Bu kontrol, 20,4 MB dosyanin uctan uca teslim edildigi anlamina gelmez.

Yerel test cihaziyla ayni Android debug sertifikasi kullanildi; bu APK bir
magaza yayin paketi degildir. APK dosyasi:
`build/app/outputs/flutter-apk/elcim-1.0.94-arm32-arm64-signed.apk`.

Derlemede testlerden kalan integration_test eklenti kaydi nedeniyle ilk
`--no-pub` denemeleri basarisiz oldu. Flutter SDK kaynaginda bu secenegin
platform eklenti kaydini yenilemeyi atladigi dogrulandi. Normal release
derlemesi kaydi yeniden uretti ve basarili oldu; uretilen Java dosyasina
elle yama veya uygulama bagimliliklarina gecici ekleme yapilmadi.
