# Depolama Onizlemeleri ve Arama Renkleri

## Degisiklikler

- Depolama sohbet ayrintisi, dosya adi listesinden secilebilir onizleme
  izgara gorunumune gecti. Foto/video orani korunur, kirpma yapilmaz.
- Belgeler ve ses dosyalari tur simgesi ve uzantiyla ayrilir; belge
  sayfalari veya ses icerigi cozumlenmez. Ad, disk boyutu ve tarih korunur.
- Kategori filtresi, tumunu sec, secili dosyalari onayla sil ve geri
  donuste depolama ozetini yenileme korunur. Asagi cekerek yenileme eklendi.
- Tek gosterimlik ve ertelenmis medya cozumlenmez. Eksik/bozuk dosyalar
  tur simgesiyle gosterilir ve temizlenebilir. Tek gosterimlik dosyanin adi
  metne veya erisilebilirlik etiketine konmaz.
- Foto onizlemesi en fazla 384 piksel olacak sekilde cozumlenir. Global
  ImageCache'e veya diske yeni onizleme yazilmaz; ekran kapandiginda,
  dosya silindiginde veya suresi doldugunda sahip olunan kare birakilir.
- Canli mesaj degisiklikleri, silinen/korumali hale gelen/suresi kisalan
  icerigin eski onizlemesini kapatir. Mesaj gozlemi sohbet yetkilendirmesi
  sonrasinda baslar; uygulama arka plana gittiginde iptal edilir.
- Arama kaydi zemini: giden soluk yesil, gelen soluk mavi, cevapsiz
  soluk kirmizi. Gelen/mesgul kaydi da kirmizidir. Ilk renkli kenarlik
  tasarimi yerine normal yuzeye acik temada %8, koyu temada %10 renk
  karistirilir. Kenarlik notr kalir; yon simgesi de yumusatilir.
  Acik/koyu temaya uygun tonlar kullanilir; anlam yalniz renge bagli
  birakilmaz. Diger AzureSurface kullanimlarinin varsayilani degismez.

## Dogrulama

- Depolama servisi/ekrani, arama filtreleri, video onizlemesi, tek
  gosterim gizliligi ve paylasilan icerik testleri: **91/91 gecti**.
- 390 piksel acik/koyu tema ve 320 piksel buyuk yazi test ekran
  goruntuleri incelendi. Test gorselleri sentetik yerel bitmaplerdir;
  bu kayit fiziksel cihaz ekran goruntusu oldugu iddiasinda degildir.
- Son `flutter analyze --no-pub`, kod uyarisi kalmamasina ragmen Linux
  dosya izleyici sinirinda `Too many open files` ile basarisiz cikti.
  Tam statik analiz basarili sayilmadi.
- Sunucu, wire protokolu, sifreleme veya imza anahtari degistirilmedi.
  iOS fiziksel cihaz/derleme dogrulamasi bu ortamda yapilmadi.

## APK

Soluk arka plan duzeltmesi icin arama/depolama ekranlarinda **45/45 test
gecti**. Metin kontrasti en az 4.5:1, yon simgesi kontrasti en az 3:1
olarak test edildi. 320 piksel acik ve 390 piksel koyu tema widget ekran
goruntuleri incelendi. Bu son duzeltme icin henuz yeni APK uretilmedi.

Asagidaki APK kaydi onceki renkli kenarlik tasarimina aittir:

**1.0.105 (2105)** ARM32+ARM64 release APK iki bagli Android telefona
`adb install -r` ile verileri silmeden kuruldu. Her iki cihazdaki surum
dogrulandi ve uygulama acildi; crash tamponlarinda hata yoktu.
Imza onceki kurulumlarla ayni Android Debug test anahtaridir.

Dosya: `build/app/outputs/flutter-apk/elcim-1.0.105-arm32-arm64-signed.apk`

SHA-256: `ba08c905ec47eb0357257b3c63c4bd72ff055359641ce76d4f4f5e0bdf816ef6`
