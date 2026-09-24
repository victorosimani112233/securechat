# Arama devamliligi ve yakinlik sensoru

## Duzeltilenler

- Uygulama ekran kilidiyle arka plana gectiginde aktif arama olsa da signaling
  baglantisini kapatiyordu. Sunucu bunu grup aramasindan ayrilma olarak isliyordu.
  Artik arama bitene kadar baglanti ve ag degisimi takibi korunur; arama bitince
  arka planda normal kapatma davranisina donulur. Gorunurluk bilgisi yine
  cevrimdisi olarak gonderilir; sesli arama kullaniciyi sohbette aktif gostermez.
- Sifreli medya anahtari ayri gelen-mesaj is hattinda uygulanirken ayrilan
  katilimcinin cryptor/medya baglantisi temizlenebiliyordu. Anahtar kurulumu ve
  grup uyeligi degisimleri artik ayni sirada islenir. Sifreleme hatasinda
  sifresiz devam edilmez.
- Android: aktif/aranan sesli cagrida ses ahizedeyken sistemin yakinlik
  sensoru ekran kontrolu acilir. Hoparlor, kablolu/Bluetooth kulaklik, goruntulu
  arama ve kapanista birakilir. Desteklenmeyen cihazlarda etkinlestirilmez.
  `WAKE_LOCK` normal izni manifestte acikca tanimlandi; yeni bir tehlikeli
  izin veya kullaniciya izin istemi eklenmedi.
- iOS: CallKit ses oturumu aktifken ve ses ahizedeyken yakinlik izlemesi
  etkinlestirilir. Ses yonlendirmesi degisiminde yeniden degerlendirilir;
  arama sonu, oturum devre disi kalmasi ve CallKit reset durumunda kapatilir.

## Dogrulama ve sinirlar

- Flutter: 869 test gecti. Aramayi baslatan/normal uyenin ayrilmasi, erken
  gelen yeni anahtar, sesli/goruntulu yeniden katilim, medya durum olayi
  olmadan acik kalan cagri, ekran kilidinde baglanti korunmasi ve arka planda
  ag degisimi kapsaniyor.
- Dart: 310 dosyada sifir analiz bulgusu. iOS readiness: PASS.
- Android yerel derlemesi ve iki yakinlik politikasi birim testi gecti;
  iOS icin RunnerTests eklendi. Fiziksel sensor davranisi cihaz uzerinde
  ayrica denenmeli.
- Bu Linux ortaminda Xcode/iPhone testleri calistirilamadi.
- Kullanici denemesindeki sessizlik sonrasi kapanisin kesin nedeni cihaz
  logu olmadan dogrulanmadi. Konusma ses seviyesine gore cagriyi kapatan
  bir uygulama kurali bulunmadi; ekran kilidinde baglanti kapatma somut bir
  kusurdu.
- Sonradan katilan Android kullanicisinin dusuk/kesik sesi henuz
  dogrulanmadi veya giderildi olarak kabul edilmiyor. Mikrofon seviyesi,
  ses rotasi ve RTP durumu fiziksel testte incelenmeli; ses kazanci veya
  sifreleme korumasi tahminen degistirilmedi.
- Bu degisiklikler istemci tarafindadir; bu turda sunucu veya JAR degismedi.

## Android paketi

- Surum: 1.0.90 / 2090, ARM32 + ARM64; onceki test imzasi korundu.
- Dosya: `build/app/outputs/flutter-apk/elcim-1.0.90-arm32-arm64-signed.apk`.
- SHA-256: `a5c24ecc754863c386634891a151b065290c42a0d7cc02fed0d957c0f73ac9f3`.
- Release derlemesi, v2/v3 imza ve 16 KB ZIP hizalama dogrulandi.
- Bagli SM-S731B telefona veri silmeden kuruldu ve paket surumu dogrulandi.
- Sonradan alinan cihaz logunda `accept-group-call TimeoutException` goruldu.
  Bu medya anahtari bekleme yolundaki hatayla uyumlu; dusuk ses seviyesinin
  tek basina kaniti degildir. Yeni surumle canli test halen gereklidir.

## Platform kaynaklari

- [Android PowerManager](https://developer.android.com/reference/android/os/PowerManager)
- [iOS yakinlik izlemesi](https://developer.apple.com/documentation/uikit/uidevice/isproximitymonitoringenabled)
- [iOS ses rotasi degisimi](https://developer.apple.com/documentation/avfaudio/avaudiosession/routechangenotification)
