# Kilitli Ekranda Ses Kaydi Teslimi

## Bulgu

Telefon tamamen kapali degilken, Elcim kapali ve ekran kilitliyken gonderilen
ses kayitlari hem birebir hem grup sohbetinde kaybolabiliyordu.

Arka plan runtime'i Signal metin/kontrol mesajlarini aliyordu fakat
`FileTransferManager` ve `MediaMessageService` baslatmiyordu. Ses kayitlari da
dosya aktarim yolunu kullanir. Arka plan soketine gelen parcalar bu nedenle
uygulama tarafinda islenmiyordu.

Ayrica medya kaydi tamamlandiginda bildirim koordinatorune olay gitmiyordu.
Dosyanin veritabaninda bulunmasi, bildirim olustugunu gostermiyordu.

## Degisiklik

- Arka planda ayni sifreli dosya alma ve medya kaydetme servisleri kullanilir.
- Grup kontrolleri/anahtarlari islenmeden parcalar cozulmez; ozel grup rota
  cozumu korunur. Yeni bir sunucu medya deposu veya acik metin aktarimi yoktur.
- Kalici dosya ve sohbet kaydindan sonra medya bildirim olayi uretilir.
  Sesli mesaj, gorsel ve dosya bildirimleri ayni gizlilik, sessiz sohbet ve
  etkin sohbet bastirma kurallarindan gecer. Tek gosterimlik icerigin adi,
  aciklamasi veya dalga verisi bildirimde kullanilmaz.
- Arka plan kapanisinda alinmis parcalar, medya kaydi ve bildirim isleri
  sirayla tamamlanir. Bekleme etkin aktarimi dikkate alir, sinirsiz degildir.

## Sinir

Bu duzeltme dosyalar icin yeni bir uctan uca ACK/retry protokolu getirmez.
Mevcut sunucu eski dosya kuyrugundaki parcayi sokete yazinca kaldirir;
isletim sisteminin sureci zorla oldurmesi veya kuyruk suresi/kapasitesinin
asilmasi halinde mutlak teslim garantisi yoktur. Metin teslim protokolu ile
dosya teslim protokolu bu noktada ayni degildir. Gecmiste dusmus kayitlarin
otomatik geri gelecegi iddia edilmez; yeniden gonderilmelidir.

Android Ayarlar > Zorla durdur, normal son uygulamalardan kapatma ile ayni
degildir. Telefon tamamen kapaliysa hicbir arka plan kodu calisamaz.

Sunucu kodu ve sunucudaki veriler bu degisiklikte degistirilmedi.

## Dogrulama

Mevcut iki Android cihazin loglari okundu. Gondericide grup ve birebir dosya
gonderimleri, alicida uygulama acikken tamamlanan dosyalar goruldu; sorunlu
birebir denemede alici dosya alma kaydi yoktu. Bu tek basina sunucunun her
adimini kanitlamaz. Yeni otomatik testler arka plan alma, kaydetme, bildirim,
gizlilik ve kapanis sirasini kontrol eder. Fiziksel kilitli ekran/FCM sonucu
ayrica dogrulanmalidir.

17 yeni medya testinin tamami gecti. Bunlar gercek Signal birebir/SenderKey
sifreleme akisiyla ses kaydinin kalici dosyasini, sohbet kaydini, bildirimini,
sessiz/gizli/tek-gosterim modlarini, tekrar teslimi ve anahtar kurulum sirasini
sinir. Kapanirken sifre cozumunun devam ettigi birebir ve grup alimi da
ayri olarak sinandi. Bildirim kapanis yarisi testi de gecti.

Son kaynakla tum Flutter test paketi tekrar calistirildi:
`flutter test --no-pub --concurrency=4` -> **1202 test gecti**.

## Cihaz Paketi

- Surum: 1.0.107 (2107), ARM32 + ARM64 release derlemesi.
- Mevcut kurulumlarla uyumlu yerel Android Debug test anahtariyla imzali;
  magazaya yayin anahtari degildir.
- R5GL2452S4A ve R5GL2452SJK cihazlarina `adb install -r` ile kuruldu.
  Paket surumu iki cihazda da sorgulandi. Uygulama verileri silinmedi.
- APK: `build/app/outputs/flutter-apk/elcim-1.0.107-arm32-arm64-signed.apk`
- SHA-256: `02cd4aae49e9deff6664fd07b93d29092c569f03e9072bd715caa7870bfba3cf`

Kurulum ve ilk acilis sonrasi iki cihazin crash tamponu bostu. Gercek FCM,
kilitli ekran ve bildirim gorunurlugu icin yeniden ses kaydi gonderme denemesi
yapildi; otomatik test sonucu fiziksel teslim dogrulamasi olarak sunulmaz.

## Fiziksel Grup Denemesi

25 Eylul 2026, cihaz yerel saati:

- Gonderici R5GL2452SJK: 17:21:28.511, `tx-progress group=true`, 1 parca.
- Alici R5GL2452S4A: 17:21:29.529, Android FCM receiver icin yeni uygulama
  sureci baslatti; 17:21:29.666 arka plan Firebase servisi basladi.
- 17:21:30.322: `rx-complete bytes=27442 group=true`.
- 17:21:30.332: mesaj bildirimi `notify(104729, ...)` olusturuldu.
- Android sistem kaydi `isInteractive=false` gosterdi; launcher/NotificationShade
  odaktaydi, Elcim sohbet ekrani degildi. Bildirim importance=4, gizlilik
  gorunurlugu SECRET olarak kayitliydi.

Bu, uygulama kapali ve ekran kapaliyken grup ses kaydi alma + bildirim yolunun
gercek cihazda calistigini dogrular.

## Fiziksel Birebir Denemesi

Ayni cihazlar ve ayni surum, 25 Eylul 2026 cihaz yerel saati:

- Gonderici: 17:23:35.672, `tx-progress group=false`, 1 parca.
- Alici: 17:23:36.734, FCM receiver icin yeni surec baslatildi;
  17:23:36.931 Firebase arka plan servisi basladi.
- 17:23:38.123: `rx-complete bytes=19176 group=false`.
- 17:23:38.137: `notify(104729, ...)` ile mesaj bildirimi olusturuldu.
- 17:23:38.358: sistem kaydi `isInteractive=false`; bildirim kaydi
  importance=4 ve SECRET gorunurlugunde.

Hem grup hem birebir ses kaydi alimi ve Android bildirimi bu iki fiziksel
denemede dogrulandi. Kullanici uygulamayi actiktan sonra iki kaydin da sesinin
geldigini teyit etti. Bu denemeler icin teslim, Android bildirimi ve duyulabilir
oynatma kontrolu tamamlandi. Bu sonuc yukarida belirtilen tum baglanti kesintisi
senaryolarinda garantili teslim veya fiziksel iOS testi anlamina gelmez.
