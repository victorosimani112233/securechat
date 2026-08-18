# SecureChat Kotlin -> Flutter Feature Map

## Tasindi veya Iskeleti Hazir

| Ozellik | Flutter Durumu | Not |
|---|---|---|
| Auth / telefon girisi | Calisiyor | E-posta OTP request/verify, server register, access+refresh token rotation ve prekey upload gercek endpoint sozlesmesine bagli. Rehber listesi registration'a girmez; V13 DB finalized private-directory OPRF tokeni tutar. |
| Sohbet listesi | Hazir | Arama/filtre, arşiv görünümü, swipe arşiv/sil, uzun-bas pin/favori/okundu, kilit/mute/unread durumlari encrypted repository'ye bagli. |
| Chat ekrani | Ilerledi | Mesaj baloncuklari/status ikonlari ve production send yolu storage -> encrypt -> signaling -> retry/status zincirine bagli. Arama, kalici mute, onayli lokal temizleme, anket olusturma/oylama, yanitlama, hedef aramali guvenli iletme, duzenleme, silme, reaction, yildiz ve pin; sesli-goruntulu arama ve tam medya secim/onizleme/gonderim akisi baglandi. |
| Rehber | Kod hazir; canli server deploy bekliyor | Android ContactsContract ve iOS Contacts.framework bridge, 3072-bit blind-RSA OPRF, tam 256 cover batch, token-sealed snapshot, stale cleanup, telefon arama ve kalici grup olusturma eklendi. Server rehber hash'lerini/eslesme sosyal grafigini tutmaz; bilinmeyen UUID'nin kimlik zenginlestirmesi yalniz cihazdadir. Canli server 2026-08-17 tarihinde config rotasina 404 dondu; istemci gizlilik icin legacy fallback yapmadan cached local sonucu korur ve kontrollu durum gosterir. |
| Arama UI | Hazir | Gercek CallManager state'i, local/remote RTC renderer, sure, mute/speaker/camera/switch, accept/reject/end ve encrypted call history bagli. Grup aramasinda local + katilimci renderer grid'i ve mesh/SFU durumu gosterilir. |
| Arama hazirlik ekrani | Hazir | Android Doze/full-screen-intent/notification/overlay gercek durum+ayar intentleri; iOS notification status ve acik platform siniri bagli. |
| Ayarlar | Hazir | Sistem/acik/koyu tema, encrypted bildirim/gizlilik/filigran/tam-ekran/planli-mesaj tercihleri, presence guncellemesi, sandbox profil fotografi, atomik cihaz verisi silme ve server-onayli hesap silme gercek servislere bagli. |
| Uygulama dili | Hazir | Kotlin TR/EN 167'ser anahtar kayipsiz ARB'ye aktarildi; system/tr/en/de/ar kalici secim, mevcut DE/AR cevirileri, Ingilizce fallback, Arapca RTL ve tum Flutter feature ekranlarinin katalog baglantisi tamam. |
| Accessibility / responsive | Hazir | Yerellesmis semantik aksiyonlar, 48x48 hedefler, %200 kucuk-telefon, tablet Arapca RTL, auth klavye action ve acik/koyu WCAG AA kontrast matrisi otomatik testli. |
| Theme tokens | Hazir | Compose `AzureTokens` Flutter `ThemeData` olarak tasindi. |
| Domain modelleri | Hazir | `Conversation`, `LocalMessage`, status/type enumlari tasindi. |
| Signaling codec | Hazir | Kotlin `SignalMessage` tipleri: ana mesaj, prekey, audio/video data, dosya, grup, presence, edit/delete/reaction/pin, call control, SDP, SFU ve grup arama lifecycle tipleri eklendi. |
| Signaling client | Hazir | Typed connection state, `/ws?userId=...`, Bearer auth, token refresh, server-shutdown delay, jitter/backoff, sistem ag kaybinda context-korumali disconnect ve Wi-Fi/mobil gecisinde anlik reconnect eklendi. |
| Socket diagnostics | Hazir | Iceriksiz connect/disconnect/failure/reconnect/auth sayaclari ve pinli client ile redacted `/health` + authenticated `/ws` uyumluluk probe'u bagli; token/user/header/body rapora girmez. |
| Crash/non-fatal diagnostics | Hazir | Flutter, platform dispatcher ve root-zone hatalari app-private atomik rapora gider; mesaj/token/icerik yazilmaz, ham ID hashlenir, 20 kayit rotasyonu ve kontrollu paylas/temizle testlidir. |
| TLS/SPKI pinning | Hazir | Auth, discovery, ICE config, push-token HTTP ile signaling/Janus WebSocket ayni primary+backup SPKI politikasini kullanir; TLS config eksiginde bootstrap fail-fast olur ve pinli host proxy uzerinden bypass edilemez. |
| Android Play release sertlestirmesi | Hazir | R8/resource shrinking, Flutter AOT obfuscation, private checksumli symbol arsivi, stripped cihaz native payload'i, server-secret sizinti auditi, SHA-256, no-backup/no-cleartext manifest ve release HTTPS/WSS fail-fast politikasi hardened build betigine bagli. Play ingestion icin map/native symbol tasiyan AAB private tutulur; bu `BUNDLE-METADATA` cihaz split APK'sina teslim edilmez. Endpoint/JSON semasi sir kabul edilmez; yetki Ktor JWT/rate-limit ve Signal E2EE'de kalir. |
| Dependency ve lisans guveni | Hazir | Direct Pub surumleri exact ve 129 hosted paket SHA-256 lock'lidir. Android/server Gradle wrapper + 1.243/544 component verification manifestleri fail-closed; plugin repository'leri settings allow-list'i disina cikamaz. WebRTC audioswitch AAR/POM'u reviewed local Maven artefakti, lisansi uygulama icinde gorunur. Mac SwiftPM lock'i offline build scriptinde zorunludur. |
| Local crypto | Hazir | AES-GCM + HKDF yalniz Keystore/Keychain ile cihaz-ici storage/session wrapping ve call-key icin kullanilir; production peer mesajinda local AES fallback yoktur. |
| Signal Protocol / crypto state | Hazir | GPLv3 Signal V3 Double Ratchet, Curve25519 identity/prekey, TOFU, kalici protobuf session record, SenderKey dagitim/rotation ve Kotlin Java 2.8.1 ile iki yonlu direct/group wire capraz testleri tamam. |
| Local storage | Hazir | Kotlin storage entity/DAO gruplari encrypted `SecureChatDatabase` ile kalicidir. Android APK upgrade'inde Room/SQLCipher v1-v22 DB, Keystore local identity ve tum Signal BLOB'lari atomik/idempotent native importer ile kayipsiz tasinir. |
| Offline queue/recovery | Hazir | Kuyruk yalniz encrypted wire sinyali kabul eder, reconnect'te sirali flush eder; eski SENDING mesajlar timeout sonrasi FAILED olur. |
| Mesaj gonderim use case | Hazir | MSGID/reply/expiry/view-once/mention/poll prefix sirasi, tek encrypt, retry ve no-plaintext-fallback davranisi tasindi. |
| Android screen protection | Native bridge hazir | `FLAG_SECURE` MainActivity icinde etkin. |
| iOS privacy overlay | Native bridge hazir | Screenshot engelleme yerine app switcher mask + screenshot event uygulanir. |
| Kilitli sohbet biyometrisi | Hazir | Android BiometricPrompt + cihaz credential ve iOS LAContext route-seviyesi fail-closed kapida; bildirim/deep route bypass edemez. |
| Sifreli dosya transferi | Hazir | Kamera/galeri/belge picker, 128 KB encrypted chunk, retry/progress, disk tabanli out-of-order assembly, stale cleanup, path traversal korumasi, incoming/outgoing DAO persistence, thumbnail, app-ici goruntuleme, tek-gosterim ve kontrollu native open/share var. |
| 1:1 WebRTC | Hazir | Dinamik ICE/TURN, audio/video capture, SDP/ICE signaling, renderer, reconnect ve medya kontrolleri var. |
| Sistem cagri entegrasyonu | Hazir | Android self-managed Telecom ConnectionService ve iOS CallKit CXProvider ayni Dart state machine'e bagli. |
| Grup WebRTC/Janus | Hazir | Ortak local stream, katilimci basina mesh PeerConnection/renderer, coordinator fanout ve 4+ katilimcida Janus publisher/subscriber RTC baglantisi tamam. |
| Planli mesajlar | Hazir | Create/edit/list/toggle/delete UI, encrypted DAO, one-off/daily/custom hesaplama ve no-plaintext-fallback fanout tamam. |
| Background maintenance | Hazir | Android WorkManager, iOS BGTaskScheduler/Fetch, foreground catch-up, expiry cleanup, stuck recovery, timer flush ve 7 gunluk sender-key rotation tamam. |
| App lifecycle/presence | Hazir | Persisted login ile resume reconnect, taze token provider, online/offline presence, last-seen gizleme, push token refresh, foreground recovery ve background socket kapatma tamam. |
| Incoming message pipeline | Hazir | Direct/group decrypt, metadata parse ve dedup encrypted DAO'lara bagli. Receipt/edit/delete/reaction/pin/timer/typing yalniz authenticated `CHATCTRL:v2` E2EE yolundan kabul edilir; raw legacy control uygulanmaz. |
| Push bildirim wake-up | Hazir | FCM/APNs token register/refresh/unregister, foreground/background generic `securechat_wake_v2` ve WebSocket drain tamam. Provider payload'inda sender/recipient/message-type yok; hardened server tokeni blind user index + AAD-bagli `v4` AEAD ile en fazla 90 gun (varsayilan 30) tutar. |
| Hardened server privacy | Hazir | Ayri production hedefi OTP backdoor/PII/kalici log kabul etmez; offline/bot zarflari persistence-kapali Redis RAM'de opaque key + AEAD + kisa TTL'dir. Rehber discovery blind-RSA OPRF + sealed snapshot kullanir; V13 DB yalniz finalized token/key ID tutar. Push blind-indexlidir; V14 push ve bot session raw-UUID legacy kolonlarini fiziksel olarak siler ve tamamlanmamis donusumde fail-closed durur. Kalici grup grafigi V9, behavioral audit V10, user-prekey timeline'i V11 ile silinir; push zamani V12'de gun bucket'idir. Grup mesaj/dosyasi alici basina direct Signal, chat control sabit 16 KiB E2EE ve group-call route'u gecici RAM state'idir. Plaintext legacy frame'ler reddedilir. V1-V14 PostgreSQL entegrasyon testlidir. Production binary+preflight PKCS#11, verify-full DB TLS, secret-file/amac ayrimi, immutable image digest, non-root/read-only/core-dump kapali runtime ve Redis AOF/RDB/volume reddini zorunlu tutar. |
| Yerel mesaj bildirimi | Hazir | Yalniz cihazda decrypt sonrasi Android/iOS banner, normal/sessiz kanal, mute+mention, foreground aktif-sohbet bastirma, gizli lock-screen redaksiyonu, tap-to-chat ve sistem-tepsisi dismissal uzlastirmasi tamam. |
| Cevapsiz arama bildirimi | Hazir | 30 saniyelik dedup timer; accept/reject/cancel/finish iptali, conversation unread guncellemesi, gizli missed-call bildirimi ve voice/video callback tamam. |
| Arama kalite UX | Hazir | Good/fair/poor/reconnecting uc-cubuk indikatoru, reconnect pulse/banner ve zayif baglantida videoyu kapatip sesli devam aksiyonu gercek CallManager'a bagli. |
| Debug bildirim araclari | Hazir | Incoming/missed/message simulasyon harness'i yalniz debug runtime'da; Android ADB receiver yalniz debug source-set/manifestinde ve release APK'dan dislanmis. |
| Sifreli yedek/restore | Hazir | Kotlin uyumlu PBKDF2+AES-GCM `.elbk`, GZIP, hesap kontrolu, 5 deneme limiti, atomik full-snapshot restore ve v1 okuma yolu var. |
| Sohbet export/admin audit | Hazir | TXT export, admin-only policy fanout, kisi bazli encrypted audit alimi ve lokal admin gecmis ekrani tamam. |
| Grup yonetimi | Hazir | 256 uye siniri, uye ekle/cikar, admin ata, ad/duyuru/export ayari, ayrilma ve yetki dogrulayan incoming handler tamam. |
| Kisi/sohbet bilgisi | Hazir | Arama, medya/dokuman, yildizli mesaj, not, mute, kilit ve disappearing timer ekran/servisi bagli. |
| Otomatik indirme/depolama | Hazir | Encrypted politika gercek Android/iOS ag turuyle beslenir; Wi-Fi/hucresel matris reddinde alinan payload silinip metadata korunur. Boyut limiti, sohbet bazli analiz ve metni koruyan medya temizleme tamam. |
| Splash/onboarding/izinler | Hazir | Encrypted ack, uc sayfalik intro ve Android/iOS bildirim-rehber-mikrofon-kamera permission akisi tamam. |
| Toplu mesaj | Hazir | Coklu sohbet secimi, alici bazli gercek encrypted send ve kismi hata raporu tamam. |
| Anketler | Hazir | 2-4 secenekli tekli/coklu anket olusturma, JSON sema dogrulama, oy baloncugu, lokal toggle, direct/group encrypted vote fanout ve hata rollback tamam. |
| Mesaj etkilesimleri | Hazir | Reply, 15 dakikalik giden metin duzenleme, lokal/herkesten silme, emoji reaction, lokal yildiz, admin kontrollu grup pin, sohbet-acikken duplicate-safe READ receipt ve giden mesaj bilgi penceresi uzun-bas menusu/DAO/signaling akisina bagli. |
| Mesaj iletme | Hazir | Coklu mesaj secimi tek guvenli hedefe sira/tip koruyarak gider; metin/anket yeni ID ve AEAD zarfla, medya/ses yeni encrypted chunk transferiyle iletilir. Kaynak ciphertext/reply/vote tasinmaz, tek-gosterim ve eksik yerel medya fail-closed davranir. |
| Sesli mesajlar | Hazir | Android/iOS AAC-LC kayit, izin, pause/resume, 10 dakika siniri, dBFS waveform, sifreli chunk transfer, VOICE_NOTE DAO, gelen metadata dogrulama ve app-ici seek/playback tamam. |

## Platform Parite Kararlari ve Harici Kanitlar

| Ozellik | Android kaynak | iOS karsiligi | Flutter karari |
|---|---|---|---|
| Signal Protocol wire parity | `:crypto` libsignal-android 2.8.1 | Ortak saf-Dart V3 runtime | Android ve iOS ayni GPLv3 Dart `SessionCipher`/`GroupCipher` kodunu kullanir; Kotlin 2.8.1 PreKey, ratchet reply, SKDM ve grup ciphertext capraz testleri gecer. |
| SQLCipher DB upgrade parity | Room + SQLCipher 4.5.6 | Yeni kurulum encrypted snapshot | Android native adapter v1-v22 DB'yi deterministic veya legacy Keystore passphrase ile salt-okunur acar; 12 tablo ve Signal state'i atomik tasir. iOS'ta eski Room kaynagi olmadigi icin no-op'tur. |
| Push | FCM | APNs + gerekirse PushKit | FCM/APNs token ve metadata wake-up tamam. Kapali uygulamada VoIP uyandirma icin Apple PushKit entitlement/provisioning ayrica gerekir. |
| Telefon arama entegrasyonu | Telecom ConnectionService | CallKit | Iki platform da native sistem cagri kontrolunu Dart `CallManager` ile cift yonlu senkronize eder. Normal metadata-only APNs yolu hazirdir; terminated-state VoIP PushKit icin gercek Apple entitlement, `.voip` token ve APNs sender kaniti harici kapidir. |
| Rehber | ContactsContract | Contacts.framework | Her iki native bridge ve 3072-bit blind-RSA OPRF + sabit 256 cover batch private discovery tamamlandi; gorunen ad/telefon ve eslesme cozumleme yalniz local rehberdedir. |
| Dosya secimi | Android Photo Picker/Camera/FileProvider | iOS Photos/Camera/UIDocumentInteraction | `image_picker` 1.2.2 ve `file_picker` ile kamera, coklu galeri ve belge secimi tamamlandi. Secilen dosya gonderimden once app sandbox'ina kopyalanir; open/share yalniz sandbox path'leri icin native bridge tarafindan kabul edilir. |
| Background jobs | WorkManager/AlarmManager | BGTaskScheduler sinirli | Iki platform scheduler'i ve foreground catch-up tamam. iOS calisma zamanini sistem belirler; kesin zaman semantigi platform tarafindan garanti edilmez. |
| TLS pinning | OkHttp CertificatePinner | SecureTransport/Network trust | Ortak Dart `SecureSocket` connection factory X.509 DER icinden SPKI cikarip SHA-256 primary/backup pin dogrular; self-signed pinned sertifika kabul edilir, diger gecersiz sertifikalar reddedilir. |

## Bilinen iOS Kisitlari

- iOS genel ekran goruntusu almayi Android `FLAG_SECURE` gibi bloklamaz.
- VoIP aramalarda arka plan uyandirma icin PushKit sadece gercek CallKit aramalarinda kabul edilir.
- Uzun sureli background WebSocket pratik degildir; foreground reconnect + push tetiklemeli model gerekir.
- Periyodik background cleanup kesin zaman garantisi vermez; disappearing message cleanup app acilis/foreground ve server timestamp ile desteklenmeli.
- Dosya sistemi path kaliciligi Android ile ayni degildir; security-scoped resource / sandbox kopyasi gerekir.
- HEIC/HEIF yeniden kodlanmaz; iOS native decoder ile gosterir, eski Android cihazlarda platform decoder destegi yoksa onizleme dosya kartina duser fakat orijinal sifreli dosya kayipsiz gonderilir.

## Wire Format Uyumluluk Notlari

- `SignalMessage` JSON `type` discriminator'i korundu.
- Server'in senderId/timestamp override davranisi ile uyumlu olacak sekilde encode alanlari ayni tutuldu.
- Unknown mesajlar drop edilmek yerine `UnknownSignalMessage` olarak tasinir; bu forward compatibility icin bilincli karar.
- Grup sender ic `GROUPSK:v2:<opaque-token>:<ciphertext>` SenderKey zarfini
  `GROUPROUTE:v3` olarak her alicinin ayri direct Signal session'ina sarar.
  Server raw group ID/name, sabit grup tokeni veya tam alici listesi gormez;
  v1/v2 dis route yalniz receive-only cutover uyumlulugudur.
- Grup file v3 ad/MIME/caption/gercek boyutu authenticated private manifest
  icine alir, chunk-aligned dis boyut kullanir ve her aliciya ayri direct Signal
  zarfi gonderir. Direct file v2 ayni private manifest politikasini korur.
