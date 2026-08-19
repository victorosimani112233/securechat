# SecureChat Flutter Migration Notes

Bu dizin mevcut Kotlin/Android ve Swift denemelerine dokunmadan olusturulan Flutter tasima hedefidir.

## Kapsam

- Ana bilgi mimarisi korundu: Auth, Sohbetler, Chat, Aramalar, Rehber, Ayarlar.
- Android Compose tasarim tokenlari Flutter ThemeData icine tasindi.
- Domain modelleri `Conversation`, `LocalMessage`, `MessageStatus`, `MessageContentType` olarak Dart'a tasindi.
- Signaling JSON codec Kotlin `SignalMessage` union'iyle ayni ana tipleri kapsayacak sekilde genisletildi.
- Repository, crypto ve signaling katmanlari arayuzlerle ayrildi ve calisan implementasyonlara baglandi.
- Production bootstrap demo veri eklemez; yeni kurulum gercek auth ekranina gider.

## Bilerek Degistirilen Noktalar

### 1. Hilt / ViewModel yerine AppContainer

Kotlin tarafindaki Hilt provider grafigi Flutter'da explicit
`AppContainer.bootstrap()` composition root'una tasindi. Production kurulumu
`AppContainer.production` ile tum zorunlu feature runtime'larini compile-time
zorunlu alir; kismi container yalniz `@visibleForTesting`
`AppContainer.testing` yolundan kurulabilir. Test verisi ve tokenlari
`test/support/test_app_container.dart` altindadir; production `lib/` agacinda
demo seed veya demo credential bulunmaz.

Widget'lar `AppContainerScope` uzerinden yalniz application service/port'larina
ulasir. HTTP, Signal primitive, database, native channel, Firebase ve WebRTC
permission/renderer ayrintilari feature ekranlarindan cikarildi. Bu sinirlar
`test/architecture_boundaries_test.dart` ile yeni import veya production test
fixture sizintisina karsi sabittir. Ek bir state-management paketi yalniz isim
degisikligi icin eklenmedi; stream sahipligi ve use-case sinirlari mevcut
servislerde acik tutuldu.

### 2. Room + SQLCipher yerine encrypted snapshot database

Flutter tarafinda `SecureChatDatabase` eklendi. Kotlin `storage` modulundeki ana entity/DAO gruplari Dart'a tasindi: conversation, message, contact, call log, scheduled message, export log, pending timer update, identity, prekey, signed prekey, session ve sender key. Snapshot app support dizininde AES-GCM ile sifrelenmis dosyada tutulur.

Neden: Android Room + SQLCipher dogrudan iOS'a tasinabilir bir API degil. Ortak Flutter kodunu hemen Android/iOS'ta calistirmak icin platform bagimsiz encrypted store secildi.

Karar: `ConversationRepository` `SecureChatDatabase` DAO'lari uzerinden
calisir. Mevcut Android Room v1-v22 + SQLCipher dosyasi native salt-okunur
exporter ile tum tablolar ve Signal binary state korunarak bu store'a atomik
aktarilir. Ayrintili sema ve geri-alma kurallari `ROOM_SCHEMA_MAP.md` ve bu
belgenin 34. bolumundedir; destructive migration yoktur.

### 3. Signal Protocol ve cihaz-ici AEAD ayrimi

Production `CryptoService`, `SignalProtocolCryptoService` ile Kotlin'in
`signal-protocol-android 2.8.1` V3 direct-session ve SenderKey wire formatini
uygular. PreKey, ratchet reply, SKDM ve grup ciphertext'i gercek Java 2.8.1
fixture'iyle iki yonlu capraz test edilir. Session/bundle/sender-key hatasinda
mesaj FAILED olur; local AES veya plaintext fallback yoktur.

`LocalAeadCryptoService` yalniz Keystore/Keychain master key altindaki cihaz-ici
session, database ve gecici migration zarflarini AES-GCM ile korur. Mesajlasma
protokolu yerine kullanilmaz. Protokol ve lisans kararinin ayrintisi 33.
bolumdedir.

### 4. Android FLAG_SECURE ve iOS ekran goruntusu farki

Android'de `FLAG_SECURE` ekran goruntusunu engeller. iOS ayni kesinlikte genel ekran goruntusu engelleme sunmaz; screenshot event yakalanabilir, hassas view'lar app switcher'da maskelenebilir.

Karar: `NativeBridge.enableScreenProtection()` platform channel olarak ayrildi.
Android native `FLAG_SECURE` uygular. iOS screenshot kaydini/olayini izler ve
uygulama arka plana giderken app-switcher goruntusunu privacy overlay ile
maskeler; iOS'un sistem genelinde screenshot'i kesin engelleyen bir API'si
olmadigi belgelenmis platform farkidir.

### 5. Telecom Framework ve CallKit farki

Android self-managed `ConnectionService` ve foreground service kullaniyor. iOS'ta CallKit + PushKit gerekir ve arka plan VoIP davranisi Apple kurallarina tabidir.

Karar: Ortak `NativeCallIntegration` sozlesmesi Android'de self-managed `PhoneAccount` + `ConnectionService`, iOS'ta `CXProvider` + `CXCallController` ile gerceklestirildi. Answer/end/mute sistem aksiyonlari method channel uzerinden Dart `CallManager` durumuna geri aktarilir.

### 6. WebRTC ve Janus

Kotlin tarafindaki 1:1 WebRTC akisi `flutter_webrtc` ile tasindi: dinamik ICE/TURN config, getUserMedia, unified-plan PeerConnection, SDP offer/answer, ICE trickle, remote/local renderer, mic/speaker/camera/switch-camera ve reconnect/failed durumlari calisir.

Karar: Signaling codec grup arama, SFU room ve Janus metadata tiplerini tasir. Janus istemcisi Bearer-auth WebSocket, create/attach, VideoRoom publisher join/publish, subscriber attach/start, keepalive, trickle ICE ve private/mDNS candidate filtreleme davranisiyla tasindi. Grup aramalarinda ortak local stream uzerinden katilimci basina ayri mesh PeerConnection/renderer kurulur; 4+ katilimci icin Janus publisher ve subscriber PeerConnection'lari acilir. Coordinator fanout, uye giris/cikis, coordinator degisimi, SDP/ICE buffer/replay ve mesh/SFU video grid UI tamamlandi.

### 7. Signaling client

In-memory signaling yerine `WebSocketSignalingService` eklendi. `/ws?userId=...` endpoint'ine Authorization Bearer header ile baglanir, gelen JSON'u `SignalMessage.decode` ile yayinlar ve kopusta sinirli exponential backoff uygular.

### 8. Keystore / Keychain ve crypto state

Master key'in app-support dizininde Base64 dosya olarak tutulmasi kaldirildi. `flutter_secure_storage` ile Android Keystore ve iOS Keychain kullanilir. Encrypted database uzerinde remote identity TOFU, registration ID, local identity, one-time prekey, signed-prekey rotation, session ve sender-key store sozlesmeleri bulunur.

### 9. Offline queue ve stuck recovery

Kotlin `OfflineMessageQueue` yorumda encrypted queue dese de send basarisizliginda `PendingMessage.content` alanina plaintext koyuyordu. Bu davranis guvenlik hedefiyle celistigi icin birebir tasinmadi. Flutter kuyruğu yalniz `EncryptedSignalMessage`, encrypted group fanout veya encrypted file-transfer kabul eder ve encrypted database'e yazar. Reconnect'te sirali flush ve 30 saniyelik stuck-SENDING recovery eklendi.

### 10. Gercek auth ve gonderim akisi

Demo token ile login kaldirildi. OTP request/verify, register, blind-RSA private
contact discovery, access/refresh rotation, prekey upload ve WebSocket connect
gercek signaling-server endpoint modellerini kullanir. Rehber hash listesi TLS
icinde dahi server'a acik gonderilmez; istemci ortak-anahtarli telefon
ciphertext'i de tasimaz. Mesaj gonderiminde
plaintext once encrypted local DB'ye SENDING olarak yazilir, wire payload bir
kez sifrelenir, retry'larda ayni ciphertext kullanilir ve encrypt/send
tukendiginde FAILED olur.

Fiziksel Android auth kaniti icin `tool/local_device_qa_server.dart`, yalniz
loopback'te ephemeral TLS ile calisan stateful bir QA endpointidir. Kontrollu
yanlis OTP, rate-limit ve SMTP-disabled sonuclarinin yaninda tek-kullanimlik
registration token, authenticated prekey upload, access/refresh rotation,
logout revoke ve user/token eslemeli WSS upgrade uygular. Production koduna
test bypass'i eklenmedi. `integration_test/device_auth_lifecycle_test.dart`
gercek SPKI pinli `adb reverse` hattinda encrypted session persistence,
eski refresh token reddi, logout temizligi ve relogin'i fiziksel cihazda
dogrular.

Android applicationId/namespace ve iOS bundle identifier Kotlin uygulamasiyla ayni `com.securechat.app` degerine cekildi. Release signing debug key'e bagli degildir; air-gapped release ortami kendi signing configuration'ini saglamalidir.

### 11. Contacts modulu

Android `ContactsContract` ve iOS `Contacts.framework` icin ayni Flutter
method-channel sozlesmesi eklendi. Rehber izni native platformdan istenir;
numaralar Dart ortak katmaninda normalize edilip yerel SHA-256 correlation
handle'ina donusturulur. Handle listesi server'a gonderilmez: 3072-bit
blind-RSA OPRF girdileri rastgele cover degerleriyle her istekte tam 256
elemana doldurulur. Server'in token-label ve token-AEAD ile sealed snapshot'ini
yalniz eslesen yerel token acabilir. Eslesme/gorunen ad/telefon encrypted local
database'e yazilir, cihaz rehberinden silinen kayitlar temizlenir ve server'da
caller-contact sosyal grafigi tutulmaz. Telefonla kullanici bulma ve secili
uyelerle kalici grup olusturma UI'a baglandi.

### 12. Media: 1:1 cagri ve sifreli dosya aktarimi

`CallManager` Kotlin durum gecislerini korur: outgoing/incoming, ring timeout, connecting/active/reconnecting, remote hangup/reject/busy, guvenilir call-control retry+ACK, medya kontrolleri, ikinci gelen cagri ve encrypted database call log. Chat sesli/goruntulu arama aksiyonlari gercek manager'a, arama gecmisi de gercek `CallLogDao` stream'ine baglandi.

`FileTransferManager` native picker'dan stream alir; 1 GB limit, 128 KB chunk, sabit bellek kullanimi, her chunk icin zorunlu direct/group encrypt, maksimum dort gonderim denemesi, ilerleme stream'i, siradan bagimsiz disk tabanli birlestirme, 10 dakikalik stale cleanup ve path traversal dosya adi temizligi uygular. Encrypt/decrypt/tamper hatasinda plaintext fallback veya kismi dosya yoktur.

Android/iOS secici uyumlulugu icin `file_picker` 10.3.10'a sabitlendi. 11.x'in mevcut AGP 9 legacy-DSL yapisinda Kotlin plugin sinifi APK'ya girmedigi yerel build ile dogrulandi; bu nedenle calisan son surum pinlendi. Bu karar `pubspec.lock` ve offline cache ile tekrar uretilebilir.

### 13. Background workers ve planli mesajlar

Kotlin AlarmManager/WorkManager business logic'i ortak Dart servisine tasindi. Tek seferlik, gunluk ve secili hafta gunleri planlari; alici fanout'u; enable/disable/delete; tekrar hesaplama; encrypted DAO persistence ve no-plaintext-fallback gonderim zinciri calisir. Sureli mesaj temizligi, stuck-SENDING recovery, offline disappearing-timer flush ve yedi gunluk sender-key rotation ayni background runtime icinde yer alir.

Android `workmanager_android` ile kalici one-off/periyodik gorev kullanir. iOS 15+ `BGTaskScheduler`/Background Fetch kullanir; `Info.plist` kimlikleri ve background isolate plugin registrant'i kaydedildi. iOS kesin saat garantisi vermedigi icin her app launch/resume'da ayni due-message/cleanup akisi catch-up olarak calisir. Planli mesaj olusturma, duzenleme, gun/saat/alici secimi, ac-kapat ve silme ekrani Ayarlar'a baglandi.

### 14. Incoming pipeline ve push wake-up

Encrypted direct/group mesaj acma, metadata parser, dedup, teslim/okundu durumlarinin monoton ilerlemesi, edit/delete/reaction/pin, kaybolan mesaj zamanlayicisi, typing/presence timeout ve sender-key dagitim kabul akisi ortak `IncomingMessageHandler` icinde calisir. Database yazma kuyrugu serialize edilerek eszamanli callback'lerde snapshot kaybi engellendi.

`firebase_core` ve `firebase_messaging` ile Android FCM/iOS APNs token alma, server register/unregister, token refresh, foreground/background metadata-only wake-up ve socket drain eklendi. Push payload mesaj plaintext'i tasimaz; asil icerik authenticated WebSocket uzerinden alinir. iOS release icin APNs signing key ve `SECURECHAT_FIREBASE_IOS_APP_ID` dis provisioning girdisidir.

### 15. Parola korumali yedek ve export audit

Kotlin `.elbk` kripto formati korunur: 32-byte salt + 12-byte IV + AES-256-GCM ciphertext/tag; anahtar PBKDF2-HMAC-SHA256 ve 120.000 iterasyonla turetilir. JSON once GZIP ile sikistirilir. Flutter v2 backup, profil ile birlikte tum encrypted database gruplarini kapsar fakat access/refresh/push tokenlarini bilerek disarida tutar. Kotlin v1 conversation/message/contact yedekleri icin okuma-yukseltme yolu vardir. Restore oncesi hesap telefonu dogrulanir, tum snapshot parse edilir ve ancak sonra atomik replace yapilir. Dosya bazli yanlis parola sayaci besinci denemede Kotlin davranisi gibi silme dener.

Grup export politikasi yalniz mevcut admin tarafindan degistirilebilir ve `UPDATE_EXPORT_POLICY` ile uyelere yayilir. Grup export kapaliyken export islemi reddedilir. Acikken sohbet TXT uretilir; diger adminlere mesaj icerigi degil, kisi bazli sifrelenmis ozet audit payload'i gider. Gelen audit yalniz payload map'inde yer alan admin tarafindan acilir ve encrypted lokal `ExportLogDao`'ya kaydedilir. Admin-only gecmis ekrani eklendi.

### 16. Grup/sohbet bilgisi ve depolama tercihleri

Grup yonetim use-case'leri ortak servise tasindi: 256 uye limiti, admin kontrolu, toplu uye ekleme, cikarma, yonetici atama, ad degistirme, duyuru modu, export politikasi ve gruptan ayrilma. Gelen CREATE/ADD/REMOVE/LEAVE/UPDATE_ADMIN/UPDATE_NAME/SET_READ_ONLY/UPDATE_EXPORT_POLICY sinyallerinde bilinen admin yetkisi tekrar kontrol edilir; degisiklikler encrypted DAO'ya ve dedup edilen sistem mesajina yazilir. Uye ayrilma/cikarilmada sender-key kayitlari ileri gizlilik icin temizlenir.

Kisi bilgisi ekraninda sohbet ici arama, medya/dokuman, yildizli mesajlar, lokal kisi notu, mute, sohbet kilidi ve direct/group disappearing-timer fanout calisir. Otomatik indirme politikasi encrypted state'te tutulur; Wi-Fi/hucresel kategori matrisi ve hucresel boyut limiti Kotlin davranisini korur. Depolama ekrani gercek disk boyutunu analiz eder ve kullanici onayiyla yalniz medya/dosya kayitlarini ve fiziksel dosyalari temizler; metin mesajlari korunur.

### 17. Ilk acilis, izinler ve toplu mesaj

Splash pulse, uc sayfalik onboarding ve permission walkthrough tasindi. Tamamlanma bayraklari plaintext preferences yerine encrypted database state'inde tutulur. Bildirim izni Firebase Messaging/APNs, rehber mevcut ContactsContract/Contacts.framework bridge, mikrofon ve kamera izinleri WebRTC media acquisition ile istenir; olusan gecici track'ler hemen kapatilir. iOS izin istemleri `Info.plist` usage-description alanlariyla, Android runtime manifest izinleriyle calisir. Reddetme auth/main akisini engellemez.

Toplu mesaj ekrani sohbet listesinden coklu alici secer ve her aliciyi mevcut `SendMessageUseCase` no-plaintext-fallback zincirinden bagimsiz gecirir. Tek alicinin encrypt/send hatasi digerlerini durdurmaz; sonuc basarili/basarisiz alici sayilariyla raporlanir.

### 18. Medya secimi, onizleme ve mesaj yasam dongusu

Kotlin `MediaPreviewScreen` davranisi Flutter'a tasindi: kamera, coklu galeri ve coklu belge secimi; yatay sayfalama; dosya adi/MIME/boyut bilgisi; 1000 karakter caption; tek-gosterim secimi ve ortak caption'in yalniz ilk medyaya uygulanmasi. Android process-kill sonrasinda `image_picker.retrieveLostData()` ile yarim kalan kamera/galeri sonucu sohbet acilisinda kurtarilir.

Onceki Flutter akisi dosya chunk'larini gonderiyor fakat sonucu mesaj DAO'suna yazmiyordu. `MediaMessageService` bu boslugu kapatir: giden dosyayi kalici app-support medya dizinine kopyalar, sifreli transfer sonucunu SENT/FAILED olarak kaydeder ve gelen tamamlanmis dosya event'ini conversation/message DAO'larina idempotent yazar. Tek-gosterimlik gelen medya ilk acilista `isViewed` olur; gonderici ve tuketmis alici tekrar acamaz. Normal resimlerde app-ici zoom goruntuleyici, belgelerde kontrollu native open ve share kullanilir.

Android open/share `FileProvider` ile salt app files/cache koklerinden URI uretir. iOS ayni canonical sandbox kontrolunden sonra `UIDocumentInteractionController` veya `UIActivityViewController` acar. Bu path siniri, sifresi acilmis veritabanina kotu niyetli bir dosya yolu yazilsa bile uygulamanin rastgele cihaz dosyalarini paylasmasini engeller. iOS HEIC orijinali yeniden kodlanmaz; platform gosterebiliyorsa onizlenir, aksi halde dosya karti kullanilir ve byte'lar degistirilmeden sifreli gonderilir.

### 19. Ortak TLS/SPKI pinning

Kotlin `CertificatePinner` ayarlari ayni host, birincil ve rotasyon/yedek pin degerleriyle Flutter'a tasindi. Dart `SecureHttpClientFactory`, TLS baglantisini `SecureSocket` ile kurar, X.509 DER icinden tam `SubjectPublicKeyInfo` elementini sinir kontrollu parser ile cikarir ve SHA-256 sonucunu iki pinle karsilastirir. Normal CA/hostname dogrulamasi korunur; self-signed sertifika yalniz SPKI pin gercekten eslesirse kabul edilir. Pinli host proxy ile acilmak istendiginde sertifika gorunurlugu kaybolacagi icin baglanti fail-closed olur.

Bu client auth/refresh, rehber discovery, ICE/TURN config, push token register/unregister, ana signaling WebSocket ve Janus WebSocket'e enjekte edilir. WorkManager/BGTask isolate'i de ayni policy ile client olusturur. `https`/`wss` kullanilirken pin hostu, birincil veya yedek pin eksikse ya da API/signaling hostlari pin hostuyla eslesmiyorsa uygulama bootstrap'i ag istegi yapmadan durur. Air-gapped/release override degerleri `SECURECHAT_CERT_PIN_HOST`, `SECURECHAT_CERT_PIN_SHA256` ve `SECURECHAT_CERT_PIN_SHA256_BACKUP` dart-define girdileridir.

### 20. Sohbet arama, mute/temizleme ve anketler

Chat menusu artik bildirim gosteren bos aksiyonlar kullanmaz. Sohbet arama alanı aktif stream'deki mesajlari anlik filtreler ve sonuc yok durumunu gosterir. Mute encrypted conversation kaydina yazilir. Sohbet temizleme geri donulemez oldugu icin onay ister ve yalniz secili conversation mesajlarini DAO uzerinden siler.

Kotlin anket JSON semasi (`question`, 2-4 `options`, `singleChoice`, option-index -> voter-id listesi `votes`) ortak `PollData` modeliyle dogrulanir. Olusturma normal `SendMessageUseCase` icinden POLL metadata ve zorunlu AEAD ile gider. Oylama onceki Flutter incoming handler'daki yanlis voter-id -> option-index map davranisini duzelterek ayni option-index -> voter-list semasini kullanir. Direct ve group vote envelope plaintext olarak signaling'e verilmez; once mevcut crypto servisiyle sifrelenir, group fanout tek ciphertext kullanir. Uc gonderim denemesi de basarisizsa optimistic lokal oy eski JSON'a geri alinir.

PushKit incelemesi istemci-only bir eksik olmadigini gostermistir: mevcut degistirilmeyecek signaling server yalniz FCM registration token saklar ve Firebase Admin sender kullanir. APNs VoIP token kaydi ile `.voip` topic sender endpoint'i olmadan client tarafinda token toplamak calisan kapali-uygulama cagrisi uretmez. Bu nedenle native tarafta sahte/bosa token kaydi eklenmedi; server/provisioning gereksinimi kritik listede acik tutuldu.

### 21. Mesaj etkilesimleri

Kotlin sohbet davranislarindaki reply, edit, delete, reaction, star ve pin akislari Flutter'a tasindi. Reply normal `SendMessageUseCase` icinde `replyToId` metadata'siyla ayni zorunlu sifreleme hattini kullanir. Yildiz yalniz yerel ve sifreli DAO durumudur. Metin duzenleme yalniz giden, tek-gosterim olmayan metinlerde ve gonderimden sonraki 15 dakika icinde kabul edilir. Lokal silme cihazdaki kaydi kaldirir; herkesten silme, edit, reaction ve pin once tum direct/grup alicilarina uc denemeli fanout yapar, ancak basaridan sonra yerel DAO'yu degistirir. Grup pin islemi yalniz admin icin aciktir. Son mesaj onizlemesi edit ve silme sonrasinda yeniden hesaplanir.

Reaction kalici semasi Kotlin incoming davranisiyla ayni olacak sekilde `emoji -> voter-id listesi` olarak tekillestirildi; kaldirma bos emoji grubunu da temizler. Uzun-bas menusu bu aksiyonlari baloncuga baglar, reply ve reaction bilgileri sohbet icinde gosterilir.

Wire uyumlulugu nedeniyle mevcut Kotlin protokolundeki `MessageEditSignal.newContent` alani ve delete/reaction/pin kontrol metadata'si signaling envelope'unda acik kalir. Flutter bunu sessizce daha guvenliymis gibi gostermedi veya server protokolunu tek tarafli kirmadi. Icerik/metadata gizliligi hedefi icin bu kontrol mesajlarinin protokol v2'de sifreli payload icine alinmasi, Kotlin/server/Flutter istemcilerinin birlikte guncellenmesi gereken ayri bir tasarim borcudur.

### 22. Sesli mesajlar

Kotlin storage semasindaki `VOICE_NOTE` tipi ve expiry/search/export davranislari vardi; ancak Kotlin app/media kaynaklarinda ayri bir sesli-not kayit/gonderim UI'si bulunmuyordu. Flutter'daki daha once yalniz enum seviyesinde duran bu tip gercek uretim ve tuketim akisina baglandi. `record` backend'i Android `AudioRecord/MediaRecorder`, iOS `AVFoundation` kullanir. Ortak oynatilabilir cikti icin AAC-LC, mono, 32 kHz ve 64 kbps M4A secildi; iOS Opus/CAF Android tarafinda ortak oynatma garantisi vermedigi icin kullanilmadi.

Kayit mikrofon iznini fail-closed kontrol eder; pause/resume, 100 ms dBFS ornekleme, 64 noktaya sinirli waveform ve 10 dakika otomatik pause vardir. Taslak app-support `voice_drafts` dizininde uretilir, gonderimde kalici `media/sent` kopyasi olustuktan sonra silinir. Kayit byte'lari mevcut 128 KB AEAD chunk transferinden gecer; plaintext fallback yoktur. Sure ve waveform `SCVN1` surumlu/limitli JSON metadata olarak mevcut encrypted-caption kanali icinde gider. Bu sayede signaling zarfina acik waveform/sure yazilmaz; eski istemci metadata'yi anlamasa da M4A dosyasini normal ses eki olarak alabilir.

Giden ve gelen mesajlar `VOICE_NOTE` olarak encrypted DAO'ya yazilir. Yerel content ilk dort Kotlin dosya alanini (`ad|MIME|boyut|path`) korur ve sona sure/waveform ekler. Sohbet baloncugu dalga formu, sure, play/pause, seek ve tamamlaninca basa sarma davranisini sunar. Eksik veya silinmis dosya uygulamayi dusurmeden hata durumu gosterir. iOS mikrofon aciklamasi sesli mesajlari da kapsayacak sekilde guncellendi.

### 23. Uygulama yasam dongusu ve presence

Kotlin `AppLifecycleObserver` karsiligi `AppLifecycleCoordinator` olarak tasindi. Daha once Flutter yalniz resume aninda cleanup calistiriyor; persisted oturumla acilista WebSocket kurmuyor, online/offline presence yollamiyor ve background'da socket'i kapatmiyordu. Coordinator lifecycle gecislerini tek kuyrukta siralar; yinelenen `resumed`, `hidden` ve `paused` event'leri cift connect/disconnect uretmez.

Foreground akisi logged-in kullaniciyi guncel session token provider ve refresh callback ile signaling'e baglar. Baglanti sonrasinda expiry cleanup, stuck-message recovery, pending timer flush ve scheduled send catch-up calisir; ardindan `recipientId=server` online presence ve FCM/APNs token yeniden kaydi yapilir. `shareLastSeen` encrypted session store'a eklendi; false ise presence online bilgisi korunurken yalniz last-seen server tarafinda gizlenir. Logged-out acilista ag baglantisi kurulmaz ama cihaz-ici cleanup yine calisir.

Background akisi socket aciksa once offline presence'i gonderir, sonra manuel disconnect ile reconnect dongusunu durdurur. Arka plan mesajlari mevcut metadata-only push + drain worker yolunda kalir. Uygulama dispose ve gercek logout da ayni temizligi tetikler. Logout HTTP endpoint'i erisilemez olsa bile yerel access/refresh/push verisi ve WebSocket mutlaka temizlenir; kullanici ag hatasi nedeniyle cihazda oturumdan cikamaz durumda birakilmaz.

### 24. Ayarlar ve kullanici tercihleri

Kotlin `ThemeManager` ve `SettingsViewModel` tercihleri Flutter'da salt gorunum satiri olmaktan cikarildi. Sistem/acik/koyu tema, bildirim icerigi, varsayilan/sessiz bildirim sesi, sohbet filigrani, tam ekran, planli mesaj ana anahtari, son gorulme ve profil fotografi yolu access/refresh tokenlarla ayni AEAD korumali session envelope'unda kalici tutulur. Uygulama kokundeki tema stream'i degisikligi yeniden baslatma gerektirmeden uygular; filigran tercihi tum `AzureBackdrop` kullanan ekranlara yansir.

Android tam ekran tercihi `immersiveSticky`, kapatma ise `edgeToEdge` sistem UI modu kullanir. iOS kalici olarak status/home-indicator alanlarini gizleme yetkisi vermedigi icin ayni anahtar guvenli `edgeToEdge` gorunume uyarlanir ve bu fark UI'da aciklanir. Bildirim sesi secimi platformlar arasi tekrar uretilebilir `default`/`silent` ile sinirlidir; Android'e ozgu keyfi ringtone URI'si iOS'ta eslenemedigi icin tasinmamistir.

Son gorulme degisikligi encrypted session'a yazildiktan sonra socket aciksa `presence_update` ile server'a aninda iletilir; sonraki lifecycle event'leri de ayni tercihi kullanir. Planli mesaj ana anahtari kapatildiginda aktif WorkManager/BGTask kayitlari iptal edilir, acildiginda encrypted DAO'daki aktif planlar yeniden kurulur ve gecikmis kayitlar catch-up islemine girer. Profil resmi yalniz gorsel MIME ve 10 MB siniriyla kabul edilir, app-support profil dizinine kopyalanir; onceki yonetilen dosya yenisi kalici olduktan sonra silinir. Disaridan gelen rastgele bir path silinmez.

Kotlin'deki `DataCleanupManager` ve hesap silme akislari da tasindi. Yalniz cihaz verisini silme push tokenini best-effort kaldirir, server logout/revoke dener, aktif planli gorevleri iptal eder, encrypted database'i tek atomik bos snapshot ile degistirir ve yalniz uygulamanin yonettigi medya/profil/yedek dizinlerini siler. Kalici hesap silmede authenticated server endpoint'i `200` dondurmeden yerel kimlik veya veri silinmez; server reddinde kullanici retry yapabilecek sekilde oturum korunur. Server onayindan sonra yerel cleanup hata verse bile tokenlar `finally` icinde temizlenir. UI cihaz silme icin geri donulemez onay, hesap silme icin tam `SİL` metni ister ve once yedekleme ekranina gecis sunar.

### 25. Yerel mesaj bildirimleri

FCM/APNs payload'i yalniz metadata wake-up olarak kalir; server veya push servisinde plaintext mesaj olusturulmaz. `IncomingMessageHandler` ciphertext'i cihazda dogrulayip actiktan, dedup edip encrypted DAO'ya yazdiktan sonra sinirli bir notification event uretir. Android/iOS ortak coordinator bu event'i `flutter_local_notifications` 22.3.0 ile sistem bildirime cevirir. Android normal ve sessiz sohbetler icin kanal ayri tutularak kanal-seviyesi ses davranisi garanti edilir; beyaz vector small-icon ve Java core-library desugaring build'e eklendi. iOS ayni conversation ID'yi thread identifier olarak kullanir ve foreground banner/list/sound tercihlerini ayri uygular.

Kullanici acik uygulamada ayni sohbeti okuyorsa yinelenen banner gosterilmez; farkli sohbet foreground'da sessiz, background'da normal bildirilir. Mute ses/titresimi kapatir, fakat authenticated `MENTION` metadata'sinda yerel kullanici varsa mute override edilir. Global `silent` her durumda ustundur. Icerik gizleme aciksa sender, conversation ID, mesaj govdesi ve tap payload'i bildirime girmez; tek `Elçim / N yeni mesaj` bildirimi kullanilir ve Android lock-screen visibility `SECRET` olur. Tercih modu degistiginde eski bildirimler temizlenerek onceki acik onizlemelerin ekranda kalmasi engellenir. Normal bildirime dokunma conversation repository'den gercek modeli bulup sohbet rotasini acar.

### 26. Kilitli sohbet ve cihaz sahibi dogrulamasi

Flutter `isLocked` DAO/UI anahtari daha once yalniz gorunurdu; iki native bridge de `NOT_CONFIGURED` ile donuyordu ve sohbet rotasi dogrulamadan aciliyordu. Android activity `FlutterFragmentActivity` tabanina alinip AndroidX `BiometricPrompt` eklendi. `BIOMETRIC_WEAK | DEVICE_CREDENTIAL` ile biyometri veya cihaz PIN/desen/parolasi kabul edilir; eszamanli ikinci prompt reddedilir ve Activity kapanirken bekleyen sonuc guvenli `false` ile tamamlanir. iOS `LocalAuthentication.LAContext` ve `.deviceOwnerAuthentication` kullanir; Face ID aciklamasi `Info.plist`e eklendi.

Asil erisim kontrolu sohbet listesi callback'ine degil `ChatScreen` route kapisina kondu. Boylece rehberden, deep route'tan veya local notification tap'inden kilitli bir conversation acmak da ayni owner check'i gerektirir. Dogrulama surerken sohbet govdesi olusturulmaz ve mesaj okunmus sayilmaz. Iptal, enrollment olmamasi veya platform hatasi fail-closed davranir; basaridan sonra DAO read islemi ve ekran kurulumu baslar.

### 27. Arama hazirlik denetimi

Kotlin `CallReadinessHelper/Screen` Flutter'a ortak state/service ve native method-channel olarak tasindi. Android `PowerManager.isIgnoringBatteryOptimizations`, Android 14+ `NotificationManager.canUseFullScreenIntent`, Android 13+ runtime bildirim izni ve `Settings.canDrawOverlays` durumlarini raporlar. Eksik satirlar dogrudan paket-scoped pil muafiyeti, full-screen intent, uygulama bildirim veya overlay sistem ekranina gider; gerekli `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` ve `SYSTEM_ALERT_WINDOW` manifest izinleri eklendi. Ekran sistem ayarindan uygulamaya her donuste ve pull-to-refresh ile durumu yeniden okur.

iOS'ta Android'e ozgu pil muafiyeti/full-screen-intent/overlay `notApplicable` olarak modellenir; notification authorization `UNUserNotificationCenter` ile gercek okunur ve eksikse uygulama ayarlari acilir. Ekran iOS arka plan calismasinin APNs/CallKit ve sistem scheduling politikasina bagli oldugunu aciklar; Android davranisini varmis gibi taklit etmez. Ayarlar > Arama hazirligi rotasina baglandi.

### 28. Sohbet listesi yonetimi

Kotlin conversation-list arşiv, sabitleme, favori, manuel okunmadi ve silme davranislari `ConversationRepository` ortak sozlesmesine tasindi. Storage implementasyonu her islemi encrypted `ConversationDao` snapshot'ina yazar; demo/in-memory implementasyon da ayni semantigi ve stream guncellemesini korur. Silme yalniz secili conversation'i ve ona bagli lokal mesaj satirlarini atomik DAO write icinde kaldirir; diger sohbetler veya medya dizini etkilenmez.

Flutter listesinde normal filtreler arşivlenmis sohbetleri gizler, Arşiv filtresi yalniz arşiv kayitlarini gosterir. Saga swipe arşivle/arşivden cikar, sola swipe geri donulemez silme onayi ister. Uzun bas menusu sabitleme, favori, okundu/okunmadi, arşiv ve silme aksiyonlarini ayni repository'ye baglar. Kilit, mute, pin, favori ve manuel okunmadi durumlari satirda gorunur. Kilitli sohbetin unread sayaci biyometrik dogrulamadan once temizlenmez.

### 29. Mesaj iletme

Kotlin `forwardMessage` ve hedef sohbet secimi Flutter uzun-bas mesaj menusu ile gercek gonderim hattina baglandi. Metin ve anketler kaynak mesaj ID/reply bilgisini kopyalamaz; her hedef icin yeni `SendMessageUseCase` cagrisi yeni mesaj kimligi ve yeni AEAD zarf uretir. Kaynak plaintext veya kaynak ciphertext signaling'e dogrudan aktarilmaz. Anket sorusu/secenekleri korunur, onceki sohbetin voter ID listeleri yeni ankete tasinmaz.

Gorsel, belge ve sesli mesaj iletmede kaynak dosyanin uygulama sandbox'indaki yerel byte'lari okunur ve `FileTransferManager` ile yeniden chunk'lanip sifrelenir. Yeni hedefte yeni transfer/message kimligi olusur; caption ve sesli-not sure/waveform metadata'si mevcut encrypted-caption kanalinda korunur. Yerel dosyasi artik bulunmayan medya basarisiz gorunur ve metin/path olarak sessizce gonderilmez. Tek-gosterimlik, silinmis, sistem ve salt-okunur hedef mesajlari fail-closed reddedilir.

Uzun-bas ile Kotlin'deki coklu mesaj secim modu acilir; kullanici ayni sohbetten ek metin/anket/medya/ses kayitlari secebilir. Secilenler timestamp sirasinda tek hedefe ayri ayri ve kendi asil tipleriyle gonderilir. Kotlin'in medya/anketi preview metnine indirgeyen birlestirme davranisi kullanilmadi. Hedef secici encrypted repository stream'indeki aktif sohbetleri arar ve salt-okunur kayitlari secilemez gosterir. Coklu hedef bulk-message davranisiyla birlestirilmedi: Kotlin tek hedef secimi korunarak yanlislikla genis alici grubuna gonderme riski azaltildi.

### 30. Okundu bilgisi ve mesaj bilgi penceresi

Kotlin `ChatReceiptManager` davranisi `ReadReceiptService` olarak tasindi. Sohbet route'u gercekten acilip kilitli sohbet owner-auth kontrolunu gectikten sonra incoming ve henuz READ olmayan mesaj ID'lerini rezerve eder. DELIVERED tikinin gorulebilmesi icin Kotlin'deki 800 ms pencere korunur; ardindan encrypted DAO statusu READ yapilir ve yalniz mesaj kimligi/status iceren `DeliveryReceiptSignal(READ)` asil gondericiye yollanir. Ayni stream'in yeniden emit etmesi veya iki eszamanli UI callback'i duplicate receipt olusturmaz. Sohbet acikken sonradan gelen mesajlar da stream emit'inde ayni akistan gecer. Arka planda veya biyometri kapisi acilmadan READ uretilmez.

Giden mesaj uzun-bas menusune Kotlin'deki mesaj bilgi penceresi eklendi. Gonderim zamani, FAILED/SENT/DELIVERED/READ aggregate durumu ve direct/grup alicilari gosterilir. Mevcut Kotlin/server receipt semasi receipt icinde grup uye bazli kalici zaman/status matrisi tasimadigi icin grup penceresi aggregate statusu tum hedeflere uygular; Flutter tarafinda olmayan per-member timestamp uydurulmadi. Gercek uye-bazli bilgi icin protokol ve storage semasinin iki istemciyle birlikte genisletilmesi gerekir.

### 31. Uygulama dili ve katalog tasimasi

Kotlin Android kaynaklarindaki Turkce ve Ingilizce 167'ser string anahtari `tool/import_android_strings.dart` ile tekrar uretilebilir bicimde Flutter ARB kataloglarina aktarildi. Android `%1$s`/`%1$d` placeholder'lari gen-l10n parametrelerine cevrilir ve otomatik test her iki kaynak katalogdaki 167 anahtarin ARB'de eksiksiz bulundugunu denetler. Kotlin'deki mevcut 21 Almanca ve 21 Arapca ceviri korundu; bu sinirli kataloglarda olmayan anahtarlar Flutter'in Ingilizce template fallback'ini kullanir. Eksik ceviri, anahtari veya ham teknik kimligi UI'a sizdirmaz.

Dil tercihi `system`, `tr`, `en`, `de`, `ar` degerleriyle access/refresh tokenlarin bulundugu AEAD-korumali session envelope'unda kalici tutulur. `SettingsService` stream'i `MaterialApp.locale` degerini yeniden baslatma gerektirmeden gunceller; `system` secimi locale'i null yaparak cihaz tercihine doner. Arapca secimi gercek RTL `Directionality` uretir. Android manifest RTL destegini acar; iOS plist desteklenen dort dili ilan eder.

Kotlin'de bulunmayan Flutter ekranlari icin yeni metinler TR/EN kataloguna eklendi. Auth, onboarding/izin, sohbet listesi, rehber, chat ve alt diyaloglari, grup/kisi bilgisi, aramalar, medya, planli mesaj, toplu mesaj, backup, depolama ve ayarlar dahil kullaniciya donuk sabit metinler `AppLocalizations` uzerinden okunur. Marka adi, telefon ulke kodu, sayisal rozet ve gorsel ayirac gibi cevrilmemesi gereken degerler bilerek literal kalir. Locale persistence, Almanca fallback, Arapca RTL, runtime tr/ar/system gecisi ve kaynak katalog paritesi widget/service testleriyle sabitlendi.

### 32. Accessibility ve responsive UI

Kritik icon-only aksiyonlar yalniz gorsel ikona dayanmaktan cikarildi. Sohbet arama/yeni sohbet, sesli-goruntulu arama, ek, ses kaydi, gonder, grup duzenleme, dialpad ve medya temizleme aksiyonlari yerellesmis tooltip veya acik `Semantics` etiketi tasir. Ana mesaj aksiyonlari 48x48 minimum dokunma hedefiyle otomatik olculur. Auth formu dogal alan sirasi, name/telephone/email autofill ipuclari ve `next`, `next`, `done` klavye action'larini korur.

Responsive matrisi ana shell icindeki conversations/calls/contacts/settings ekranlarini, chat rotasini ve auth formunu 320x568 boyutta %200 metin olcegiyle render eder. Ayni ana shell/chat akisi 800x1280 tablette Arapca RTL ile calisir. RenderFlex/overflow veya yon hatasi test exception'i olarak build'i kirar.

Otomatik WCAG kontrast denetimi acik temadaki Azure 500 + beyaz ciftinin 3.88:1 ve Danger + beyaz ciftinin 2.92:1 oldugunu yakaladi. Palet disina cikmadan acik ana etkileşim zemini mevcut Azure Deep tokenina, acik hata zemini yeni Danger Deep tonuna alindi. Koyu temada Azure Glow zemin + Night on-color kullanildi. Normal metin icin onSurface/surface, onPrimary/primary, onSecondary/secondary, onError/error, body/scaffold ve error/scaffold ciftlerinin tumu 4.5:1 veya ustunde test edilir.

### 33. Signal Protocol V3 wire parity

Kotlin uygulama `org.whispersystems:signal-protocol-android:2.8.1` ile legacy Signal Protocol V3, Double Ratchet ve SenderKey kullanir. Flutter production mesaji icin daha onceki `LOCAL_AES_GCM` yolu kaldirildi; bu AEAD sinifi yalniz Keystore/Keychain master key ile cihaz-ici session ve encrypted snapshot dosyalarini sarmalar. Peer ve grup mesajlari `libsignal_protocol_dart 0.8.2` uzerindeki V3 `SessionCipher`, `SessionBuilder`, `GroupSessionBuilder` ve `GroupCipher` ile uretilir. Paket GPL-3.0'dur; mevcut Kotlin libsignal bagimliliginin lisans ailesi korunmustur. Resmi yeni Rust libsignal/AGPL secilmedi, cunku hedef mevcut 2.8.1 istemci ve botlarla state/wire uyumlulugunu bozmadan tasimaktir. Bu karar mevcut protokole post-quantum ozellik eklemez; o, Kotlin/server/bot/Flutter birlikte yukseltilecek ayri bir protokol surumu olmalidir.

Identity pair, registration ID, one-time prekey, signed prekey, TOFU remote identity, session record ve sender-key record libsignal'in kendi protobuf baytlari olarak encrypted DAO'larda tutulur. Prekey upload JSON alanlari Kotlin ile ayni Curve25519 public-key ve signature byte'larini tasir. Session yoksa authenticated `GET /api/v1/users/{id}/prekeys` fresh bundle getirir; ayni aliciya eszamanli kurulum tek Future'da birlesir. Bundle veya signature gecersizse encrypt hata verir ve mesaj FAILED olur; local AES/plaintext fallback yoktur.

Direct wire `E2EE:v1:PREKEY|SIGNAL:registrationId:b64` olarak kalir. Grup
SenderKey dagitim mesaji `SKDM:groupId:b64` seklinde her uyeye once 1:1 Signal
session icinde gider; dagitim basarisizsa grup mesaji gonderilmez. SenderKey
`GROUPSK:v2:<opaque-token>:b64` ic zarfi cihazlarda wire parity icin korunur.
Production gonderim bu ic zarfi ve local group ID'yi `GROUPROUTE:v3` payload'i
olarak her alicinin ayri direct Signal session'i icine sarar. Sunucu ordinary
`encrypted_message` disinda raw group ID/name, sabit grup tokeni veya tek
frame'de tam alici listesi goremez. Incoming v1/v2 dis route yalniz kontrollu
migration icin receive-only'dir; yeni gonderim geri donmez. Incoming SKDM typed
SenderKey record'a islenir. Periyodik rotasyon eski ham 32-byte preview kaydi
yazmaz; yeni SenderKey state olusturup ayni guvenli dagitim hattini kullanir.

Eski Flutter preview'i Ed25519/X25519 JSON kayitlari kullanmisti ve Signal record olarak parse edilemez. Ilk prekey bootstrap'i bu formati tespit ederse yalniz identity/prekey/signed-prekey/session/sender-key ve ilgili crypto-state alanlarini atomik temizler; conversation/message/contact gibi kullanici verileri korunur. Bu state zaten Kotlin wire ile haberlesemiyordu, dolayisiyla sessiz uyumsuz session tutmak yerine yeni Signal identity kaydi ve server prekey upload'i gereklidir.

`test/libsignal_wire_compat_test.dart`, Flutter dizinindeki test-only `LegacySignalInterop.java` aracini cache'teki tam `signal-protocol-java 2.8.1`, `curve25519-java 0.5.0` ve gercek transitive `protobuf-javalite 3.10.0` ile derler. Dart'in ilk PreKey mesaji Java'da acilir, Java ratchet cevabi Dart'ta acilir; Dart SKDM/grup ciphertext Java'da ve Java SKDM/grup ciphertext Dart'ta acilir. Ayrica production adapter persistence, fail-closed eksik bundle ve `SendMessageUseCase` dagitimdan-once-grup-ciphertext sirasi testlidir.

### 34. Room + SQLCipher cihaz-ici upgrade migrasyonu

Kotlin `securechat.db` Room v1-v22 semalari, tablo/kolon eklenme
surumleri, v22 indeksleri ve Flutter snapshot alanlari
`docs/ROOM_SCHEMA_MAP.md` icinde envanterlendi. Kotlin builder'daki
`fallbackToDestructiveMigration()` Flutter upgrade yolunda hic cagirilmaz.
Android native `LegacyRoomExporter`, Kotlin ile ayni SQLCipher 4.5.6
kutuphanesini kullanarak dosyayi salt-okunur acar. Once mevcut
`HMAC-SHA256(salt, ANDROID_ID)` passphrase'i, gerekirse eski APK'nin
Android Keystore ile sardigi random passphrase'i dener.

On iki Room tablosu kayipsiz export edilir. Identity, prekey, signed-prekey,
session ve sender-key BLOB'lari donusturulmeden Base64 tasinir. Room disindaki
`crypto_prefs` registration ID ve yerel Signal identity pair'i de ayni eski
Android Keystore alias'i ile native tarafta acilir. Gecici export plaintext
degildir: her denemede uretilen 256-bit transport anahtari ile AES-GCM
sifrelidir; anahtar yalniz method-channel cevabinda process bellegine gelir.

Dart converter tum JSON'u once parse eder, schema araligini, tablo row count,
kolon tiplerini, BLOB Base64'lerini ve message->conversation referanslarini
dogrular. Yalniz kullanici verisi bulunmayan Flutter deposu kabul edilir.
Tum satirlar, local Signal state ve import marker'i tek encrypted snapshot
write'inda commit edilir; persist hatasinda in-memory snapshot da geri alinir.
Sonraki acilista marker ayni importu tekrarlamaz ve yarim kalan native arsiv
adimini idempotent tamamlar. Basaridan sonra DB/WAL/SHM once app-private arsive
kopyalanip boyutlari dogrulanir, sonra kaynak kopyalar ve eski crypto prefs
temizlenir. Donusum/commit hatasinda kaynak DB ve aktif Flutter DB degismez.

Android 13 instrumentation testi gercek SQLCipher v22 fixture dosyasini iki
passphrase nesliyle acar, session BLOB ve Keystore identity pair baytlarini
dogrular ve onaydan once kaynak DB'nin durdugunu kanitlar. Dart testleri tum 12
tablo importunu, v1 kolon defaultlarini, idempotence, malformed/aktif-DB
fail-closed davranisini ve iOS/yeni-kurulum no-op yolunu kapsar.

### 35. Sistem ag durumu ve gizlilik-korumali socket diagnostics

Kotlin `NetworkMonitor` ve `NetworkTypeProvider` davranisi Android/iOS ortak
`SystemNetworkMonitor` icine tasindi. `connectivity_plus` yalniz aktif tasima
turunu ve sistem degisimini bildirir; Wi-Fi gorunmesini internet erisimi kaniti
saymaz. Gercek erisilebilirlik WebSocket timeout/hata hattinda dogrulanmaya
devam eder. Foreground lifecycle monitoru baslatir, background durdurur. Tum
aglar kayboldugunda socket kapatilir fakat user/token provider baglami korunur;
ag geri geldiginde veya Wi-Fi-mobil tasiyici degistiginde backoff beklemeden
yeniden baglanir. Android O sonrasi background callback kisiti nedeniyle resume
aninda mevcut durum ayrica okunur.

Auto-download servisi artik production gelen-medya hattinda monitorun gercek
`wifi/cellular/other` degerini kullanir. Kotlin davranisi korunarak sifreli
chunk aktarimi tamamlanir; politika reddederse payload diskten silinir ve mesaj
metadata'si bos file path ile kaydedilir. Bu depolama tasarrufudur, transfer
bant genisligi tasarrufu degildir.

`WebSocketTelemetry` production signaling callback'lerine baglidir ve yalniz
connect/disconnect/failure/reconnect/auth rejection sayaclari, exception sinif
adi, hata kategorisi, opsiyonel HTTP kodu ve zamani tutar. Exception mesaji,
mesaj icerigi, token, userId, URL, header ve response body saklanmaz.
`ServerCompatibilityChecker` rastgele path/fake-token taramasi yapmaz; mevcut
TLS/SPKI pinli `HttpClient` ile yalniz configured `/health` ve gercek
Bearer-authenticated `/ws` endpoint'ini kontrol eder. Disari aktarilabilir rapor
host/port dahil kimliklendirici icermez.

### 36. Crash ve non-fatal diagnostics

Kotlin'deki iki crash reporter yolu ortak `AppCrashReporter` servisinde
birlestirildi. Flutter framework hatalari, `PlatformDispatcher` hatalari ve root
zone icindeki yakalanmayan async hatalar ayni production reporter'a gider.
Raporlar app-private dizinde atomik gecici-dosya rename ile JSON olarak yazilir
ve en yeni 20 kayit tutulur. Exception mesaji, sohbet/mesaj icerigi, token,
telefon ve ham kullanici kimligi rapora girmez; yalniz hata sinifi, sanitize
edilmis stack ve whitelist metadata tutulur. Gerekli kullanici kimligi SHA-256
ile tek yonlu ozetlenir. Listeleme, son raporu platform share sheet ile paylasma
ve yalniz diagnostics dizinini temizleme davranislari testlidir.

Android/iOS native bridge, surum/build/OS/model gibi iceriksiz metadata verir.
Reporter `main()` bootstrap'indan once kuruldugu icin dependency kurulumu ve ilk
ekran hatalari da kapsanir. Native metadata veya disk yazimi hata verirse hata
raporlama uygulamanin asil akisini ikinci kez dusurmez.

### 37. Missed-call ve notification dismissal uzlastirmasi

Gelen 1:1 veya grup aramasi cevaplanmadan 30 saniye beklerse tek bir missed-call
olayi uretilir. Accept, reject, cancel, finish ve dispose timer'i iptal eder;
ayni call ID tekrar gelirse duplicate bildirim/log olusmaz. Olay conversation
son mesaji ve unread sayisini gunceller, lock-screen icerigini gizleyen local
notification gosterir ve voice/video callback aksiyonu sunar.

Kullanici bildirimi sistem tepsisinden sildiginde dismissal stream ilgili
conversation sayacini temizler. Uygulama foreground'a geldiginde aktif sistem
bildirimleriyle encrypted DAO tekrar uzlastirilir; uygulama kapaliyken kacmis
dismiss event'i kalici hayalet rozet birakmaz. Tum bildirim payload'lari ham
mesaj icerigi veya ciphertext tasimaz.

### 38. Arama kalite geri bildirimi

Kotlin `CallQualityIndicator` davranisi Flutter cagrı ekraninda
`good/fair/poor/reconnecting` durumlariyla tasindi. Uc cubuklu indikator ve
semantik etiketi, reconnect sirasinda pulse ve banner gosterir. Zayif baglanti
durumunda kullanici videoyu `CallManager.toggleCamera()` uzerinden kapatip sesli
devam edebilir; bu yalniz gorsel bir dugme degildir. Indikator seviyeleri ve
aksiyon widget testleriyle sabitlendi.

### 39. Debug-only bildirim araclari ve platform manifest kararlari

Incoming/missed/message bildirim simulasyonlari `NotificationDebugHarness`
icinde `kDebugMode` ile korunur. Android ADB receiver yalniz
`android/app/src/debug` source-set ve debug manifestinde tanimlidir. Birlesik
manifest denetiminde receiver debug APK'da var, release APK'da yoktur.

Son manifest karsilastirmasinda Android `WAKE_LOCK`, boot receiver,
FirebaseMessagingService ve WorkManager SystemJobService plugin manifestlerinden
dogru birlesir. Self-managed Telecom service `foregroundServiceType="phoneCall"`
tasir. `READ_PHONE_STATE`/`READ_PHONE_NUMBERS` eklenmedi; ortak discovery SIM
numarasini okumaz, kullanicinin girdigi normalize telefonun yalniz hash'ini
gonderir. Legacy external-storage izinleri de eklenmedi; picker ve app sandbox
scoped storage kullanir. iOS audio/fetch/remote-notification background mode'lari
hazirdir; `voip` entitlement/provisioning halen Apple/server blocker'idir.

Dosya-seviyesi audit `tool/generate_source_audit.dart` ile tekrar uretilebilir.
Son sonuc 271/271 kaynak icin PLATFORM=28, MERGED=66, COVERED=173, DECISION=4 ve
GAP=0'dur. Dört DECISION satiri production'da zaten no-op background blur,
reddedilen plaintext legacy telemetry ve kullanilmayan P2P data-channel gibi
bilincli olarak tasinmayan yollardir; eksik runtime davranisi degildir.

### 40. Clean architecture ve production composition ikinci gecisi

Production ve test kurulumu ayrildi. `AppContainer.production` auth, contacts,
crypto, network, media, background, storage, settings, audit ve lifecycle
runtime'larini zorunlu alir; bootstrap sonunda eksik graph fail-fast kontrol
edilir. Kismi graph yalniz `AppContainer.testing` ile testlerde kurulabilir.
Eski `AppContainer.demo`, demo credential/seed fonksiyonlari ve kullanilmayan
encrypted-file conversation repository production agacindan kaldirildi. Test
verisi `test/support` altina tasindigi icin `ConversationRepository ->
AppContainer` circular import'u da kalkti.

Foreground ve background bakimi artik ayni `StuckMessageRecovery` instance'ini
paylasir. Call-history UI'nin DAO'ya dogrudan baglantisi `CallHistoryService`
read modeline alindi; bu sirada Kotlin'in gercek `ANSWERED` statusunun Flutter
UI'da yanlislikla failed'e dusmesi bulundu ve typed
`CallHistoryStatus.completed` eslemesiyle duzeltildi. Optional runtime'lara
feature ekranlarindaki zorunlu `!` erisimleri kaldirildi; servis yoksa aksiyon
disable edilir veya yerellesmis unavailable state gosterilir.

Onboarding artik Firebase Messaging ve WebRTC pluginlerini dogrudan cagirmiyor.
Notification/contacts/camera/microphone izinleri `AppPermissionService` ve
`MobileAppPermissionPlatform` sinirindan geciyor. Push bootstrap izin dialogu
acmaz; yalniz token stream'ini ve daha once verilmis izinle mevcut tokeni
uzlastirir. Kullanici notifications satirina bastiginda izin ve token kaydi tek
application islemi olarak calisir. Bu ayrim iOS'un izin isteme zamanlamasini da
korur.

WebRTC `RTCVideoView`, yerel image renderer ve native dosya open/share ayrintisi
kucuk platform presentation/port sinirlarina tasindi. Buyuk chat dosyasindaki
mesaj balonu, ses kaydi/oynatici ve mesaj detay/dialog state'leri ayri Dart part
dosyalarina bolundu; route/state orkestrasyonu ana dosyada kaldi. Mimari test
feature katmaninin HTTP, crypto, database, native channel, Firebase veya
WebRTC pluginine yeni dogrudan bagimlilik eklemesini engeller.

### 41. Async state machine ve resource ownership ikinci gecisi

Production'daki sahipli fire-and-forget islemler ortak
`AsyncOperationTracker` uzerinden izlenir. Tracker yeni isi stream/timer
callback'i icinde baslamadan once kaydeder, hatayi merkezi sinira iletir ve
test/dispose icin `waitForIdle()` sunar. Socket, retry, call, recorder,
renderer, controller ve subscription terminal yollari bu sahiplik modeliyle
yeniden incelendi.

Tam paralel Flutter paketi medya persistence testinde gercek bir yarisi ortaya
cikardi: received-file event'i async stream ile yayinlandigi icin testteki sabit
30 ms bekleme bazen persistence Future'i daha kaydedilmeden bitiyordu. Event
synchronous broadcast oldu; dosya chunk islemleri transfer ID bazinda serial
tail ile siralandi; `FileTransferManager.dispose` tail'leri ve
`MediaMessageService.waitForIdle` persistence'i drain ediyor. Test artik zaman
tahmini degil gercek idle sinirini bekliyor. Duzeltme sonrasi 169/169 test tam
paralel pakette gecti.

### 42. Server veri minimizasyonu ve metadata privacy hedefi

Kok Kotlin server referans kaldi; production icin
`flutter_securechat/server_hardened` ayri hedefi olusturuldu. OTP evrensel kodu
kaldirildi, SMTP/DB/Redis ve privacy secret'lari fail-fast oldu. Offline
message/file ve bot queue/idempotency Redis key'leri HMAC blind index, degerleri
recipient/binding AAD'li AES-GCM oldu. Privacy-first varsayilan retention mesaj
icin 15 dakika, file icin 5 dakika, bot kayitlari icin 15 dakika, consumed
prekey icin 1 saat, push icin 30 gun ve TURN icin 10 dakikadir; kod
daha uzun degerleri sert ust sinirla reddeder.

Signaling ve bot Redis instance'lari transient state icin yalniz RAM store'u
olabilir. Her iki process listener acmadan `appendonly=no` ve bos RDB `save`
schedule'ini `CONFIG GET` ile dogrular; AOF/RDB aciksa veya sonuc okunamiyorsa
startup fail-closed durur. Boylece kisa TTL'li client ciphertext'i Redis disk
dosyasina ve sonraki backup'a sizamaz. Host swap/memory snapshot yasaği yine
deployment politikasinda ayrica uygulanmalidir.

APK icine gomulu ortak anahtarla acilabilen `encrypted_phone` tasarimi DB
snapshot'ini tum istemciler icin cozulur hale getirdigi icin tamamen emekli
edildi. V13 ile eski HMAC telefon index'i private-directory semasina tasindi.
Rehber girdileri blind-RSA OPRF ile 256'lik cover batch icinde degerlendirilir;
DB yalniz finalized token ve OPRF public key ID'si tutar, snapshot'taki user ID
token-AEAD ile sealed'dir. Kayit/legacy migration yalniz hesabin kendi hash'ini
transient isler; adres defteri hash'i veya caller-contact sosyal grafigi
server'a/persistence'a girmez. Flutter bilinmeyen UUID icin server phone lookup
yapmaz; isim yalniz cihaz rehberinde local cozulur. DB ve export edilebilir OPRF
key'inin birlikte ele gecirilmesi halinde sozluk direncinin kayboldugu acik risk
olarak korunur; production key'i HSM/KMS sinirina alinmalidir.

2026-08-17 fiziksel Android QA sirasinda canli
`https://94.73.180.226/api/v1/directory/config` istegi HTTP 404 dondu. Bu,
mobil implementasyon hatasi degil, calisan server artefaktinin hardened route
contract'inin gerisinde oldugunu kanitlar. Mobil taraf 404/501/502/503/504 ve
ulasim hatalarini `DirectoryServiceUnavailableException` olarak siniflandirir;
ham exception gostermez, cached cihaz eslesmelerini silmez ve telefon/hash
gonderen legacy endpoint'e dusmez. Production discovery ancak
`server_hardened` deployment'i ve public config probe'u 200 olduktan sonra
acilmis sayilir.

Push V5 ile blind user index ve user-AAD bagli randomized `v4` AEAD'ye tasindi.
V7, gecis asamasinda grup sosyal grafigini blind index + AEAD ile korumustu;
ancak ciphertext sosyal grafik de sunucu ele gecirildiginde iliski verisidir.
Bu nedenle V9 `group_members` tablosunu tamamen siler ve runtime bu veriyi
PostgreSQL/Redis'e yeniden yazmaz. V6 shared phone envelope'i, V8 gereksiz
registration/last-seen/joined/last-used/session-updated timestamp'lerini sildi.
V10 pseudonymous UUID kullansa dahi behavioral timeline olusturan `audit_log`
tablosunu siler. Server ve bot security eventleri artik yalniz event turu
bazinda kimliksiz, zamansiz RAM sayacidir; E2EE admin export audit'i sadece
admin cihazlarinda encrypted kalir.
V11 user one-time prekey teslimini `UPDATE consumed_at` yerine atomik
`DELETE ... RETURNING` yapar; kullanilmis public key veya session-bootstrap
zamani server DB'sinde kalmaz. `one_time_prekeys` ve `signed_prekeys`
`created_at` timeline kolonlari da kaldirilmistir.
V12 push token retention'ini exact `updated_at` yerine gun-duzeyi
`registered_on` ile uygular; token rotate zamaninin saat/dakika hassasiyeti DB
snapshot'inda kalmaz.
Startup migration ve retention transaction'i basarili olmadan trafik kabul
etmez. Account delete DB transaction'i ardindan push/cache/socket/presence/
call/offline queue kopyalarini temizler.

Retention worker ilk cleanup transaction'ini listener acilmadan calistirir.
Sonraki cleanup hata verirse eski davranistaki gibi yalniz warn loglayip devam
etmez: privacy health false olur, aktif socket'ler kapanir, HTTP/WS trafigi
reddedilir ve bir dakikalik aralikla tekrar denenir. Tam transaction yeniden
basarili olmadan trafik acilmaz; retention sozlesmesi availability'den once
gelir.

Grup wire v3 SenderKey ciphertext'ini ve local route bilgisini aliciya ozel
direct Signal ciphertext'i icine alir. Grup dosyasi `flutter-file-v3-group`
ile ayni modeli kullanir; ad, MIME, caption ve gercek boyut authenticated
manifesttedir, dis boyut yalniz chunk-aligned ust sinirdir. Grup aramalari her
cagri icin yeni 256-bit nonce kullanir ve katilimci listesi yalniz aktif cagri
boyunca, en cok dort saat process RAM'de yasar. Push saglayicisina yalniz generic
`securechat_wake_v2` gider. E2EE'nin kaynak IP, canli route iliskisi, zamanlama,
pad edilmis boyut ve TURN/Janus trafik analizini gizlemedigi acikca
belgelenmistir; bu sinirlar `SERVER_DATA_PRIVACY_AUDIT.md` icindeki production
sozlesmesidir.

Hardened Kotlin unit testleri ve gercek PostgreSQL 16 Testcontainers ile V1-V14
migration/push-time/group-graph/audit/prekey-timeline/final-schema privacy entegrasyonu `--offline` gecer. Flutter'daki 12
statik gate OTP bypass, PII log, ham Redis key, eski phone route, zayif push,
group/file v1 sender ve retention regression'larini release hatasi yapar.

V14, gecis donemi icin nullable kalmis `fcm_tokens.user_id` ve
`bot_signal_session.recipient_user_id` kolonlarini kaldirir. Populated upgrade
once V13 runtime converter'larini calistirmalidir; herhangi bir raw iliski,
eksik opaque index veya non-v4 push zarfi kalirsa migration silme yapmadan
durur. Boylece production kodu bu legacy kolonlari ne okuyabilir ne yeniden
yazabilir.

### 43. Sohbet kontrol metadata'sinin E2EE ve sabit boyutlu tasinmasi

Kotlin/ilk Flutter wire sozlesmesindeki `delivery_receipt`, `message_edit`,
`message_delete`, `message_reaction`, `message_pin`, `typing_indicator` ve
`disappearing_timer` frame'leri alanlarini JSON envelope disinda acik
tasiyordu. Mesaj metni E2EE olsa bile message ID, reaction emoji, yeni edit
metni, okundu davranisi ve timer suresi sunucu tarafinda davranissal zaman
cizelgesi uretebiliyordu.

Flutter production gondericileri artik bu typed control nesnelerini
`CHATCTRL:v2` ic payload'ina cevirir, sender/recipient alanlarini payload'dan
cikarir, paketi rastgele byte'larla tam 16 KiB'ye doldurur ve alicinin direct
Signal session'iyle ordinary `encrypted_message` olarak yollar. Alici kimligi
ve authenticated remote identity decrypt sonrasinda yeniden enjekte edilir.
Raw legacy control frame'leri Flutter incoming handler tarafinda uygulanmaz;
hardened Ktor server ayni yedi discriminator'i route etmeden reddeder.

Incoming authorization da sikilastirildi: receipt yalniz yerel giden mesaja,
edit/delete yalniz authenticated yazarin kendi mesajina, reaction yalniz
sohbet katilimcisina, grup pin yalniz local kayittaki admine ve timer yalniz
izinli sabit surelerden birine uygulanir. Poll vote artik baska sohbetin poll
ID'sini referanslayamaz. Admin audit outer event'i `PRIVATE_EVENT` olarak
genellestirildi; gercek `EXPORT` olayi yalniz admin-E2EE payload'indadir.

Bu degisiklik sunucunun canli sender/recipient route ciftini, kaynak IP'yi ve
paket zamanini gormesini engellemez. Bunlar icin sealed-sender/oblivious relay
gibi yeni bir protokol gerekir; mevcut route'ta varmis gibi iddia edilmez.
Kapanis kaniti: 180/180 Flutter testi, temiz analyze, 12 statik privacy gate,
hardened signaling+bot 50/50 testi (sifir skip), saf-Dart smoke, offline pub ve 496 gorevli
offline Android build basarili. Debug APK 258629658 bayt ve SHA-256
`5de03e8a64e57db45285333b1b29af3df266cd294aa1446e55dadbd0d34833ed`.

### 44. Dependency, lisans ve air-gapped supply-chain kapisi

Gizlilik yalniz protokol tasarimiyla korunamaz: cihaz plaintext'ine, rehbere ve
Signal private key'lerine erisen bir Flutter/native dependency degistirilirse
sunucuda mesaj saklanmiyor olmasi yeterli degildir. Bu nedenle dependency
integrity release'in fail-closed gizlilik kapisi yapildi.

`pubspec.yaml` hosted direct dependency'leri lock'taki kesin surumlerine
sabitler. `pubspec.lock` 129/129 hosted package icin SHA-256 tasir; Git/path
dependency yoktur ve `pub get --offline` lock'i degistirmeden gecer. Android
Gradle 9.1.0 ve hardened server Gradle 8.5 distribution SHA-256 degerleri
wrapper dosyalarinda zorunludur. Gercek dependency graph'lerinden uretilen
verification manifestleri Android'de 1.243 component/2.261 hash, serverda 544
component/829 hash tasir; trusted wildcard veya ignored-key bypass'i yoktur.

Audit `flutter_webrtc` plugininin kendi Gradle betiginde JitPack ekledigini
yakaladi. Android dependency resolution settings allow-list'i onceliklidir;
plugin project repo eklemeleri ignore edilir. Resmi Flutter engine endpoint'i
yalniz `io.flutter` grubuna, vendored repo yalniz `com.github.davidliu` grubuna
aciktir. Zorunlu `audioswitch` commit AAR/POM'u local Maven agacina byte-for-byte
tasindi; SHA-256 degerleri Gradle manifesti ve statik gate ile cift kontrol
edilir. Apache-2.0 metni Flutter asset/license registry'ye eklendi.

Air-gapped script daha once kaynak arsivinde bulunmayan hardened server
`local-repo` agacini ayri `maven_local_repo.tar.gz` olarak paketler ve restore
README'si offline signaling/bot testini de calistirir. Final cok-GB bundle tum
migration kapilari bitmeden yeniden uretilmez; mevcut bundle final diye
sunulmaz.

iOS'ta Xcode/SwiftPM graph'i Linux'ta resolve edilemez. Mac gate online ilk
turda `Package.resolved` dosyasini `ios/Package.resolved.lock` olarak saklar;
remote package varsa offline tur locksuz devam etmez ve automatic resolution'i
kapatir. Xcode 26'nin JSON `Package.resolved` ciktisi plist `plutil -lint`
kontrolunden ayrildi; v1/v3 semalarini ve pin revision alanlarini denetleyen Dart
gate'i eklendi. Flutter 3.44.9'un `firebase_core` ve `firebase_messaging` Swift
paketleri minimum iOS 15 istedigi icin Runner Debug/Release/Profile target'lari
14.0'dan 15.0'a birlikte yukseltildi; Android minimum surumu degismedi.
Xcode 26 Swift derlemesi `workmanager_apple` periodic task API'sindeki
`NSNumber?` parametresine `Int` aritmetik degerlerini ortuk cevirmedi. On bes
dakikalik maintenance ve yedi gunluk sender-key rotation sureleri urun
davranisi degistirilmeden `NSNumber(value:)` ile acikca koprulendi; readiness
audit'i iki kaydin da tipli kalmasini zorunlu tutar.
Signing/APNs private key'leri hicbir lock veya bundle'a girmez.

`libsignal_protocol_dart 0.8.2` GPL-3.0'dur. Lisans ekrani uygulamada acildi ve
dagitilan binary ile eslesen kaynak/build talimatlari zorunlulugu
`SUPPLY_CHAIN_AUDIT.md` icinde release kosulu yapildi. Bu hukuki karar Signal
wire parity'sini daha zayif bir kriptoyla sessizce degistirme izni vermez.

Kapanis kaniti: 185/185 Flutter testi, temiz analyze, saf-Dart smoke, offline
Pub, 496-gorevli offline Android build ve dependency verification etkin halde
50/50 sifir-skip hardened signaling/bot testi basarili. Guncel debug APK
258630861 bayt, SHA-256
`df924ac3040139dcf23410a9a11a9fad44816be6293b20d2ee7a14f6d29a5d3c`.

### 45. Production-caller diferansiyel ve privacy-first release kapisi

Onceki 271-satir kaynak manifesti hedef/test dosyasinin varligini kanitliyor,
fakat bir Dart dosyasinin production graph'ta gercekten yuklendigini garanti
etmiyordu. Generator ve bagimsiz Flutter testi artik `lib/main.dart`tan tum
import/export/part graph'ini kurar. Her `lib/` hedefi erisilebilir olmali ve
kendisine dogrudan baglanan erisilebilir caller'i gostermelidir. Android native
hedefi ilgili main/debug manifestte kayitli olmali; test fixture'i yalniz
`TEST_ONLY`, hedefsiz satir yalniz allow-list'teki dort `DECISION` olabilir.
Her 271 kaynak icin ayrica korunacak davranis veya privacy invariant'i zorunlu
oldu. Production agacindaki TODO/FIXME, executable stub, bos UI callback ve
`UnsupportedError` release hatasidir.

Encrypt exception yolunun signaling cagirmadigi, local mesaji `FAILED` yaptigi
ve grup gondericisinin `GroupMessageFanoutSignal` uretmeyip her alici icin
direct Signal route kullandigi statik gate ile dinamik send testinin birlikte
korudugu invariant'tir. Bu sayede eski kodla parite gerekcesi plaintext fallback
veya linklenebilir server-side grup fanout'unu geri getiremez.

Android hardened build sonuna `audit_android_release.sh` eklendi. Audit AAB'nin
cihaza gidecek `base/lib` payload'indaki 18 native kutuphanenin tamaminin
`.debug_*`/`.symtab` icermedigini, NOTICE ve R8 kanitlarini, private symbol
arsivini, credential dosyasi ve server private-key/env-secret sizintisi
olmadigini fail-closed denetler. AGP, Play'in symbol isleme hatti icin R8 map ve
native `.sym` kopyalarini AAB `BUNDLE-METADATA` alaninda tasir; bunlar cihaz
split APK'sina girmez. Buna ragmen AAB de-obfuscation materyali tasidigi icin
public download artefakti degil, Play upload icin private artefakttir.

Guncel AAB 86018778 bayt, SHA-256
`453eb94d14c4918c9112955e680ca2f71d1ab4e11236bdb6e323e7d5652bd0a0`.
Teslim-yakini unsigned release APK'sinda 18/18 native kutuphane stripped,
`BUNDLE-METADATA` sayisi sifir ve server-secret izi yoktur. Kapanis kaniti
194/194 Flutter testi, temiz analyze, saf-Dart smoke, iOS statik audit,
663-gorevli `assembleRelease --offline` ve gercek PostgreSQL V1-V14 dahil
hardened signaling+bot 64/64 sifir-skip testidir.

Disk alanini build icin geri kazanmak amaciyla eski ve zaten final olmayan
offline bundle'in yeniden uretilebilir `gradle_cache.tar.gz` ara ciktisi
kaldirildi. Mevcut `build/offline_bundle` bu nedenle teslim edilebilir degildir;
tum final kaynaklar ve Mac/iOS supplement'i hazir oldugunda modül 26 kapsaminda
yeniden uretilip checksum'lanacaktir.

### 46. Compose sohbet listesi UI/UX paritesi

Sohbetler ekrani Compose hiyerarsisine gore yeniden kuruldu: `elçim.` marka
basligi, signaling durum gostergesi ve guvenli retry sheet'i, acilip odaklanan
global sohbet/mesaj aramasi, tumu/okunmamis/gruplar/favoriler filtreleri,
arsiv ayirimi, shimmer/empty state, typing/kilitli mesaj onizlemesi ve
pin/favori/mute/unread rozetli cam kartlar ayni akista calisir. Global arama
encrypted DAO uzerinde buyuk-kucuk harf duyarsiz, yeni-tarihten eskiye ve
limitli sorgulanir; arama icin ayri plaintext index veya server sorgusu
olusturulmaz.

Feature widget'in signaling implementation tipine baglanmasi clean
architecture testinde yakalandi. `AppConnectionStatusSource` sunum adapter'i
eklenerek WebSocket tipi UI sinirinin gerisine alindi. Cam kartin DecoratedBox
katmani ripple'i gizledigi icin ortak `AzureGlassPanel`, border/clip koruyan
`Material` yuzeyine cevrildi. Conversation satiri sabit `ListTile` yerine
icerige gore uzayan `InkWell` hiyerarsisi kullandigindan 320x568 ekranda yuzde
200 metin olceginde tasma yapmaz. Arama ve daha-fazla aksiyonlari acik,
yerellesmis ekran okuyucu etiketleri tasir.

Samsung SM-S921B / Android 14 cihazinda 2.039 saniyelik cold start, empty state,
arama focus/keyboard, dort islemlik Compose menusu ve fiziksel sagdan-sola tab
gecisi dogrulandi; UI agaci `Arama / Sekme 2 / 4` icin `selected=true` verdi.
Release `FLAG_SECURE` degismedi; ekran kaniti yalniz debug manifest izniyle
alindi. Kapanis kapisi temiz analyze, 209/209 Flutter testi ve ADB-tunelli
debug APK build/install sonucudur. Ayrintili kanit matrisi
`docs/UI_UX_PARITY.md` dosyasindadir.

## Operational metadata ve production deployment sertlestirmesi

Privacy karsi-denetimi hardened server'in eski rolling file appender'larinin
redaksiyon olsa dahi 10-30 gunluk olay zaman cizelgesi olusturabildigini buldu.
Iki server hedefinde kalici appender kaldirildi, root seviye sabit `ERROR`
yapildi ve noisy HTTP/network logger'lari kapatildi. Production compose'un
`logging=none` politikasi bu sinirli console cikisini da kalici collector'a
aktarmaz; operasyon health ve bearer-authenticated kimliksiz aggregate RAM
metrikleriyle izlenir.

Secret'lar `SecretSource` ile salt-okunur `NAME_FILE` dosyalarindan alinir;
direct+file cakismasi, relative/symlink/bos/asiri buyuk kaynak ve key tekrar
kullanimi startup'ta reddedilir. Ayrica signaling ve bot `main()` ilk adimda
binary-level production politikasini uygular: verify-full PostgreSQL TLS,
credential-free JDBC URL, plaintext queue reddi, signaling icin PKCS#11 OPRF,
guvenli SMTP/client-facing Janus transportu ve bot socket'lerinin private
tmpfs disina cikmamasi zorunludur.

Yeni `server_hardened/deploy` hedefi non-root/read-only image, tum capability
drop, no-new-privileges, core/heap/error dump ve JVM attach kapatma, ephemeral
Redis tmpfs ve sifir Redis/log volume sozlesmesini tasir. Deploy scripti
varsayilan olarak yalniz preflight yapar; uc image digest'ini, secret dosya
izin/boyut/amac ayrimini ve DB TLS'ini gectikten sonra bile gercek compose
degisikligi icin acik operator confirmation ister. Eski root `infra` compose
production yoluna bagli degildir.

Kapanis kaniti 194/194 Flutter testi, 64/64 hardened Kotlin testi, temiz
analyze, Dart privacy audit, shell parse, compose parse ve olumlu/olumsuz
preflight'tir. Server fat JAR ve bot installDist offline uretilmistir. Container
base JRE indirmesi registry I/O timeout'unda kaldigi icin registry push/digest
deployment kaniti gercek operator ortamina aittir; bu durum kodda mutable tag
veya zayif fallback acmaz.

Guncel signaling fat JAR SHA-256 degeri
`ffbe8f60abc4fb6b067c3bb47acf49235b94d55816588097e440f0347702ab52`;
78 bot runtime library'sinin sirali file-hash manifest SHA-256 degeri
`c49cdcba25b23684848d68320ea24b2fe64dcd2a1f4c0701ebee3cd1469e58dc`'dir.

## Henuz Tasinmayan Kritik Parcalar

- PushKit ile kapali uygulamayi gelen VoIP aramasinda uyandirma (FCM/APNs mesaj wake-up tamam; Apple VoIP PushKit kanali ayri provisioning gerektirir)

Build zinciri notu: mevcut pinli Flutter SDK ile Android build basarilidir; ancak Flutter tool `file_picker`, `flutter_webrtc` ve `workmanager_android` eklentilerinin legacy Kotlin Gradle Plugin uyguladigini ve gelecekteki bir Flutter surumunde Built-in Kotlin migration gerekecegini bildirir. Air-gapped bundle mevcut calisan SDK/plugin lock kombinasyonunu sabitleyecek; SDK yukseltmesinden once bu uc eklenti ayrica yeniden dogrulanmalidir.

## Ktor Sozlesme ve Android Play Release Sertlestirmesi

Ktor route envanteri generator ile Flutter istemcilerine capraz baglandi;
privacy daraltmalari sonrasi production hedefindeki 22/22
HTTP/WebSocket route kararlidir ve Kotlin/Flutter `SignalMessage` setleri 33/33
esittir. Kotlin'de olup Flutter production akisinda eksik kalan one-time prekey
refresh foreground/WorkManager bakimina eklendi. Upload basarisizsa yeni local
prekey batch geri alinir; aksi halde threshold tekrar denemeyi sonsuza kadar
bastirabilirdi. Ilk parity gecisinde eklenen authenticated encrypted-phone
lookup, ortak APK anahtariyla DB degerlerini cozebilme riski nedeniyle privacy
modulunde kaldirildi. Bilinmeyen kullanici kimligi artik yalniz cihaz
rehberindeki hash eslesmesiyle local zenginlestirilir.

Play release icin endpoint ve JSON semasini APK'dan tamamen gizleme hedefi
reddedildi; bu teknik olarak garanti edilemez. Bunun yerine clientta server
secret bulunmaz, Ktor JWT `typ`/expiry/revocation/`sub`, Redis rate limit ve
Signal E2EE asil guven siniridir. Android release R8+resource shrinking ve
Flutter AOT obfuscation kullanir. Backup/device transfer ve cleartext trafik
  kapalidir; product config HTTPS/WSS disinda fail-fast olur. Dart symbol ve R8
mapping'in release-sahibi kopyasi private checksumli dizinde tutulur. AAB'nin
Play-ingestion icin kendi `BUNDLE-METADATA` symbol/map kopyasi tasidigi ve bu
nedenle AAB'nin de private kalmasi gerektigi; cihaz APK payload'inin ise stripped
ve metadata-dislanmis oldugu release audit'iyle kontrol edilir.

## Test Durumu

- Pure Dart smoke test: `/tmp/flutter-sdk/bin/cache/dart-sdk/bin/dart tool/smoke_test.dart`
- Flutter analyze: `CI=true BOT=true /tmp/flutter-sdk/bin/flutter --no-version-check --suppress-analytics analyze`
- Flutter widget test: `CI=true BOT=true /tmp/flutter-sdk/bin/flutter --no-version-check --suppress-analytics test`
- Service tests: Signal V3 direct/group/SKDM/persistence/fail-closed round-trip, local storage AEAD, encrypted database persistence ve signaling codec round-trip.
- Storage tests: encrypted snapshot database DAO contract, crypto/session/sender-key DAO persistence, plaintext sizmama; Room v1/v22 conversion, tum 12 tablo, atomiklik/idempotence ve Android SQLCipher/Keystore instrumentation fixture kontrolu.
- Crypto tests: Keystore/Keychain mock contract, TOFU identity, Signal V3 prekey imza/yenileme/rotation, preview-key migrasyonu, Java 2.8.1 direct/SenderKey capraz wire uyumlulugu ve call key zeroize.
- Network tests: persistent encrypted offline queue, stuck recovery ve gercek localhost WebSocket Bearer/typed-message alisverisi.
- TLS tests: SPKI DER extraction, sertifika yenilemesinde ayni public-key kabulü, primary/backup kabulü, farkli key reddi, malformed DER ve eksik/mismatched config fail-fast.
- Send use-case tests: tek encrypt, retry, direct/group fanout, metadata azaltma ve plaintext fallback olmamasi.
- Auth tests: OTP/register/refresh/prekey upload yerel HTTP entegrasyonu, raw
  telefon/ciphertext gondermeme ve private-directory enrollment contract'i;
  fiziksel Android'de pinli TLS/WSS, negatif OTP, rate-limit, refresh rotation,
  encrypted persistence, logout revoke/clear ve relogin.
- Contacts tests: 3072-bit blind-RSA capraz protokol, sabit 256 cover batch,
  public-key ID dogrulama, token-sealed snapshot, local-only identity cozumleme,
  registered eslesme persistence, stale cleanup, permission denial ve grup
  olusturma.
- Media tests: outgoing offer/answer/ICE/active/hangup ve call-log, incoming ICE buffer/accept/answer, grup coordinator fanout/mesh peer kurulumu, kabul oncesi grup offer buffer/replay, sifreli chunk round-trip, siradan bagimsiz birlestirme, caption metadata, ciphertext tamper reddi, medya metadata/path temizleme, incoming/outgoing DAO persistence ve sahte Janus VideoRoom sunucusuyla auth/create/attach/join/publish/subscribe akisi.
- Background tests: custom weekday hesaplama, one-off silme, daily reschedule, encrypted storage sizinti kontrolu, offline timer flush ve sender-key distribution-before-commit.
- Incoming/push tests: decrypt/dedup/receipt, group metadata cozumleme, edit/delete/reaction/timer, metadata-only push token register/refresh/unregister.
- Poll/chat tests: sema limitleri, tekli/coklu toggle, normal encrypted create, ciphertext vote, incoming voter-list guncellemesi ve delivery rollback.
- Message interaction tests: edit suresi/yetkisi, reply metadata, local/herkesten silme, retry fanout, emoji-voter reaction semasi, incoming reaction kaldirma ve admin kontrollu pin.
- Voice-note tests: surumlu metadata/limit reddi, mikrofon backend yasam dongusu, amplitude normalizasyonu, pause/resume, encrypted caption/chunk, giden ve gelen VOICE_NOTE DAO persistence.
- Lifecycle tests: persisted-session resume connect, online/offline presence sirasi, last-seen gizleme, idempotent event, maintenance/push refresh ve logged-out no-network davranisi.
- Settings tests: encrypted tercih persistence, canli presence gizlilik guncellemesi, global planli mesaj cancel/reschedule, profil gorseli retain/remove ve tam ekran platform controller davranisi.
- Account-data tests: local logout/tam encrypted-store cleanup, server reddinde yerel veriyi koruma ve server onayi sonrasinda credential/dosya/veritabani silme.
- Notification tests: decrypt-sonrasi event, privacy sender/content/payload redaksiyonu, mute/mention/global sound onceligi ve foreground active-chat bastirma.
- Chat-access tests: acik sohbet icin prompt atlama, kilitli sohbet owner-check basarisi ve platform hatasinda fail-closed davranis.
- Call-readiness tests: granted/not-applicable normalizasyonu, bilinmeyen/denied fail-safe state ve native ayar aksiyonu delegation.
- Conversation-management tests: encrypted DAO archive/pin/favorite/manual-unread persistence, plaintext sizmama, conversation+message scoped delete ve case-insensitive newest-first global mesaj aramasi.
- Message-forwarding tests: hedef basina yeni message ID/AEAD envelope, reply/ciphertext tasimama, coklu secimde sira/tip koruma ve poll vote sifirlama, tek-gosterim fail-closed ve medya byte'larini yeni encrypted chunk transferi olarak gonderme.
- Read-receipt tests: eszamanli sohbet-acma callback'lerinde tek READ receipt, outgoing mesaja dokunmama ve acik sohbete sonradan gelen mesaji ayrica okundu bildirme.
- Backup/export tests: PBKDF2+AES-GCM authenticate/tamper, tam snapshot restore, hesap eslesmesi, bes deneme silme, admin policy fanout, export content ve admin-only encrypted audit.
- Group/chat/storage tests: admin/non-admin mutation, incoming group authorization/system events, leave/archive, chat-info filtre/timer, auto-download matrix, disk-size analizi ve text-preserving media cleanup.
- Android debug build: `CI=true BOT=true /tmp/flutter-sdk/bin/flutter --no-version-check --suppress-analytics build apk --debug`
  - Sonuc: basarili.
  - APK: `build/app/outputs/flutter-apk/app-debug.apk`
  - Son build yeni Flutter pluginleriyle basarili; `android-35`, Gradle/JNI/plugin cache'leri olustu.
- Offline pub cache dogrulama: `CI=true BOT=true /tmp/flutter-sdk/bin/flutter --no-version-check --suppress-analytics pub get --offline`
  - Sonuc: basarili.
- Android release build: `CI=true BOT=true /tmp/flutter-sdk/bin/flutter --no-version-check --suppress-analytics build apk --release`
  - Sonuc: basarili; `build/app/outputs/flutter-apk/app-release.apk` olustu.
  - Bu APK yerel release signing yapilandirmasi verilmedigi icin dagitim imzali magaza artefakti olarak kabul edilmemelidir.
- Offline Android build dogrulama: `cd android && ./gradlew assembleDebug --offline`
  - Sonuc: ayarlar modulu dahil tam test paketi sonrasinda 1:1/grup WebRTC, Firebase push, FilePicker/ImagePicker, ses kayit/oynatma, lifecycle/presence, Telecom, WorkManager, yedek, export, grup yonetimi, onboarding, toplu mesaj, medya onizleme, TLS pinning, anket ve mesaj etkilesimi degisiklikleriyle basarili.
  - Son offline debug Gradle sonucu: 496 gorev, BUILD SUCCESSFUL.
- Offline Android release dogrulama: `cd android && ./gradlew assembleRelease --offline`
  - Sonuc: 663 gorev, BUILD SUCCESSFUL; release engine/ABI artefactlarinin air-gapped cache'te oldugu dogrulandi.
- Tam Flutter test sonucu: 219/219 basarili; `flutter analyze` temiz. Saf-Dart
  smoke, offline `pub get`, 663 gorevli offline Android release, audited AAB ve
  hardened signaling+bot PostgreSQL entegrasyon testleri de basarili.
- Fiziksel Android sohbet/rehber/grup turu reply, edit, delete, reaction, star,
  pin, poll, forward, search, archive, mute, private contact korelasyonu, grup
  uye/admin/duyuru politikasini gercek encrypted DAO ve production servisleri
  ile gecti. Wire ve disk plaintext sizintisi ile close/reopen persistence ayni
  turda assert edildi.
- Fiziksel Android medya turunda dokuz encrypted file chunk ters sirada
  birlestirildi; private manifest ve wire metadata minimizasyonu dogrulandi.
  Iki gercek `WebRtcMediaEngine` audio offer/answer/trickle ICE ile `connected`
  oldu ve remote stream'leri acildi. Media preview caption/view-once typed
  sonucunu cihaz UI'inda geri dondurdu.
- Fiziksel Android background/veri turunda encrypted planli mesaj ve offline
  timer flush, tam `.elbk` backup/restore, admin-only encrypted export audit,
  auto-download/storage cleanup ve server-onayli hesap silme ayni gercek DAO
  yasam dongusunde gecti. Son adim token/session, plan, tum DB satirlari ile
  yonetilen media/backup dizinlerini temizledi.
- Ana Kotlin Android derlemesi onceki incelemede gecmisti: `:app:compileDevDebugKotlin`.

## 2026-08-18 Cihaz, UI ve Release Kapanislari

- Email OTP'de native transport ayrintisinin UI'a sizdigi yol
  `AuthApiException.network` sinifina map edildi. ADB reverse Android tarafinda
  bir Wi-Fi/mobile transport olusturmadigi icin yalniz non-product ve tum
  endpoint'ler loopback oldugunda debug transport istisnasi eklendi. Release
  network policy'si degismedi; HTTPS/WSS ve iki SPKI pin fail-closed kalir.
- Launch/onboarding/permission sayfalari system bottom inset'ini CTA ve page
  indicator icin ayri tuketir. Bu degisiklik, Samsung navigation bar'in son
  sayfa butonlarini kapatmasini onler; iOS ayni kodda home-indicator safe-area
  degerini kullanir.
- Sohbet composer'i tek dar kapsayicidan ayri input glass yuzeyi ile baglamsal
  mic/send butonuna ayrildi. Amaç metin alanini buyutmek, klavye acikken alt
  inset'i korumak ve view-once kontrolune 48 dp erisilebilir hedef vermektir.
- Notification tap, Flutter navigator kurulmadan once gelirse pending tutulup
  ilk uygun frame'de acilir. Killed-process mesaj bildirimi fiziksel cihazda
  yeni process ve hedef sohbet route'u ile dogrulandi.
- WorkManager periodic is, process kapaliyken Android JobScheduler ile
  force-run edildi; `SystemJobService` prosesi baslatti, worker `SUCCESS`
  dondu ve yeniden planlandi.
- Compose `OngoingCallBar` artik `ongoing_call_bar.dart` ile uygulama route
  agacinin ustundedir. Connecting/active/reconnecting durumlarini gosterir,
  call route'unda gizlenir ve native `open/answer` aksiyonlarini call screen'e
  tasir.
- Android incoming/ongoing call notification'i tek `id=1200` uzerinde gercek
  `NotificationCompat.CallStyle` kullanir. Android 14 ongoing CallStyle'i normal
  notification olarak reddettigi icin `SecureChatCallService` eklendi ve
  `FOREGROUND_SERVICE_TYPE_PHONE_CALL` ile startForeground yapildi. iOS'ta bu
  servis yoktur; mevcut CallKit `CXProvider/CXCallController` yolu korunur.
- Kotlin Haptic yardimcisinin kullanildigi mesaj gonderme, mesaj uzun basma,
  conversation swipe `%50` esigi ve aktif call controls noktalarina Flutter
  `HapticFeedback` adapter'i eklendi.
- Hardened Android scriptindeki `flutter build ... --no-pub`, Flutter 3.44 release
  registrant uretimini atlayip test-only `IntegrationTestPlugin` sinifini
  kaynak registrant'ta birakiyordu. `--no-pub` kaldirildi; offline `pub get`
  once yapildigi icin dependency cache kullanilirken release tooling yeniden
  uretilir ve dev plugin teslim DEX'ine girmez.
- AndroidX Core eklemesinin cozumledigi iki Google `.module` dosyasinin
  incelenen SHA-256 degeri Gradle verification metadata'sina eklendi. Supply
  chain kapisi gevsetilmedi; yalniz iki eksik artefakt allow-list'e alindi.
- Son hardened AAB 18 stripped native library, obfuscated Dart/R8 mapping,
  credential/private-key/server-secret taramasi ve API 33 release negatif
  cihaz turundan gecti. Dagitim imzasi veya private symbol dosyalari kaynak
  Git'e konmaz.

Platform sapmalarinin tek tablosu ve her sapmanin nedeni
`docs/IOS_PLATFORM_DIFFERENCES.md` icinde tutulur.

## Offline Bundle Plani

Bundle icerigi:

- Bundle dizini: `build/offline_bundle`
- Toplam boyut: final paketleme tamamlandiginda checksum manifestinde kaydedilecek
- Flutter SDK cache: `/tmp/flutter-sdk`
- Dart SDK cache
- `flutter_securechat/pubspec.lock`
- Pub cache (`PUB_CACHE`) ve gerekiyorsa hosted package tarball'lari
- Android Gradle wrapper/cache ve mevcut `local-repo`
- Android SDK build subset'i: `platforms/android-34` (Firebase plugin compile SDK), `platforms/android-35`, `platforms/android-36`, `build-tools/36.0.0`, `ndk/28.2.13676358`, `licenses`
- Bu ortamda uretilen debug ve unsigned release APK

Android bundle farkli bir gecici kok dizine tamamen acilarak dogrulandi. Bundle
disindaki `~/.pub-cache`, `~/.gradle` veya Android SDK kullanilmadan
`pub get --offline`, analyze, 136 test ve sifir build dizininde birlikte
`assembleDebug assembleRelease --offline` gecti (1140 gorev). Ilk restore'un
yakaladigi Firebase `android-34` platform ihtiyaci final SDK arsivine eklendi.

Onemli platform siniri: `flutter_sdk.tar.gz` Linux host icindir ve macOS'ta
calismaz. iOS air-gapped teslimi icin ayni Flutter surumunun macOS/Apple Silicon
SDK'si, iOS engine artefactlari, Xcode ve SwiftPM package cache'i Mac uzerinde
hazirlanmalidir. Kaynak iOS targeti, CallKit/native bridge ve SPM proje
referanslari bundle'dadir; fiziksel build/signing kaniti ve macOS cache
supplement'i `docs/MACOS_IOS_BUILD.md` akisiyla Mac sunucuda tamamlanacak.
