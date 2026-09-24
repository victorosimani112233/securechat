# Guvenli e-posta ile hesap kurtarma

## Kapsam

Kullanici 23 Eylul 2026'da korumali hesap-kurtarma kaydini onayladi. Bu
degisiklik, numarayi bilen veya herhangi bir e-postaya erisen kisinin o hesabi
almasina izin vermez. Eski kayit OTP'leri yalnizca yeni kayit icindir.

- Ayarlar > Kurtarma e-postasi: acik oturum, mevcut Signal ozel anahtariyla
  amaca ozel imza ve e-posta kodu birlikte istenir. Mevcut bag otomatik
  degistirilmez; eski hesaplara e-posta tahmin edilerek eklenmez.
- Kayit ekranindaki mevcut hesaba giris: daha once baglanmis e-posta, kod,
  ardindan oturum/kimlik degisimi onayi. Telefon varligini aciklayan sorgu yok.
- Bilinmeyen e-posta icin istek yaniti ayni bicimdedir. Bu yanit e-postanin
  kayitli oldugunu veya SMTP tesliminin gerceklestigini kanitlamaz.
- Yeni cihazda eski ozel anahtar bulunmuyorsa yeni Signal kimligi olusturulur.
  Eski oturumlar iptal edilir. Bu tek cihazli kurtarmadir, coklu cihaz ekleme
  degildir. E-posta ele gecirilirse hesap kurtarma da risk altindadir; e-posta
  saglayicisinda guclu parola ve MFA kullanilmalidir.
- Eski sohbetler sunucudan indirilmez. Yedek ayrica geri yuklenir; yedekler
  Signal ozel anahtarlarini ve giris tokenlarini icermez.

## Nerede Ne Degisti

- `lib/src/auth/account_recovery_coordinator.dart`: UI icin kurtarma sozlesmesi.
- `lib/src/auth/secure_account_recovery_coordinator.dart`: guvenilir cihaz
  kaydi, amaca bagli imza, login, acik kimlik degisimi onayi, kesilen islemi
  surdurme ve hesap UUID denetimleri.
- `auth_api.dart`: yalniz belirlenmis kurtarma endpoint'lerine HTTP erisimi;
  mevcut pinlenmis istemci tekrar kullanilir. `auth_coordinator.dart` bu
  servisi baglar; bekleyen kurtarma varken yeni hesap kaydi engellenir.
- `pre_key_manager.dart`, `crypto_protocol_store.dart`, `secure_chat_database.dart`:
  yeni ozel anahtarlar sunucu isteginden ONCE sifreli bekleyen kayda yazilir.
  Yaniti kaybolan istek ayni completion ID, anahtar ve imza ile yeniden
  gonderilir. Gelen tokenlar anahtar etkinlestirilmeden once sifreli kaydedilir.
  Yerel kimlik kurulumu atomiktir; diger kisilerin guvenilen anahtarlari korunur.
- Giris, prekey yayini basarili olmadan tamamlanmis sayilmaz. Sonrasindaki
  WebSocket baglanti hatasi yeni OTP/kimlik olusturmaz; normal baglanti
  gostergesi ve yeniden baglanma akisina aittir.
- `features/auth/recovery_*screen.dart`, `auth_screen.dart`, `settings_screen.dart`:
  kayit/giris ayrimi, e-posta baglama, kod, onay, tekrar deneme ve acik
  dogrulamayi yeniden baslatma adimlari. Dort dil, kaydirilabilir formlar,
  klavye ve buyuk yazi destegi.
- `services/peer_identity_review_service.dart`, `signal_protocol_crypto_service.dart`,
  `libsignal_protocol_store.dart`, kisi bilgileri ve kimlik inceleme ekrani:
  eski/yeni/kendi SHA-256 anahtar parmak izi. Onay yalniz ekranda gosterilen
  tam anahtara baglidir; sonradan degisen anahtar reddedilir. Karsi tarafla
  guvenilir bagimsiz kanaldan karsilastirma onayi gerekir. Otomatik guven
  sifirlama yok. Yerel pin degisimi ve etkilenen oturum temizligi atomiktir.
- `backup_service.dart`: UUID sahipligi ve aktif anahtarlari koruyan yedek
  geri yukleme. Ayni numara farkli UUID icin sahiplik kaniti degildir.
  Ayrintilar: [BACKUP_RECOVERY.md](BACKUP_RECOVERY.md).
- Sunucu: `server_hardened/signaling-server` altindaki recovery servisleri,
  yeni migrasyon, kimlik anahtari degisimi korumalari, oturum iptali ve
  hesap silme/retention entegrasyonu. Kokteki eski sunucu hedef alinmadi.
- `secure_chat_database.dart`, `encrypted_record_store.dart` ve lifecycle:
  arka plan isolate'inin yazdigi mesaj/sayaclarin eski on plan cache'inde
  kaybolmamasi icin baglanti oncesi yenileme eklendi. SQLite `data_version`
  degismedikce tam veri yeniden okunmaz. Aktif izleyiciler saniyede bir
  surumu denetler; yazma islemi once SQLite kilidi alir, sonra guncel
  goruntuyu okuyup degistirir. Bu kontrol sunucuya sorgu gondermez.

## Veri ve Guven Siniri

Kalici e-posta/hesap bagi yeni metaveridir ve kullanici onayiyla eklendi.
Indeksler ayri amacli HMAC; hesap/e-posta baglami ayri anahtarla AES-GCM
korumalidir. SQL dokumunde acik e-posta/hesap eslesmesi tutulmaz. **Bu kayit
E2EE degildir**: calisan sunucu kurtarma sirasinda baglami cozer ve SMTP
saglayicisi e-posta adresini gorur. Sunucu gizli anahtarlariyla birlikte ele
gecirilirse bu koruma metaveriyi gizleyemez. Mesaj icerigi ve Signal ozel
anahtarlari bu kayda eklenmez.

OTP 10 dakika, en fazla 5 deneme; tamamlamaya ozel yetki ve birebir tekrar
yaniti 5 dakika. Bekleyen kayit cihazda sifreli tutulur ve tamamlaninca silinir.
Islem sonuclanmadan uygulama kapanirsa giris ekranindaki tekrar deneme ayni
kaydi kullanir. Suresi gecmis/islem sonucu belirsiz durumlarda kullanici acikca
yeni dogrulama baslatabilir; onaylanmis yerel ozel anahtar korunur.

## Canliya Alma

Yeni JAR, yeni veritabani migrasyonu, SMTP ve birbirinden/onceki sirlarindan
farkli `RECOVERY_INDEX_KEY` ile `RECOVERY_ENCRYPTION_KEY` gerekir. Bunlar
sunucu sirlaridir; Flutter dart-define, Git, APK veya dokumana yazilmaz.
Her biri bagimsiz 32 bayt rastgele degerin Base64 kodlamasidir. Anahtarlari
her yeniden baslatmada degistirmeyin: mevcut kurtarma kayitlari okunamaz.
Ikisi de yoksa kurtarma kapali kalir; eski OTP kayit yolu kurtarma yerine
kullanilmaz. Mevcut hesaplar guvenilir cihazdan bir kez e-posta baglamalidir.

Ilk uygulama asamasinda canli sunucuya SSH/yukleme yapilmadi. Daha sonra
23 Eylul'de kullanici onayi ve actigi SSH baglantisiyla asagidaki canli
dagitim tamamlandi. Gercek SMTP ile hesap kurtarma ve iki fiziksel cihaz
arasinda yeni kimlik onayi henuz dogrulanmadi.
Mac/Xcode olmadigindan native iOS derlemesi yapilmadi.

## Dogrulama Kaydi

- Kurtarma, anahtar malzemesi, yedek ve peer-kimlik hedefli turu: 67 test gecti.
- Ilk tam Flutter turu: 808 test gecti, 3 test basarisizdi. UI katmaninin
  crypto yerine servis sozlesmesini kullanmasi ve gercek UUID bekleyen yedek
  test fixture'i duzeltildi; ilgili 27 test tekrar gecti. Sunucu epoch
  kontrolunun kaynak denetimi son sunucu degisikligiyle tekrar calistirilacak.
- Yerel cache duzeltmesinden onceki tam Flutter turu: **811 test gecti**.
  O turdaki statik analiz temiz; iOS readiness ve Codemagic privacy audit
  PASS. Bunlar native iOS derlemesi degildir.
- Cache duzeltmesi: 73 hedefli test ve 16 yeni testin tekrar turu gecti.
  Tam turda saptanan watcher kapanis beklemesi duzeltildikten sonra ilgili
  45 test ve son tam Flutter turunda **829 test gecti**. Bos izleme kontrolu
  yazma kuyruguna is eklemez; acik yenileme/yazma islemleri siralidir.
  Son statik analiz denemesi host inotify/acik dosya limitine takildi;
  temiz sonuc olarak degerlendirilmedi. Sistem limitleri degistirilmedi.
- Sunucu: recovery/schema 28, bot API 190 test gecti. Tam signaling turu
  1.274 test calistirdi; schema sorunu duzeltilip tekrar dogrulandi.
  Uc GroupJanusGateway testi host inotify limiti nedeniyle halen basarisiz;
  tam sunucu test paketi PASS degildir.
- Yeni sunucu JAR'i derlendi; ilk test asamasinda canliya yuklenmemisti.
  Asagidaki dagitimda kullanilan SHA-256:
  `440b6b53a2d8f9d63979210804669f81b8e029a3a89022263d92d5079166dd47`.

### 23 Eylul Canli Test Sunucusu Dagitimi

- Kullanici onayli tek test hesabi, numara/OPRF eslesmesi dogrulanarak
  mevcut hesap silme endpoint'inden temizlendi. Diger hesaplar korundu.
  Ayrinti: `MESSAGE_DIAGNOSTICS_2026-09-23.md`.
- Yukaridaki SHA-256 hem aktarimdan sonra hem calisan JAR yolunda dogrulandi.
  Bu artefaktin manifestinde commit/builtAt `unknown`; V23 mevcut.
  Test sunucusunda artefakt kimligi SHA-256 ile kaydedildi. Bu bir imzali,
  temiz commit'e dayanan production release dogrulamasi degildir.
- Eski JAR'in 22 migrasyonu ile aday JAR'in karsiliklari bayt bayt ayni.
  Canli PostgreSQL uzerinde Flyway salt okunur validasyonu gecti; yalniz
  V23 bekliyordu. Normal startup migrasyonu sonucu `23|t` dogrulandi.
- Iki bagimsiz 32 bayt rastgele kurtarma anahtari sunucuda olusturuldu:
  `/root/.securechat-dev/RECOVERY_INDEX_KEY.key` ve
  `/root/.securechat-dev/RECOVERY_ENCRYPTION_KEY.key` (izin 0400).
  `dev.env` dosyasina yalniz `_FILE` referanslari eklendi. Diger sirlar
  degismedi; degerler terminale/Git'e/APK'ya aktarilmadi. Bu anahtarlar
  kalicidir; gelecekteki tasima/yedekleme onlari da guvenle korumalidir.
- Eski process TERM ile kapatildi; yeni process PID 178648 ile acildi.
  JAR yolu: `/root/securechat/kaynak/server_hardened/signaling-server/build/libs/signaling-server-all.jar`.
- Hesap silindikten sonra ve migration oncesi alinan root-only PostgreSQL
  dump'i sifreli saklandi; decrypt + pg_restore listeleme denetimi gecti.
  Eski JAR ve env ile gecici dizin:
  `/root/.securechat-dev/recovery-deploy-20260923T114312Z`.
  Systemd gecici zamanlayicisi 24 Eylul 11:43:50 UTC'de bu dizini silmek
  uzere kuruldu. Makine yeniden baslarsa gecici timer kaybolabilir;
  operator bu durumda sureli temizligi yeniden saglamalidir.
  Kalici kurtarma anahtarlari bu temizlige dahil degildir.
- Geri donus sadece eski JAR'i kopyalamak degildir: eski kod V23'u kabul
  etmez. Veritabani yedegi ancak yeni islemlerle celismedigi dogrulanarak
  kontrollu bir geri donus planinda kullanilmalidir.
- Dis HTTPS problari mevcut SPKI pinleri zorunlu tutularak gecti:
  `/health` 200; bos JSON ile `auth/login/request` 400 `invalid_json`;
  yetkisiz `account/recovery-email/status` 401. Artik 404/503 yok.
  Bu problar e-posta gondermez ve gercek kullanici girisinin yerine gecmez.
- Siradaki canli test: yeni kayit, guvenilir cihazdan kurtarma e-postasini
  OTP ile baglama, ardindan mevcut hesaba giris. OTP kullanici tarafindan
  girilecek. Mesajlasma ve yeni peer-kimlik onayi ayrica dogrulanacak.

### Bagli Android Cihaz Kontrolleri

Samsung SM_S731B uzerinde 1.0.84 ile, ekran yakalama korumasi kapatilmadan
ADB/UI Automator erisilebilirlik agaci kullanildi. Siyah ekran goruntusu
nedeniyle pixel/renk/thumbnail gorunumu hakkinda gorsel dogrulama iddiasi yok.

- Bildirim sesi ve gizlilik panelleri acilip kapandi; icerik gosterme ayari
  ses secim panelinde degil, gizlilikte.
- Kisi bilgileri basliktan acildi. Medya listesinde normal resim vardi;
  listedeki resmi secmek ilgili sohbet mesajina dondurdu.
- Sohbet basliginda son gorulme ve gecmisteki aramalarda tur, sure ve
  reddedilme bilgileri erisilebilirlik agacinda goruldu.
- Klavye acikken mesaj alani y=1166..1307, arac dugmeleri y=1172..1310
  araligindaydi; klavyenin ustunde kaldilar. Mesaj yazilmadi/gonderilmedi.
- Metin mesaji uzun basma menusunde Kopyala goruldu; Sil y=2025..2183
  araliginda, sistem gezinme dugmelerinin ustunde. Silme yapilmadi.
- Kullanici baska cihazdan gruba mesaj gonderdi. Diger sohbet acikken
  Android bildirimi `1 sohbetten 1 yeni mesaj`, alt Sohbet rozeti `1` oldu.
  Mesaj icerigi bildirimde yoktu. Sonra Ayarlar'a gecildi, rozet korundu.
- Kullanici ikinci, birebir mesaji gonderdi; Android ozeti
  `2 sohbetten 2 yeni mesaj` olarak dogrulandi. Bu sirada sistem Rehber
  uygulamasi on plandaydi. Elcim'e donuste rozet 1 kaldi; arka planin ayri
  veritabani baglantisindan yazdiklarini on plan cache'inin yenilememesi
  inceleniyor. Bu ikinci rozet kontrolu bu asamada basarili sayilmadi.
- Canli arama testi bu turda yapilmadi.

### Son Cihaz Paketi

- 1.0.85+85 release APK, onceki cihaz test anahtariyla imzalanip
  `adb install -r` ile ayni Samsung'a kuruldu. Paket yoneticisi surum 85'i
  ve 23 Eylul 10:39 kurulumunu dogruladi; veri temizleme yapilmadi.
- APK v2/v3 imzasi ve 16 KB zipalign denetimi gecti. Kaynak tablosundaki
  13 `raw/elcim_*` sesi ile karsilik gelen 13 paketlenmis WAV dogrulandi.
  Release kaynak dosya adlari kisaltilmistir; sadece ZIP icinde `res/raw`
  aramak seslerin olmadigini gostermez.
- APK SHA-256:
  `f881d6055a2bc41f64c23dd41d70ca262f3a12b39d351f45b64053c0c8a06931`.
- Yeni APK'nin soguk acilisinda iki sohbetin her birinde bir okunmamis
  mesaj ve alt sekmede toplam **2** dogrulandi. Mesajlar acilmadi.
  Arka plan/yeni mesaj/one donus canli tekrar testi icin kullanicidan
  ucuncu mesaj istendi; bu adim henuz tamamlanmadi.
- Test paketi: `build/app/outputs/flutter-apk/app-release-1.0.85-device-test-signed.apk`.
  Bu cihaz test imzasidir, magaza dagitim imzasi degildir.

## Kaynaklar

Tek kullanim, sinirli omur ve hesap varligini ifsa etmeyen yanitlar icin
[OWASP Forgot Password Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html).
Mevcut Signal kutuphanesinin imza algoritmasi ve bagimsiz anahtar dogrulama
siniri icin [XEdDSA](https://signal.org/docs/specifications/xeddsa/) ve
[X3DH](https://signal.org/docs/specifications/x3dh/) belirtimleri esas alindi;
yeni bir kriptografik algoritma yazilmadi.
