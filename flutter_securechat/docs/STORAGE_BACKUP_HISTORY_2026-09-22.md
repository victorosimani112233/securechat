# Depolama, yedek geri yukleme ve planli mesaj gecmisi

## Yeniden acilista kaybolan sohbetler

- Kok neden: `SecureChatDatabase.replaceFromPortableJson`, geri gelen snapshot'i
  yalnizca bellege atiyordu. JSON'dan kurulan takipli koleksiyonlar degismis
  sayilmadigi icin artimli kayit katmani bu kayitlari diske yazmiyordu.
- Duzeltme: geri yuklemede tam tablo degisimi isaretlenir ve tum koleksiyonlar
  yazilacak olarak kaydedilir. Silme ve eklemeler sifreli SQLite katmaninda
  ayni islemde uygulanir; eski sohbetlerden artik satir birakilmaz.
- `_write` hata yolunda snapshot degismisse eski bellek referansi ve reset
  durumu geri gelir. Normal artimli yazmalarin kayit bazli rollback'i korunur.
- Yedek sifrelemesi, hesap eslestirmesi ve Signal ozel anahtar/oturum
  materyalinin yedekten ayiklanmasi degistirilmedi.
- Mevcut `.elbk` dosyalari degistirilmedi. Eski surumde geri yuklenip yeniden
  baslatmada kaybolan sohbetler icin duzeltilmis surumde ayni yedek yeniden
  geri yuklenmelidir. Kullanici telefonunda otomatik geri yukleme veya veri
  temizleme yapilmadi.
- `test/backup_restore_persistence_test.dart`: gercek sifreli yedek olusturma,
  eski verinin yerini alma, veritabanini kapatip yeniden acma, kontaklar,
  sifreli disk kaydi, yedek dosyasinin degismemesi ve islem ortasinda hata
  sonrasi eski verilerin korunmasi. Iki regresyon da duzeltmeden once basarisizdi.

## Depolama kullanimi

- `storage_usage_screen.dart`: sohbet satiri artik ilgili dosya yonetimini acar.
- Yeni `chat_storage_screen.dart`: fotograf/video/ses/belge filtresi, coklu
  secim, gorunenleri secme ve onayli yerel silme. Donuste ozet yenilenir.
- `StorageManagementService.cleanSelectedFiles`: yalniz secilen sohbetin medya
  kayitlari temizlenir; metinler ve diger sohbetlerin kayitlari korunur.
  Dosya uygulamanin medya dizini disindaysa veya symlink ile bu dizinden
  cikiyorsa silme reddedilir. Paylasilan dosya son yerel referansta silinir.
- Eksik dosya disk kullanimina eklenmez; sifir baytlik mevcut dosya eksik
  sayilmaz. Hatalar kullaniciya gosterilir; basarisiz kayitlar tutulur.
- Kilitli sohbetler parola/mevcut cihaz dogrulamasi ister. Arka plana gecis
  erisimi iptal eder. Tek-gosterimlik medyanin adi veya onizlemesi acilmaz.
- Sunucudaki veya karsi cihazdaki kopyaya silme komutu gonderilmez.
- Dosya sistemi ile veritabani tek ortak atomik islem sunmaz: dosya silindikten
  sonra veritabani yazimi basarisiz olursa kayit kalabilir; sonraki denemede
  eksik dosya kaydi temizlenebilir. Geri alinamaz silme onceden onaylatilir.

## Yedek parolasi

- `backup_screen.dart`: yeni yedekte en az 8 karakter ve parola eslesmesi
  kosullari yazdikca tik/carpi ile guncellenir. Gecerli olmadan olusturulamaz.
- Mevcut 8 karakter kurali `BackupService.minimumPasswordLength` ile
  paylasilir; yeni buyuk harf/sayi/sembol zorunlulugu eklenmedi.
- Geri yukleme eski parolalari kabul etmeye devam eder. Klavye acikken dar
  ekranda gereksinimler ve onay dugmesi kaydirilarak erisilebilir.

## Planli mesaj gecmisi

- `ScheduledMessageService`, `ScheduledMessageDao`, storage entity/snapshot ve
  `scheduled_messages_screen.dart`: yeni Gecmis sekmesi ve salt-okunur detay.
- Her calistirmada alicilar, zaman ve gercek gonderim sonucu tutulur. Gunluk
  tekrarlar ayri kayittir; plan silinince veya degisince gecmis degismez.
- Tek seferlik planin kaldirilmasi ile gecmis ekleme ayni veritabani islemidir.
  Ag baglantisi yoksa plan bekler; gonderilmis gibi gecmis yazilmaz.
- Gonderildi durumu aliciya teslim veya okunma ACK'i degildir. Sifreleme,
  iletim ve diger hatalar gonderim basarisiyla karistirilmaz.
- Son 500 calistirma sifreli yerel veritabaninda tutulur ve sifreli yedeklere
  dahildir. Onceki surumlerde kaydedilmemis gonderimler uydurulmaz veya mevcut
  mesajlardan tahmin edilmez; yeni gecmis bu surumden itibaren birikir.
- Alicilardan birinde sureli mesaj aciksa veya sohbet bilgisi bulunamiyorsa
  gonderilen metin gecmis kaydina kopyalanmaz; yalniz sonuc metaverisi tutulur.
  Tekrar edecek planin kendi metni, tekrar yapabilmek icin planda kalir.
- Kilitli sohbetin metni/alici listesi gecmiste maskelenir; detay dogrulama
  ister ve arka plana geciste tekrar kilitlenir. Yeni kilit durumu canli izlenir.
- Bir servis ornegindeki cakisan callback'ler tekrar gondermez. Bu degisiklik
  ag ve yerel veritabani arasinda dagitik exactly-once garantisi saglamaz;
  gonderim sonrasi kayit oncesi process kesilmesi mevcut bir sinirdir.

## Dogrulama kapsami

- Son kaynakta `flutter test --no-pub`: **553 test gecti**.
- `flutter analyze --no-pub`: **No issues found**. Onceki inotify sorunu bu
  dogrulama turunda yasanmadi. `git diff --check` temiz.
- Geri yukleme/dayaniklilik, depolama temizleme ve planli mesaj gecmisi icin
  gercek sifreli veritabaniyla testler eklendi.
- Parola, depolama yonetimi ve gecmis icin widget testleri; dar ekran/buyuk
  metin, secim/iptal/onay ve kilit denetimleri.
- Bu degisiklikler sunucu, E2EE protokolu veya Kotlin uygulamasini degistirmez.
- Android APK test imzasi mevcut telefonla ayni tutulur; magazaya yayin imzasi
  degildir. iOS native derlemesi bu Linux ortaminda calistirilmadi.

## Android kurulumu

- Mevcut `185.22.184.114` API/signaling adresleri ve iki sertifika piniyle
  release APK derlendi: **1.0.78+78**, 123.6 MB.
- APK: `build/app/outputs/flutter-apk/app-release-device-test-signed.apk`.
- SHA-256: `45fd9a07ebe1df8a0805156841dbe30627b8ccf6611ed3e931c23e65d031643f`.
- Mevcut telefonla ayni test sertifikasi dogrulandi. Samsung SM-S731B'ye
  `adb install -r` sonucu **Success**; kurulu surum ve guncelleme zamani
  **22 Eylul 2026 10:51:58** olarak dogrulandi. Veriler temizlenmedi.
- 13 bildirim/arama ses kaynagi APK kaynak tablosunda mevcut.
- Kullanicinin gercek yedegiyle telefonda restore yapilmadi. Yeniden acilis
  kaliciligi otomatik testlerde gercek sifreli test veritabanlariyla dogrulandi.
- Commit/push ve sunucu deployment'i yapilmadi.
