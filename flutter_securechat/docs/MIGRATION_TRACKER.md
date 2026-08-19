# Kotlin -> Flutter Migration Tracker

Bu dosya tasimanin tek ilerleme kaynagidir. Calisma ve kalite kurallari
`AUTONOMOUS_MIGRATION_PLAYBOOK.md` icindedir. `MIGRATION_NOTES.md` kararlarin
ayrintisini, `FEATURE_MAP.md` kullaniciya donuk ozetini, `SOURCE_AUDIT.md` ise
271 Kotlin/Java kaynaginin tek tek production karsiligini tutar.

Mevcut Kotlin kaynak agaci davranis referansidir ve tasima boyunca
degistirilmez. Yeni ortak uygulama yalniz `flutter_securechat/` altinda
gelistirilir.

## Degistirilemez Ana Oncelik: Gizlilik

Gizlilik bir sonraki faza birakilacak iyilestirme degil, her modül icin
baglayici release kapisidir. Bir ozellik Kotlin davranisini kopyalasa bile
asagidaki sinirlardan birini bozuyorsa tamamlanmis sayilmaz:

1. Mesaj, medya, dosya metadata'si, grup adi/kimligi, rehber eslesmesi,
   sosyal grafik veya davranis zaman cizelgesi sunucuda kalici tutulmaz.
2. Direct ve grup mesajlarinda Signal encryption/session/prekey hatasi
   `FAILED` sonucudur. Plaintext, local-AES peer-wire veya eski zayif protokol
   fallback'i yoktur.
3. Grup route metadata'si ve chat-control olayi recipient-specific direct
   Signal zarfinin icindedir. Sunucu toplu alici listesi, sabit grup tokeni,
   kontrol turu veya mesaj kimligi gormez.
4. Offline teslim yalniz zaten E2EE olan zarf icindir; ayri server AEAD,
   opaque Redis key, sert kisa TTL ve ACK sonrasi silme kullanir. Redis RDB/AOF
   aciksa servis fail-closed baslar.
5. Sunucu loglari ve metrikleri ham UUID, telefon, e-posta, IP, token,
   envelope, grup/dosya adi veya request body tasimaz. Kimliksiz RAM sayaclari
   kalici davranissal audit satirinin yerine kullanilir.
6. Mobil bundle'a server secret, signing private key, OPRF private key veya
   production credential girmez. Endpoint ve wire semasi sir kabul edilmez;
   asil guven siniri E2EE, server authorization ve rate limit'tir.
7. Kalici server verisi yalniz protokolun zorunlu minimumudur; retention ve
   hesap silme tum PostgreSQL, Redis, process cache, push ve bot kopyalarini
   kapsar.
8. Privacy storage/migration/retention sagligi bozulursa eski semaya veya
   daha zayif kayda donulmez; HTTP/WS trafik fail-closed reddedilir.

Production icin yalniz `server_hardened` hedefi kabul edilir. Kok Kotlin
`signaling-server` davranis referansidir ve production privacy artefakti
degildir.

### Zorunlu minimum server persistence

| Veri | Kalici bicim | Neden | Sinir |
|---|---|---|---|
| Hesap adresi | Rastgele UUID + finalized blind-RSA OPRF directory token/key ID | JWT subject ve prekey adresleme | Hesap silmede transaction icinde silinir |
| Signal public key materyali | Public identity, tek signed prekey, kullanilmamis one-time public prekey | Yeni E2EE session kurma | OTPK atomik teslimde hemen silinir |
| Push token | User blind index + AAD-bagli AES-GCM token + gun bucket | Generic wake-up | Varsayilan 30 gun, sert ust sinir 90 gun |
| Opsiyonel bot policy/credential | Blind index veya master-key AEAD | Yetkilendirilmis bot istemcisi | Revoke/expiry ve 30/90 gun retention |

Mesaj gecmisi, medya, rehber listesi/eslesmesi, grup uyeligi/adi, private Signal
key, exact last-seen ve behavioral audit bu tabloda yoktur ve eklenemez. Canli
route icin kaynak IP, zamanlama, trafik hacmi ve sender/recipient iliskisinin
process tarafindan gorulebildigi gercegi saklanmaz; E2EE trafik analizini tek
basina cozmeye yetmez. Ayrintili tehdit modeli
`SERVER_DATA_PRIVACY_AUDIT.md` icindedir.

## Tamamlanma Kurali

Bir modül ancak asagidakilerin tamami varsa `DONE` olur:

1. Kotlin kaynaklarindaki basari, hata, timeout, iptal, retry, restart ve veri
   sozlesmeleri dosya seviyesinde eslenmistir.
2. Flutter karsiligi `lib/main.dart` production graph'indan erisilir ve dogrudan
   production caller'i vardir; yalniz testte duran kod kapanis sayilmaz.
3. Bos callback, demo-only production yolu, TODO/FIXME,
   `UnsupportedError`/`UnimplementedError`, sessiz no-op veya plaintext fallback
   yoktur.
4. UI gercek application/service state'ine baglidir; feature katmani dogrudan
   HTTP, crypto, database veya native plugin detayina baglanmaz.
5. Android ve iOS farklari gercek native uygulama veya dogru, testli platform
   kisiti olarak ele alinmistir.
6. Veri/wire parity gereken yerde Kotlin fixture veya source contract ile
   capraz test vardir.
7. Privacy ve security invariant'lari fail-closed test edilir.
8. Analyze, tam Flutter test paketi, ilgili native/statik audit, hardened server
   testleri ve riskle orantili offline build kapilari gecer.
9. Degisiklik, sapma, retention ve kalan dis gereksinim belgelenmistir.

Durumlar: `DONE`, `IN PROGRESS`, `OPEN`, `EXTERNAL BLOCKER`.

`EXTERNAL BLOCKER`, kodda placeholder oldugu anlamina gelmez; Apple hesabi,
fiziksel cihaz, gercek push saglayicisi, fiziksel HSM veya macOS/Xcode gibi bu
Linux ortaminda uretilemeyen kanit demektir. Yeni yerel bir gap bulunursa ilgili
`DONE` satiri yeniden `IN PROGRESS` yapilir.

## Kaynak Envanteri ve Son Kanit

- Kotlin/Java uygulama kaynaklari: 271 dosya (`app`, `crypto`, `storage`,
  `network`, `media`, `contacts`).
- Flutter/Dart: 206 dosya; 121 production `lib`, 85 test/integration/tool.
- Source audit: 271/271; `PLATFORM=28`, `MERGED=64`, `COVERED=175`,
  `DECISION=4`, `GAP=0`.
- Her `lib/...` audit hedefi `lib/main.dart` import graph'indan erisilir; direct
  production caller ve davranis/gizlilik invariant'i generator/test ile
  zorunludur.
- Kotlin kataloglari: 167 TR, 167 EN, 21 DE, 21 AR anahtar; Flutter katalog ve
  fallback/RTL testleriyle korunur.
- Flutter: 233/233 host testi, temiz `flutter analyze --no-pub`, saf-Dart
  smoke, offline `pub get` ve iOS statik readiness audit basarili. Dort Android
  integration hedefi de fiziksel Samsung SM-S921B cihazda gecti.
- Hardened server: 177/177 `:signaling-server:test :bot-api:test --offline`,
  sifir failure/error/skip; gercek PostgreSQL V1-V18 ve Redis Testcontainers
  kapsami dahil.
- Android offline release: `assembleRelease --offline --no-daemon`, 663 gorev,
  basarili.
- Hardened AAB: `86645886` byte,
  SHA-256 `2d36a8f56327262b815f0e2d253827f47f46129eb49f6ba72f4fb5343faaf85b`.
  Teslim edilen 18 native library stripped; server secret/signing material
  taramasi temiz.
- Unsigned release APK: `114596562` byte,
  SHA-256 `e7a5f6c88f1b87018f5ce55f72eec8f6e1adf823130b51176830351d9121a92d`.
  APK'de `BUNDLE-METADATA` yok, native payload stripped ve yasakli server secret
  yok.

AAB Play ingestion icin R8 mapping/native symbol `BUNDLE-METADATA` tasir ve bu
nedenle private release artefaktidir. Bu metadata cihaz split APK'larina
dagitilmaz. Ayrica checksum'li private symbol arsivi
`build/private_symbols/android` altindadir.

## Modül Durumlari

| Sira | Modül | Durum | Kapanis kaniti / kalan dis is |
|---:|---|---|---|
| 1 | Proje iskeleti, tema, navigation | DONE | Android/iOS Flutter targetlari, Azure tema ve route agaci production composition'da. |
| 2 | Domain modelleri ve signaling codec | DONE | Mesaj, presence, prekey, dosya, SDP/ICE, SFU ve grup arama union tipleri round-trip testli. |
| 3 | Encrypted storage DAO katmani | DONE | Kotlin entity/DAO gruplari authenticated encrypted snapshot DB'de kalici; plaintext sizinti ve atomik yazma testli. |
| 4 | Auth, OTP, session ve token rotation | DONE | E-posta OTP, register, refresh rotation, prekey upload, encrypted session, logout ve account delete gercek endpoint akislariyla testli. |
| 5 | Rehber ve private discovery | CODE DONE / DEPLOY BLOCKED | Android ContactsContract/iOS Contacts, 3072-bit blind-RSA OPRF, tam 256 cover batch, sealed snapshot ve stale cleanup testli; server sosyal grafik tutmaz. 2026-08-17 fiziksel Android denemesinde canlı `GET /api/v1/directory/config` rotası HTTP 404 verdiği için production discovery, hardened server deploy edilene kadar kapalıdır. İstemci eski/hash tabanlı fallback yapmaz ve cached local eşleşmeleri silmez. |
| 6 | Mesaj gonderim ve incoming pipeline | DONE | Direct/group Signal, retry/status, decrypt/dedup/receipt ve authenticated control handler; encryption hatasinda plaintext fallback yok. |
| 7 | Offline queue ve network resilience | DONE | Kuyruk yalniz encrypted wire zarfini alir; ordered flush, stuck recovery, reconnect ve TLS/SPKI primary/backup pin testli. |
| 8 | Medya, dosya ve sesli mesaj | DONE | Picker/preview, 128 KiB encrypted chunk, out-of-order assembly, view-once, sandbox open/share ve AAC voice note testli. |
| 9 | 1:1 ve grup WebRTC/Janus | DONE | Dinamik ICE/TURN, SDP/ICE, mesh/SFU, controls, renderer, call log, reconnect ve hata akislari bagli. |
| 10 | Telecom/CallKit ve call readiness | DONE | Android self-managed Telecom, Android 12+ CallStyle/phone-call foreground service, iOS CallKit ve uygulama geneli devam eden arama bandi ayni Dart state machine'e bagli; native aksiyonlar testli. |
| 11 | Push ve yerel bildirim | DONE | FCM/APNs generic metadata-only wake, decrypt-sonrasi redacted local notification, mute/mention ve active-chat suppression testli. |
| 12 | Background, planli mesaj ve lifecycle | DONE | WorkManager/BGTask, foreground catch-up, timer flush, sender-key rotation, expiry cleanup ve presence testli. |
| 13 | Grup/kisi bilgisi ve yonetim | DONE | 256 uye, admin/yetki, duyuru/export/timer/mute/lock/leave davranislari incoming authorization ile testli. |
| 14 | Backup, restore, export ve admin audit | DONE | PBKDF2+AES-GCM `.elbk`, hesap kontrolu, atomik restore, deneme limiti ve sadece cihazda encrypted admin audit testli. |
| 15 | Ayarlar, veri temizleme ve depolama | DONE | Encrypted tercihler, profil, auto-download, storage analizi/scoped cleanup ve server-onayli hesap silme testli. |
| 16 | Sohbet listesi ve mesaj etkilesimleri | DONE | Archive/pin/favorite/unread/delete, reply/edit/delete/reaction/star/pin/poll production DAO ve E2EE akislariyla testli. |
| 17 | Guvenli coklu mesaj iletme | DONE | Coklu secim, yeni ID/AEAD, medya re-transfer, poll reset ve view-once fail-closed testli. |
| 18 | READ receipt ve mesaj bilgisi | DONE | Duplicate-safe receipt, acik-sohbete sonradan gelen mesaj ve aggregate delivery/read info testli. |
| 19 | Uygulama dili ve localization | DONE | system/tr/en/de/ar kalici secim, Kotlin katalog paritesi, EN fallback ve Arabic RTL testli. |
| 20 | Accessibility ve responsive UI | DONE | Yerellesmis semantics, 48x48 hedefler, safe-area uyumlu onboarding, kullanilabilir sohbet composer'i, %200 kucuk ekran, tablet RTL, klavye aksiyonlari ve WCAG AA matrisi testli. |
| 21 | iOS fiziksel build/runtime | EXTERNAL BLOCKER | Linux'ta Xcode/signing/fiziksel iPhone yok. Kaynak, plist, entitlement beklentileri ve deterministic Mac build scripti hazir; Mac kaniti gerekli. |
| 22 | Signal Protocol V3 wire parity | DONE | Saf-Dart V3 Double Ratchet/SenderKey production yolunda; Kotlin `signal-protocol-java 2.8.1` ile PreKey, ratchet reply, SKDM ve group ciphertext iki yonlu capraz testli. |
| 23 | Room+SQLCipher binary/schema migration | DONE | SQLCipher 4.5.6 salt-okunur exporter, v1-v22 converter, legacy Keystore passphrase, BLOB-preserving atomik import ve Android 13 fixture testli. |
| 24 | Apple PushKit VoIP wake-up | EXTERNAL BLOCKER | Client CallKit ve normal APNs yolu var; `.voip` entitlement/provisioning, gercek token ve APNs server sender'i dis hesap testi gerektirir. |
| 25 | Tam Kotlin/Flutter dosya audit'i | DONE | 271/271 kaynak resolve; production reachability/caller/invariant kapisi, manifest kaydi ve target/test path dogrulamasi gecer. |
| 26 | Final air-gapped bundle | EXTERNAL BLOCKER | Onceki Linux bundle izole restore ve 1140-gorevli offline debug+release ile dogrulandi; son degisikliklerden sonra eski cache arsivi bilincli kaldirildi. Final Android paket ile macOS Flutter/iOS engine/SwiftPM supplement'i Mac kapisinda yeniden checksum'lanacak. |
| 27 | Ktor HTTP/WebSocket contract parity | DONE | Privacy daraltmalari sonrasi 22/22 route karari ve 33/33 Signal discriminator generator ile sabit; legacy phone resolver yok. |
| 28 | Android Play/reverse-engineering hardening | DONE | R8/resource shrinking, AOT obfuscation, split debug info, no-backup/no-cleartext ve release HTTPS/WSS fail-fast; 18 native library stripped, AAB/APK privacy audit ve API 33 release cihaz kapisi gecer. |
| 29 | Clean architecture ve production composition | DONE | Production/test graph ayrik; demo/circular dependency/duplicate recovery yok; UI low-level plugin/DAO sinirini gecmiyor; mimari guard testli. |
| 30 | Async state machine ve resource ownership | DONE | Owned async tracker, keyed receive serialization, deterministic idle ve dispose-drain; socket/timer/renderer/recorder tum terminal yollarda kapanir. |
| 31 | iOS statik build-readiness | DONE | Swift-Dart channel, Info.plist, Background Modes, URL/file/privacy, Firebase uyumlu iOS 15 deployment target, plugin ve entitlement sozlesmesi fail-fast auditli; fiziksel kanit satir 21'de. |
| 32 | Dependency, lisans ve supply chain | DONE | 129 hosted Pub SHA-256 lock, exact direct surumler, iki wrapper checksum'i, Android 1.243 ve server 544 component verification, allow-list repository ve vendored audioswitch testli. |
| 33 | Son davranissal diferansiyel/release gate | DONE | 271 caller/invariant auditi, 233 Flutter testi, iOS/Codemagic static audit, 177 hardened server testi, offline Android release ve audited AAB birlikte gecer. |
| 34 | Server veri minimizasyonu/metadata gizliligi | DONE | V1-V14 kalici grup/audit/prekey timeline/raw UUID kolonlarini siler; short-lived queue AEAD+opaque RAM, retention fail-closed, private group/control routing ve hesap silme testli. |
| 35 | Private discovery production key/ownership kapanisi | EXTERNAL BLOCKER | Kodda zayif fallback yok; OPRF ve no-fallback PKCS#11/HSM backend testli. Fiziksel HSM tatbikati ile ilk telefon sahipligi icin privacy-reviewed SMS/voice veya high-entropy invite/QR capability urun karari dis servis/donanim gerektirir. |
| 36 | Operational log/backup metadata minimizasyonu | DONE | Disk/rotation appender'lari kaldirildi; fixed ERROR console Docker `logging=none` ile atilir. Secret-file ve purpose separation, non-root/read-only/core-dump kapali image, ephemeral Redis, immutable image digest, PostgreSQL verify-full TLS ve varsayilan non-mutating deploy preflight'i statik+Kotlin testleriyle sabit. |
| 37 | Hardened server production deployment kaniti | EXTERNAL BLOCKER | Source, offline JVM artefaktlari, compose parse ve preflight tamam. 2026-08-17 canli probe `https://94.73.180.226/api/v1/directory/config` icin HTTP 404 kanitladi; dolayisiyla calisan production image halen hardened contract degildir. Private registry'ye push edilmis digest image'lar; gercek encrypted/verify-full PostgreSQL, secret manager, no-swap/no-snapshot Redis host ve backup retention/account-delete tatbikati production altyapisinda kanitlanmali. Mutable tag veya legacy-route fallback yok. |

## Ayrintili Kapanis Matrisleri

### Kripto, storage ve veri omru

- [x] Peer content icin Signal V3; device-local storage/session wrapping icin
  Keystore/Keychain destekli AES-GCM + HKDF. Iki amac birbirine fallback olmaz.
- [x] Identity, prekey, signed prekey, session ve sender-key kayitlari encrypted
  DAO'da kalicidir; migration state byte-for-byte korunur.
- [x] SenderKey distribution direct Signal session icinden asil group
  ciphertext'ten once gider; yedi gunluk rotation state'i background ve
  foreground catch-up ile uzlastirilir.
- [x] Dosya metadata'si authenticated private manifesttedir; temp/final path
  app sandbox'ina sinirli, path traversal ve partial/tamper fail-closed.
- [x] Backup password'u saklanmaz; PBKDF2 parametreleri, GZIP ve AES-GCM auth
  Kotlin format uyumluluguyla dogrulanir.
- [x] Hesap silme server onayi olmadan local retry state'ini yok etmez; onaydan
  sonra credential, database ve sandbox file'lari atomik cleanup planina girer.

### Network ve server privacy

- [x] Tum HTTP/WS/Janus baglantilari ayni TLS/SPKI primary+backup pin
  politikasina bagli; release config eksiginde bootstrap fail-fast.
- [x] Auth subject/user ID eslesmesi, sender override, frame limiti, rate limit,
  token type/rotation ve server shutdown backoff testli.
- [x] `GROUPROUTE:v3` ve `flutter-file-v3-group` her aliciya ayri direct Signal
  zarfidir; hardened server `group_message_fanout` ve plaintext legacy
  chat-control frame'lerini reddeder.
- [x] `CHATCTRL:v2` edit/delete/reaction/pin/receipt/typing/timer detayini
  rastgele padded sabit 16 KiB encrypted paket icinde tutar.
- [x] Push provider yalniz `type=securechat_wake_v2` gorur; sender, recipient,
  message type, text, group ve exact time payload'da yoktur.
- [x] Private discovery server'a address-book SHA-256 listesi gondermez; blind
  OPRF + cover batch + locally opened sealed snapshot kullanir.
- [x] PostgreSQL final schema testi izinli tablo/kolon setini birebir kilitler;
  tamamlanmamis privacy migration veri silmek veya fallback yapmak yerine
  startup'i durdurur.

### Platform, medya ve UX

- [x] Android `FLAG_SECURE`; iOS'un OS kisiti nedeniyle app-switcher blur ve
  screenshot event/uyari uygulanir. iOS'ta gercek screenshot bloklama iddia
  edilmez.
- [x] Android Telecom ve iOS CallKit action'lari Dart call state machine ile
  iki yonlu senkronizedir; native callback route bypass edemez.
- [x] iOS background WebSocket'e guvenilmez; generic push + foreground
  reconnect kullanilir. BGTask exact-time garantisi vermedigi icin foreground
  catch-up server timestamp ile tamamlanir.
- [x] Contacts, camera, microphone, Photos/file picker ve notification izinleri
  kullanici aksiyonunda ve platform-native bridge uzerinden istenir.
- [x] Biometric/owner-check locked chat route, notification ve deep route
  girislerinde fail-closed calisir.
- [x] Debug notification receiver/harness yalniz debug source setindedir ve
  release manifest/APK'da yoktur.

### Clean code, test ve supply chain

- [x] Presentation -> application/domain -> repository/service -> platform
  yonu guard testleriyle korunur; composition root disinda global runtime
  kurulmaz.
- [x] Feature UI dogrudan HTTP, database, crypto veya native channel import
  etmez; typed interface/application service kullanir.
- [x] Fire-and-forget islemler sahipli tracker'a kayitlidir; test ve dispose
  siniri deterministiktir.
- [x] Pub direct surumleri exact, lock SHA-256'li; Gradle byte verification
  metadata fail-closed ve repository kaynaklari allow-list'tir.
- [x] WebRTC audioswitch AAR/POM reviewed local Maven artefakti ve lisansiyla
  vendoredir; GPL-3.0 Signal dagitim yukumlulugu release dokumaninda aciktir.
- [x] Release AAB otomatik stripped/native section, R8 mapping/private symbol,
  credential ve server-secret auditinden gecmeden build betigi basarili donmez.

## Acik Dis Kapanis Kapilari

Yerel `OPEN` veya `IN PROGRESS` modül kalmamistir. Asagidaki kanitlar gercek
dis ortamda tamamlanmadan genel release "tamamlandi" denmez:

1. macOS/Xcode'da deterministic SwiftPM lock ile simulator, no-codesign device,
   imzali fiziksel iPhone ve offline cache turu (`21`).
2. Apple App ID/entitlement ile gercek PushKit `.voip` token rotation ve kapali
   uygulama gelen arama testi (`24`).
3. Son kaynakla Android cache bundle ve Mac Flutter/iOS engine/SwiftPM
   supplement'inin tek SHA-256 manifestle yeniden uretilmesi (`26`).
4. Export edilemeyen, rate-limited gercek PKCS#11 HSM/KMS uzerinde OPRF key
   rotation/failover tatbikati; ilk telefon sahipligi icin privacy-reviewed
   SMS/voice ya da invite/QR capability politikasinin secilmesi (`35`).
5. Hardened image'larin private registry'de digest ile yayinlanmasi; gercek
   PostgreSQL TLS/disk/backup-retention, secret manager ve Redis host
   no-swap/no-snapshot politikasinin deployment tatbikati (`37`).

## Son Calisma Kaydi - 2026-08-15

- 271 kaynak audit generator'u import graph reachability, direct production
  caller ve davranis/privacy invariant'i zorunlu hale getirildi.
- Son diferansiyel gate 6 fail-fast kontrolle source set, caller graph,
  decision set, placeholder/no-op taramasi, no-plaintext send ve Android release
  privacy contract'ini kilitledi.
- Flutter test tabani 191/191'e, hardened server 50/50'ye cikarildi; analyze,
  smoke, iOS static audit, offline pub ve offline Android release gecti.
- Hardened AAB gercek teslim payload'indaki 18 native library icin debug section
  ve server-secret taramasindan gecti; private symbol checksum'i dogrulandi.
- Release APK ayrica acilip AAB metadata'sinin cihaza gitmedigi ve native
  payload'in stripped oldugu dogrulandi.

## Son Calisma Kaydi - 2026-08-17

- Hardened signaling ve bot kalici rolling log appender'larindan arindirildi;
  log seviyesi runtime'da acilamaz ve production compose log driver'i
  `none`'dir. Health ile bearer-korumali kimliksiz aggregate RAM metrikleri
  operasyonel sinir olarak kalir.
- Tum server secret'lari `NAME_FILE` read-only dosya sinirina alindi; symlink,
  bos/asiri buyuk dosya, direct+file cakismasi ve amaclar arasi ayni materyal
  kullanimi fail-closed reddedilir.
- Hardened image/compose hedefi non-root, read-only, `cap_drop=ALL`, core/heap
  dump ve attach kapali; Redis volume/RDB/AOF olmadan tmpfs'te calisir. Root
  `infra/docker-compose.yml` production hedefi degildir.
- `deploy_privacy_stack.sh` uc image'i de registry digest'iyle, secret dosya
  izinlerini, secret tekrarini ve `sslmode=verify-full` PostgreSQL URL'sini
  dogrular; varsayilan `--check-only` container degistirmez, `--apply` acik
  operator onayi ister.
- Compose atlansa bile signaling/bot binary production modu, verify-full DB
  TLS, plaintext queue reddi, PKCS#11 OPRF, SMTP/Janus transportu ve private bot
  socket sinirini listener'dan once uygular.
- 194/194 Flutter ve 64/64 hardened server testi, temiz analyze, shell/compose
  parse, olumlu+olumsuz deployment preflight ve statik privacy audit gecti.
  Signaling fat JAR (`69249175` byte, SHA-256
  `ffbe8f60abc4fb6b067c3bb47acf49235b94d55816588097e440f0347702ab52`) ile
  bot installDist (`78` library; sirali file-hash manifest SHA-256
  `c49cdcba25b23684848d68320ea24b2fe64dcd2a1f4c0701ebee3cd1469e58dc`)
  offline uretildi. Resmi JRE image pull'u registry I/O timeout'u nedeniyle bu
  Linux turunda tamamlanamadi; source/artefakt kapanisini etkilemez, gercek
  registry image digest/push kaniti deployment operator kapisinda kalir.
- Final offline bundle eski cache'in guncel release'i temsil etmemesi nedeniyle
  teslim edilebilir sayilmadi; Mac supplement'iyle final kapida yeniden
  uretilmek uzere bos birakildi.

## Son Calisma Kaydi - 2026-08-18

- Android 12+ gelen/devam eden arama bildirimi ayni sabit notification ID ile
  CallStyle'a tasindi; ongoing durum gercek `phoneCall` foreground service ile
  Android 14 kurallarina uyarlandi. Kabul, reddet, kapat ve bildirime dokunma
  aksiyonlari Dart call state machine'e geri iletilir.
- Uygulama geneli devam eden arama bandi, grup remote-end kapanisi ve Kotlin
  haptic davranislari production caller ve widget/source testleriyle kapatildi.
- Onboarding safe-area yerlesimi ve sohbet input/composer'i 320x568, yuzde 200
  yazi olcegi ve fiziksel klavye/nav-bar kosullarinda duzeltildi.
- Process-kill sonrasi WorkManager, notification cold start, CallStyle lifecycle
  ve release guvenlik akislari cihazda dogrulandi. API 33 release AVD'de
  `debuggable=false`, `FLAG_SECURE`, no-backup/no-cleartext ve debug harness
  yoklugu ayrica kanitlandi.
- Flutter 3.44.9 ile 233/233 test, temiz analyze, 271/271 source audit,
  iOS readiness ve Codemagic privacy audit gecti. Kok `codemagic.yaml`, macOS
  no-codesign verification ve ayri signed-candidate workflow'u ile hazirlandi.
- Codemagic/Xcode 26, Firebase Swift package urunlerinin minimum iOS 15
  gereksinimini gercek device release compile'da kanitladi. Runner'in Debug,
  Release ve Profile target'lari 15.0'a birlikte yukseltildi; audit eski 14.0
  veya karisik deployment target'i fail-closed reddeder.
