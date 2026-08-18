# Android Device Production-Readiness Tracker

Bu dosya Android cihazda gozlenmis istemci davranislarinin tek kanit
kaynagidir. Kanit fiziksel Samsung yerine izole AVD'den geldiyse satirda acikca
belirtilir. Birim/widget testi, native API sozlesmesi, tek cihazli medya testi
ve iki istemcili uctan uca test ayni sey sayilmaz. Her satir yalniz belirtilen
kanit seviyesine kadar kapanir.

Sunucu kaynaklari bu calismanin kapsaminda degildir. Gerektiginde yalniz
`tool/` altindaki loopback QA sunucusu veya istemci test doubles kullanilir;
production server kodu degistirilmez.

## Durumlar

- `PASS`: belirtilen kapsam kayitta adi verilen Android cihazda calistirildi ve
  assert edildi; AVD kullanimi ayrica etiketlenir.
- `PARTIAL`: alt davranislar gecti, tam kullanici senaryosu henuz bitmedi.
- `HOST ONLY`: otomatik test var, fiziksel cihaz kaniti yok.
- `BLOCKED`: istemci disi bir onkosul eksik; sebep ve tekrar komutu yazili.
- `NOT RUN`: henuz cihazda tetiklenmedi.

## Cihaz ve kosu ortami

- Tarih: 2026-08-18
- Cihaz: Samsung SM-S921B, Android 14, 1080x2340
- ADB seri numarasi: `RFCY601MDPT`
- Paket: `com.securechat.app`, debug `1.0.76` (`versionCode=76`)
- Host-device route: `adb reverse tcp:18443 tcp:18443` ve lokal QA auth icin
  `adb reverse tcp:18444 tcp:18444`
- Izin onkosulu: ilk kosuda contacts/camera/microphone/notification izinleri
  kullanici tarafindan elle verildi. Test APK yeniden kurulunca Android bu
  grant'leri sildigi icin kalici normal APK `adb install -r -g` ile, kullanicinin
  acik yetkisine dayanilarak kuruldu. Bu kayit izin dialog UX'inin gectigi
  anlamina gelmez; yalniz izin verilmis native davranisi kanitlar.
- Cihazda rehber verisi yoktur; ContactsProvider sifir satiri basariyla
  dondurmustur. Gercek kisi icerigi loglanmadi veya hosta alinmadi.
- D03 sonrasinda debug build'e `applicationIdSuffix = ".debug"` eklendi.
  Sonraki integration turlari `com.securechat.app.debug` paketini kullanir;
  giris yapilmis `com.securechat.app` oturumu test runner tarafindan artik
  kaldirilmaz veya ezilmez. Release application ID degismemistir.

## Tamamlanan fiziksel turlar

### D01 - Temel navigasyon ve sohbet etkilesimi: PASS

Komut:

```bash
flutter test --no-pub integration_test/device_core_flow_test.dart \
  -d RFCY601MDPT --reporter expanded
```

Kanitlanan davranislar:

- Uygulama ve yatay ana pager render'i.
- Ayse Demir sohbetini acma ve geri donme.
- Attachment tray: kamera, galeri, dosya ve anket aksiyonlari.
- Tek-gosterim modunda mesaj gonderme ve repository persistence.
- Tek-gosterim iceriginin listede tekrar acilamamasi.
- Arama, Rehber ve Ayarlar tab gecisleri.
- Ayarlar listesinin yedekleme bolumune kadar kaydirilmasi.

Sonuc: `All tests passed`.

### D02 - Native gizlilik, medya ve platform sozlesmesi: PASS

Komut:

```bash
flutter test --no-pub integration_test/device_native_contract_test.dart \
  -d RFCY601MDPT --reporter expanded
```

Ilk kosu gercek bir urun hatasi buldu: `WebRtcMediaEngine._prepare()` ilk
aramada `close()` cagiriyor, `close()` ise initialize edilmemis
`RTCVideoRenderer.srcObject` alanina yaziyordu. `flutter_webrtc` bunu
`Call initialize before setting the stream` ile reddediyordu. Renderer temizligi
yalniz renderer'lar initialize edildiyse yapilacak sekilde duzeltildi. Ikinci
kosu tum adimlarla gecti.

Kanitlanan davranislar:

- Android Keystore/secure storage master key'i 32 byte ve iki okumada kalici.
- Call-readiness native map'i beklenen dort typed alani donduruyor.
- Android ContactsProvider izin verilmis durumda aciliyor; bu bos cihazda
  sifir satir donduruyor.
- Android self-managed Telecom account registration hata vermiyor.
- WorkManager'in iki periyodik isi kaydediliyor.
- Connectivity plugin fiziksel cihaz state'ini donduruyor. Cihazin normal
  network state'i `none`; ADB reverse bir Android network transport'u degildir.
- Gercek mikrofondan AAC kayit, pause/resume, non-empty dosya ve waveform
  olusumu; test sonunda gecici dosya siliniyor.
- Gercek kamera+mikrofon ile WebRTC offer; SDP `m=audio` ve `m=video` tasiyor.
- Mute, camera enable/disable, kamera cevirme ve speaker route cagrilari.
- Sessiz local notification `SECRET` lock-screen visibility ile gosteriliyor,
  reconcile ediliyor ve iptal ediliyor.
- Native `enableScreenProtection` cagrisi tamamlanip `FLAG_SECURE` uygulanabiliyor.

Sonuc: `All tests passed`.

### D03 - Kalici Android sistem kaydi: PASS

Integration runner test sonunda paketi kaldirdigi icin normal debug APK ayrica
uretilip kalici kuruldu ve baslatildi. Sonrasinda ADB `dumpsys` ile:

- PID acik ve `MainActivity` foreground.
- JobScheduler'da `com.securechat.app` icin iki `SystemJobService` kaydi var.
  Birincisi yaklasik 15 dakika minimum latency ve 30 saniye exponential
  backoff; ikincisi yaklasik 7 gun latency ve 15 dakika backoff tasiyor.
- Telecom `PhoneAccountRegistrar`,
  `SecureChatConnectionService` hesabini `Capabilities: SelfManaged` olarak
  listeliyor.
- Notification archive, test bildirimini `elcim_messages_low_v1`, mesaj
  kategorisi ve `vis=SECRET` olarak listeliyor. Baslik/govde kanit dosyasina
  alinmadi.
- `READ_CONTACTS`, `CAMERA`, `RECORD_AUDIO`, `POST_NOTIFICATIONS`,
  `MANAGE_OWN_CALLS` ve `USE_FULL_SCREEN_INTENT` grant'leri sistemde goruluyor.

### D04 - Canli auth ve USB signaling: PARTIAL

Internetsiz cihaz icin host `127.0.0.1:18443` uzerinde production TLS'e ham
TCP relay acildi ve `adb reverse tcp:18443 tcp:18443` uygulandi. APK su debug
define'lariyla uretildi:

- API: `https://127.0.0.1:18443`
- signaling: `wss://127.0.0.1:18443`
- certificate pin host: `127.0.0.1`

Relay uzerinden olculen production sertifika SPKI SHA-256 degeri compiled
birincil pin ile birebir eslesti. Hostname/system trust gevsetilmedi; pinned
public key dogrulamasi devam etti.

Kullanici email OTP ve kayit akisinin tamamlanip uygulamaya girildigini
dogruladi. Ilk giriste HTTP calisirken signaling disconnected kaldi. Kok neden,
Android `ConnectivityManager` durumunun ADB reverse kullanilirken `none`
olmasi ve lifecycle'in socket acilimini bundan once fail-closed durdurmasiydi.
Yalniz non-product build ve tum endpoint'ler loopback ise system-network
olmadan ADB transportuna izin veren politika eklendi. Hedef testleri gectikten
sonra cihazda:

- connection-status hata ikonu UI'dan kayboldu;
- ADB -> host relay -> production TLS hatti uzun sureli `ESTABLISHED` oldu;
- WebSocket reconnect yerine acik kaldi.

Ham `SocketException` UI'da endpoint/platform ayrintisi gostermesin diye auth
transport hatalari typed `AuthApiException.network` ve yerellestirilmis
`connection_failed` sonucuna map edildi.

2026-08-18'de ikinci, tamamen lokal ve deterministik auth turu eklendi.
Ephemeral sertifikali QA sunucusu yalniz `127.0.0.1:18444` dinledi; cihaz
`adb reverse tcp:18444 tcp:18444` ile baglandi ve APK sertifikanin gercek SPKI
SHA-256 degeriyle derlendi. Sistem trust/hostname kontrolu gevsetilmedi. Ayrik
`com.securechat.app.debug` paketindeki
`integration_test/device_auth_lifecycle_test.dart` su davranislari fiziksel
cihazda assert etti:

- yanlis OTP icin HTTP 401 ve kullanici oturumu olusmamasi;
- kontrollu 429 rate-limit/retry-after ve SMTP-disabled sonucu;
- OTP, registration token, kayit, authenticated prekey upload ve WSS connect;
- session dosyasinda plaintext profil sizmamasi ve restart-okunur tokenlar;
- refresh token rotation, onceki tokenin tekrar kullaniminda 401;
- logout sonrasinda server revoke, socket kapanisi ve kalici local temizleme;
- ayni cihazda yeni registration token ile yeniden giris ve ikinci logout.

Bu kosu ilk kez debug manifest birlesimini de gercek derleme yolunda tetikledi.
Debug etiketi ana manifest etiketiyle cakistigi icin debug manifestine standart
`tools:replace="android:label"` eklendi. Degisiklik yalniz debug source-set'tedir;
release etiketi, application ID ve privacy manifesti degismedi.

Kalan: clean-install onboarding/izin aciklama ekranlari ve dort native izin
dialogunun kullanici-etkilesimli turu.

### D05-D06 - Sohbet, rehber ve grup modulleri: PASS

Komut:

```bash
flutter test --no-pub \
  integration_test/device_chat_group_modules_test.dart \
  -d RFCY601MDPT --reporter expanded
```

Test gercek encrypted snapshot DAO, `SendMessageUseCase`, chat/group servisleri
ve cihaz Dart runtime'ini kullandi. Yalniz uzaktaki ikinci peer ve private
directory cevabi deterministik test sinirinda modellendi. Fiziksel cihazda:

- reply kimligi ile mesaj gonderme, 15 dakika icinde edit, reaction, star,
  message pin ve herkes icin silme;
- poll olusturma/oy verme, yeni ID ve yeni AEAD zarfiyla baska sohbete forward;
- sohbet ici arama, mute, archive, conversation pin/favorite/manual-unread;
- normalize edilmis iki cihaz kisisi icin local hash korelasyonu, registered
  contact persistence ve ham telefonun discovery sinirina gecmemesi;
- yeni grup, uye ekleme/cikarma, admin yetkisi, isim ve duyuru-only politikasi,
  mute/lock ve non-admin mutation reddi;
- signaling zarfinda plaintext/grup metadata sizmamasi, disk snapshot'inda
  plaintext bulunmamasi ve veritabanini kapatip yeniden acinca state'in kalmasi

assert edildi. Checkpoint'lerin dordu de tamamlandi ve sonuc
`All tests passed` oldu.

### D07-D08 - Sifreli medya ve WebRTC peer turu: PARTIAL

Komut:

```bash
flutter test --no-pub integration_test/device_media_peer_test.dart \
  -d RFCY601MDPT --reporter expanded
```

Fiziksel cihazdaki urun servisleriyle:

- 257 byte dosya dokuz authenticated encrypted parcaya ayrildi; wire'da ad,
  caption ve kaynak message ID bulunmadigi denetlendi;
- parcalar ters sirada alinip orijinal byte dizisine eksiksiz birlestirildi ve
  private manifestten caption/view-once/message ID geri acildi;
- gercek medya preview route'u belgeyi render etti, caption aldi ve view-once
  secimini typed `MediaSendRequest` olarak geri dondurdu;
- iki ayri `WebRtcMediaEngine`, gercek Android `flutter_webrtc` runtime'inda
  audio offer/answer ve iki yonlu trickle ICE alisverisi yapti;
- iki peer de `connected` durumuna ulasti ve iki uzak media stream olustu

assert edildi. Sonuc `All tests passed` oldu. D07 icin Android sistem
kamera/galeri/dosya secici UI turlari; D08 icin gercek ayri cihazdaki grup
mesh ve gelen/giden self-managed Telecom UI hala ayri kanittir.

2026-08-18'de Android sistem cagri bildirimi ayrica kalici debug APK uzerinden
ADB ile `incoming -> active -> ended` sirasi kullanilarak olculdu:

- Gelen video cagrisi tek `id=1200`, `incoming_call_channel`, iki immutable
  aksiyon, full-screen/content intent, `CallStyle callType=1` ve kimliksiz
  `Elcim aramasi` metniyle gorundu.
- Aktif duruma geciste ayni bildirim kimligi `call_channel`, tek kapatma
  aksiyonu ve `CallStyle callType=2` olarak guncellendi.
- Android 14'un ongoing `CallStyle` zorunlulugu, gercek
  `SecureChatCallService` foreground service'i ve `phoneCall` type'i ile
  karsilandi; `dumpsys activity services` servisi foreground `id=1200` olarak
  kaydetti.
- `ended` sonrasinda hem bildirim hem servis kayboldu; logcat'te
  `FATAL EXCEPTION` veya foreground-service ihlali kalmadi.
- Flutter'daki global devam-eden-arama bandi native `open/answer` aksiyonunu
  cagri route'una tasir; terminal ve cagri ekranlarinda kendini gizler.

### D09-D11 - Background ve veri yasam dongusu: D09 PASS, D11 PASS

Komut:

```bash
flutter test --no-pub \
  integration_test/device_background_data_lifecycle_test.dart \
  -d RFCY601MDPT --reporter expanded
```

Tek bir encrypted database/session fixture'i fiziksel cihaz Dart runtime'inda
asagidaki sirayla calistirildi:

- one-off planli mesaj platform scheduler'a kaydedildi, encrypted signaling
  zarfi olarak gonderildi ve plani silindi;
- offline disappearing-timer update'i kalici kuyruga yazildi, reconnect
  sonrasinda flush edilip kuyruktan kaldirildi;
- parola korumali `.elbk` yedegi token/plaintext sizdirmadan olusturuldu;
  silinen tam DB satiri yedekten atomik geri getirildi;
- grup sohbet export'u olusturuldu ve yalniz diger admine encrypted audit
  gitti; wire'da icerik veya `EXPORT` olay adi bulunmadi;
- auto-download politikasi encrypted state'te kaldi, disk boyutu gercek
  dosyadan hesaplandi, media temizlendi ve text mesaji korundu;
- loopback HTTP sunucusunun onayladigi hesap silme; Bearer auth, push
  unregister, plan cancel, session/token clear, tum DB satirlari ve yonetilen
  media/backup dizinlerinin silinmesiyle tamamlandi.

Bes checkpoint de gecti ve sonuc `All tests passed` oldu. Ardindan uygulama
prosesi sonlandirildi ve kayitli WorkManager isi Android JobScheduler tarafinda
force-run edildi. Sistem `SystemJobService` ile yeni prosesi baslatti; worker
yaklasik `4.594 s` icinde `SUCCESS` dondu ve periyodik is yeniden planlandi.
Boylece D09 process-kill, OS execution ve restart reconciliation kapsami da
fiziksel cihazda kapandi.

### D10 - Bildirim cold-start ve gizlilik: PASS

Kalici debug APK prosesi kapatildiktan sonra debug-only ADB hook'u ile redacted
mesaj bildirimi olusturuldu. Sistem bildirimi `SECRET/PRIVATE` gorunurlukte
tuttu. Content intent tetiklenince Android yeni `MainActivity` prosesi baslatti
ve Flutter ilk frame yarisi olmadan `debug-conversation` sohbet route'una gitti.
Uygulama bootstrap'i tamamlanmadan gelen tap'in kaybolmasina neden olan race,
pending payload'in navigator hazir oldugunda tuketilmesiyle kapatildi.

### D12 - Safe-area, composer ve responsive UI: PARTIAL

- Onboarding ve izin sayfalari alt sistem navigation inset'ini hem CTA hem
  indicator icin tuketir; Samsung gesture/3-button alt bolgesine icerik tasmaz.
- `320x568` ve `%200` metin testinde onboarding, ana shell ve devam eden cagri
  bandi overflow vermedi; Arabic RTL ve tablet yonu otomatik matriste gecti.
- Sohbet composer'i ayri input yuzeyi ve baglamsal mic/send aksiyonu olarak
  duzenlendi. Fiziksel klavye acikken input alani yaklasik `194 dp` kullanilabilir
  genislikte kaldi, alt navigation ile cakismadi; view-once kontrolu `48 dp`
  dokunma hedefine sahip.
- Tam ekran bazinda fiziksel light/dark, Arabic RTL ve TalkBack ekran kaydi
  matrisi henuz tamamlanmadigi icin D12 genel satiri `PARTIAL` kalir.

### D13 - Release negatif guvenlik: PASS (API 33 AVD)

Kullanici oturumunu bozmamak icin son kaynak, temiz `tg_test13` AVD'sinde
release-mode APK olarak test edildi. Kurulum imzasi yalniz QA icin Android debug
sertifikasiydi; derleme tipi, R8/AOT ve manifest release'tir.

- Hardened AAB `86645886` byte ve SHA-256
  `2d36a8f56327262b815f0e2d253827f47f46129eb49f6ba72f4fb5343faaf85b`;
  18 native library stripped, private key/server-secret taramasi temizdir.
- Paket `debuggable=false`; `run-as com.securechat.app` sistem tarafindan
  reddedildi. Teslim DEX'inde `IntegrationTestPlugin` ve
  `TestNotificationReceiver` bulunmadi.
- `dumpsys window`, aktif `MainActivity` icin `SECURE` flag'ini kaydetti;
  `screencap` cikisi sifir byte oldu.
- Birlesmis teslim manifestinde `allowBackup=false`, `fullBackupContent=false`,
  `usesCleartextTraffic=false`; data-extraction tum private domainleri dislar.
- Uygulamaya ait call foreground service ve FileProvider exported degildir;
  Telecom ConnectionService yalniz sistem `BIND_TELECOM_CONNECTION_SERVICE`
  izniyle exported'dir. Logcat'te crash, token, pin girdisi veya server-secret
  izi bulunmadi.

## Fiziksel cihaz kapsama matrisi

| Tur | Ozellik grubu | Durum | Tam kapanis icin kalan |
|---|---|---|---|
| D01 | Ana pager, tablar, sohbet ac/kapat, composer | PASS | Diger sohbet aksiyonlari D05'te. |
| D02 | Keystore, Contacts bridge, mic, WebRTC capture, Telecom register, notification, FLAG_SECURE | PASS | Peer-to-peer media ve OS call UI D08'de. |
| D03 | Kalici WorkManager/Telecom/permission sistem kaydi | PASS | Gercek task execution D09'da. |
| D04 | Splash, onboarding, izin aciklamalari, kayit, OTP, session/refresh/logout | PARTIAL | Canli kayit+USB WebSocket ile lokal negatif OTP/rate-limit/refresh/logout/relogin gecti; clean-install izin UX kaldi. |
| D05 | Reply/edit/delete/reaction/star/pin/poll/forward/search/archive/mute | PASS | Gercek ikinci peer ile delivery D07-D08 iki-peer turunda ayrica sinanacak. |
| D06 | Rehber discovery, yeni grup, uye/admin/duyuru/grup bilgisi | PASS | Production private-directory deploy rotasi dis server blocker'i olarak ayridir. |
| D07 | Kamera secici, galeri, dosya picker, medya preview, voice-note UI, encrypted transfer | PARTIAL | Native capture/voice, preview ve encrypted transfer gecti; sistem picker ve voice sheet UI kaldi. |
| D08 | 1:1/group call, SDP/ICE, reconnect, incoming/outgoing Telecom UI, missed call | PARTIAL | Gercek iki-peer 1:1 SDP/ICE/media ve Android 14 CallStyle/FGS lifecycle gecti; grup mesh ve Telecom karsi-uc UI kaldi. |
| D09 | Planli mesaj, background execution, offline/reconnect, process restart | PASS | OS force-run, killed-process SystemJobService bootstrap, worker SUCCESS ve yeniden planlama gecti. |
| D10 | Bildirim tap/dismiss/deep route, foreground suppression, privacy | PASS | Killed-process content intent yeni prosesi baslatip hedef sohbeti acti; `SECRET/PRIVATE` kaniti gecti. |
| D11 | Backup/restore/export/storage/auto-download/data cleanup/account delete | PASS | Encrypted tam yasam dongusu fiziksel cihazda gecti. |
| D12 | Tema, locale/RTL, font scale, ekran boyutu, accessibility, UI/UX goruntu incelemesi | PARTIAL | Onboarding safe-area ve klavyeli composer fiziksel; responsive/RTL widget matrisi gecti. Tam fiziksel light/dark/RTL/TalkBack ekran turu kaldi. |
| D13 | Release negative security: FLAG_SECURE, backup, cleartext, logs, exported surface | PASS | Temiz API 33 AVD'de release APK ve audited AAB negatif kontrolleri gecti. |
| D14 | Gercek FCM wake/push | BLOCKED | Cihaz Play Services `241518038`, plugin min `261200000`; provider credential ve guncel servis gerekli. Local notification D02'de gecti. |
| D15 | iOS/CallKit/APNs/BGTask/Keychain | BLOCKED | macOS/Xcode ve fiziksel/simulator iOS kapisi daha sonra. Kaynak statik audit ayri. |

## Siradaki otonom sira

1. D04 icin debug paketi clean-install ederek onboarding ve dort native izin
   dialogunu tek kullanici-etkilesimli cihaz oturumunda bitir.
2. D07-D08 icin ikinci kontrollu peer (emulator veya ikinci app instance) ile
   encrypted file ve WebRTC signaling turunu calistir. Production server
   kaynaklarini degistirme.
3. D12 icin fiziksel light/dark, Arabic RTL ve TalkBack checkpoint turunu
   tamamla; iOS safe-area kanitini D15'te ayri tut.
4. D14-D15 harici push saglayicisi, macOS/Xcode ve Apple hesap kosullari
   saglandiginda ilgili platform turlarini calistir.
5. Her turdan sonra bu matrisi gercek kanitla guncelle; `NOT RUN` veya
   `PARTIAL` bir satiri varsayimla `PASS` yapma.
