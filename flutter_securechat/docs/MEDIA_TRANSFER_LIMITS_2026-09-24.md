# Dosya aktarimi duzeltmeleri

## Degisenler

- Sunucunun kullanici basina 5 MiB/dakika dosya kotasi kaldirildi.
  Kaynak gecmisi: `4d3472d`, 2026-08-18, Git yazari `root`.
  Bu yazar kaydi arkasindaki kisiyi veya araci kanitlamaz.
- Tek dosya ust siniri 100 MiB (104857600 byte). Tek WebSocket paketi
  256 KiB ve genel 50 mesaj/saniye saldiri korumasi aynen korunuyor.
- Gercek Signal sifrelemesinde eski grup dosya parcasi 415165 byte
  olabiliyordu. Grup parcalari 48 KiB oldu; sifreli aciklama icin de
  yer ayrildi. Birebir aktarim 128 KiB parca kullanmaya devam ediyor.
- Grup aktarim surumu `flutter-file-v5-group`. Yeni istemci eski
  v2/v3/v4 dosyalarini almaya devam eder; eski istemci yeni v5 grup
  dosyasini alamaz. Android ve iOS istemcileri birlikte guncellenmeli.
- Dosya parcalari ayni sokette en az 50 ms arayla gonderiliyor.
  Bu, MB/dakika kotasi degildir; genel paket korumasinin toplu dosya
  aktarimini kesmesini onler. Mesaj ve arama sinyalleri bu kuyrugu beklemez.
- Dosya okuyucu akis kaynagini gerektikce okuyor. Eski okuyucu agi
  beklemeden tum dosyayi buyuk bir integer listesine aliyordu.
- Harici dosya seciciden donuste grup kontrolu, soket baglantisini
  dogrulamadan gonderilmiyor. Kalici gonderim kuyrugu kullanan yol degismedi.
- Sifreli dosya adi, MIME turu, aciklama ve tek gosterim bilgisi
  sunucuya acik olarak verilmez. Sifreleme kaldirilmadi veya zayiflatilmadi.

## Dagitim

Yeni sunucu artefakti `server_hardened/signaling-server/build/libs/signaling-server-all.jar`.
Build: `403b85c-dirty-media-transfer-20260924`, tarih `2026-09-24T13:45:40Z`.
SHA-256: `e96a71b3c8a47f040779ab47928417006e2552ccb8e78c589c1910f838f539d6`.
`server_hardened/tools/deploy_signaling_group_calls.sh` bu hash icin guncellendi.
Yeni veritabani migrasyonu yok. Canli sunucu bu calismada degistirilmedi.

Android APK: `build/app/outputs/flutter-apk/elcim-1.0.91-arm32-arm64-signed.apk`.
Surum 1.0.91 / 2091, ARM32 ve ARM64. Mevcut test imzasi ile imzali;
magaza dagitim anahtari degildir. Imza ve 16 KiB hizalama dogrulandi.
SHA-256: `6d6a17794821d10aa5e69c29f20939eeb6f7afd520d50c4421e5a8defbe3d230`.
Bagli SM-S731B telefona veriler silinmeden kuruldu; surum ve acilis dogrulandi.

## Dogrulama

- Son tam Flutter test kosusu: 879/879 basarili (100 MiB testleri dahil).
- 59 odakli Flutter testi gecti: gercek Signal ile 600 KiB birebir/grup,
  normal/tek gosterim sifreleme ve alicida birlestirme; 100 MiB birebir/grup
  gonderim ve cerceve butcesi; 100 MiB ustunu reddetme; kaynak akisinda
  geri basinc; soket paket hizi; harici seciciden donuste yeniden baglanma.
- 100 MiB testleri kaynak akisini sifreleyip gonderilen cerceveleri dogrular;
  fiziksel ag veya alicida 100 MiB birlestirme testi degildir.
- 35 sunucu testi gecti, atlanan yok. Gercek Redis/PostgreSQL kullanan
  yonlendirme testinde 6 MiB aktarimin 48 parcasi eksiksiz kuyruga alindi.
- Dart tek seferlik analiz: 311 dosya, sifir tani.
- Gizlilik kontrolunun eski parca degiskenini bekleyen kaynak testi yeni
  degisken adina uyarlandi; 12 gizlilik testi yeniden gecti.

## Acik noktalar

- Sunucu kapali alici icin dosyalari hala kucuk, gecici RAM kuyrugunda
  tutuyor (10 MiB). Bu degisiklik 100 MiB cevrimdisi teslim garantisi degildir.
- Sokete yazma basarisi alicinin dosyayi kaydettigi anlamina gelmez;
  dosya aktariminda uctan uca teslim onayi eksigi devam ediyor.
- Galeriden giden ancak dosya seciciden gitmeyen 600 KB dosyanin cihazdaki
  tam nedeni henuz kanitlanmadi. Kota ve grup paket hatasi kanitlandi.
- iOS derleme ve iki fiziksel cihaz arasinda 100 MiB testi burada yapilmadi.
