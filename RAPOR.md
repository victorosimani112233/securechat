# SecureChat — Kapsamli Uygulama Raporu

---

## 1. Genel Bakis

SecureChat, WhatsApp benzeri, uctan uca sifreli, P2P (peer-to-peer) mimaride calisan bir Android mesajlasma uygulamasidir. Mesaj icerigi hicbir zaman sunucuya gonderilmez; sunucu yalnizca sinyal (signaling) amacli kullanilir.

| Ozellik | Deger |
|---------|-------|
| Platform | Android (Kotlin) |
| Min SDK | 26 (Android 8.0) |
| Target SDK | 34 (Android 14) |
| UI | Jetpack Compose + Material 3 |
| Mimari | Multi-module Clean Architecture |
| Sifreleme | Signal Protocol (libsignal-android) |
| Veritabani | Room + SQLCipher |
| DI | Hilt |
| Modul Sayisi | 7 (app, crypto, network, storage, media, contacts, common) |

---

## 2. Modul Mimarisi

```
+-----------------------------------------------------------+
|                         app                                |
|  (UI, ViewModels, UseCases, Navigation, DI, Services)      |
+--------+--------+--------+--------+--------+--------------+
| crypto | network| storage| media  |contacts|    common     |
|        |        |        |        |        |               |
| Signal | WebSock| Room+  | WebRTC | Rehber | UserIdentity  |
| Proto  | Signal | SQLCip | Arama  | Kesif  | Provider      |
| col    | ing    | her    |        |        |               |
+--------+--------+--------+--------+--------+--------------+
```

**Bagimlilik akisi:** `app` -> tum moduller -> `common`

---

## 3. Genel Sistem Semasi

```
+=====================================================================+
|                        SECURECHAT SISTEM SEMASI                      |
+=====================================================================+

  +------------------+                          +------------------+
  |   CIHAZ A        |                          |   CIHAZ B        |
  |  (Gonderen)      |                          |  (Alici)         |
  +------------------+                          +------------------+
  |                  |                          |                  |
  | +==============+ |                          | +==============+ |
  | |  UI KATMANI  | |                          | |  UI KATMANI  | |
  | | Jetpack      | |                          | | Jetpack      | |
  | | Compose      | |                          | | Compose      | |
  | | 17 Ekran     | |                          | | 17 Ekran     | |
  | +======|=======+ |                          | +======^=======+ |
  |        |         |                          |        |         |
  |        v         |                          |        |         |
  | +==============+ |                          | +==============+ |
  | | VIEWMODEL    | |                          | | VIEWMODEL    | |
  | | 13 ViewModel | |                          | | 13 ViewModel | |
  | +======|=======+ |                          | +======^=======+ |
  |        |         |                          |        |         |
  |        v         |                          |        |         |
  | +==============+ |                          | +==============+ |
  | | USE CASES    | |                          | | USE CASES    | |
  | | 8 UseCase    | |                          | | 8 UseCase    | |
  | +==|=======|===+ |                          | +==|=======^===+ |
  |    |       |     |                          |    |       |     |
  |    v       v     |                          |    v       |     |
  | +======+ +====+  |                          | +======+ +====+  |
  | |CRYPTO| |STOR|  |                          | |CRYPTO| |STOR|  |
  | |      | |AGE |  |                          | |      | |AGE |  |
  | |Signal| |Room|  |                          | |Signal| |Room|  |
  | |Proto | |SQL |  |                          | |Proto | |SQL |  |
  | |col   | |Ciph|  |                          | |col   | |Ciph|  |
  | +==|===+ +====+  |                          | +==^===+ +====+  |
  |    |              |                          |    |              |
  |    v              |                          |    |              |
  | +=============+   |                          | +=============+  |
  | | NETWORK     |   |                          | | NETWORK     |  |
  | | WebSocket   |   |                          | | WebSocket   |  |
  | | Client      |   |                          | | Client      |  |
  | +=====|=======+   |                          | +=====^=======+  |
  |       |           |                          |       |          |
  +-------|---+-------+                          +-------|--+-------+
          |   |                                          |  |
          |   |  +-------- P2P (WebRTC) --------+       |  |
          |   |  |  Ses/Video/Dosya (Sifreli)    |       |  |
          |   +==|===============================|=======+  |
          |      |                               |          |
          v      |                               |          |
  +-------+------+-------------------------------+----------+-------+
  |                    SIGNALING SERVER                              |
  |                    (Ktor WebSocket)                              |
  |                                                                  |
  |  +-------------------+  +-------------------+  +--------------+  |
  |  | Routing           |  | Authentication    |  | Push (FCM)   |  |
  |  | (Mesaj icerigini  |  | (JWT Token)       |  | Bildirimler  |  |
  |  |  GORMEZ)          |  |                   |  |              |  |
  |  +-------------------+  +-------------------+  +--------------+  |
  |                                                                  |
  |  +-------------------+                                           |
  |  | Discovery API     |                                           |
  |  | (Hash eslesme)    |                                           |
  |  +-------------------+                                           |
  +------------------------------------------------------------------+

  ONEMLI: Sunucu SADECE sinyal yonlendirme yapar.
  Mesaj icerigi, arama verisi ve dosyalar
  DOGRUDAN cihazlar arasi (P2P) iletilir.
```

---

## 4. Katmanli Mimari (Clean Architecture)

```
+------------------------------------------------------------------+
|                                                                    |
|  PRESENTATION (UI) KATMANI                                         |
|  +--------------------------+  +-------------------------------+   |
|  | Jetpack Compose Screens  |  | ViewModels (StateFlow/Flow)  |   |
|  | - SplashScreen           |  | - ChatViewModel              |   |
|  | - LoginScreen            |  | - ConversationsViewModel     |   |
|  | - ConversationsScreen    |  | - ContactsViewModel          |   |
|  | - ChatScreen             |  | - CallViewModel              |   |
|  | - ContactsScreen         |  | - CreateGroupViewModel       |   |
|  | - CallScreen             |  | - SettingsViewModel          |   |
|  | - CreateGroupScreen      |  | - ProfileViewModel           |   |
|  | - GroupInfoScreen         |  | - ...                        |   |
|  | - SettingsScreen         |  |                               |   |
|  | - ProfileScreen          |  |                               |   |
|  | - ArchivedScreen         |  |                               |   |
|  | - ...                    |  |                               |   |
|  +--------------------------+  +-------------------------------+   |
|                         |              |                           |
|                         v              v                           |
|  DOMAIN KATMANI                                                    |
|  +------------------------------------------------------------+   |
|  | Use Cases                                                   |   |
|  | - SendMessageUseCase      - ObserveMessagesUseCase          |   |
|  | - MarkAsReadUseCase       - UpdateContactNamesUseCase       |   |
|  | - PromoteToAdminUseCase   - ...                             |   |
|  +------------------------------------------------------------+   |
|  +------------------------------------------------------------+   |
|  | Domain Models                                               |   |
|  | - LocalMessage, Conversation, RegisteredContact             |   |
|  | - CallSession, CallState, ConnectionState                   |   |
|  +------------------------------------------------------------+   |
|                         |                                          |
|                         v                                          |
|  DATA KATMANI                                                      |
|  +-------------+ +-------------+ +-----------+ +---------------+   |
|  | Repositories | | DAOs (Room) | | Crypto    | | Network       |   |
|  | -MessageRepo | | -MessageDao | | -Signal   | | -SignalingCli |   |
|  | -ContactRepo | | -ContactDao | |  Protocol | | -WebSocket    |   |
|  |              | | -ConvDao    | | -Keystore | | -PeerConn     |   |
|  |              | | -SessionDao | |           | |  Manager      |   |
|  +-------------+ +-------------+ +-----------+ +---------------+   |
|                                                                    |
+------------------------------------------------------------------+
```

---

## 5. Feature (Ozellik) Envanteri

### 5.1 Mesajlasma
- **1-to-1 metin mesajlasma** — Signal Protocol ile E2E sifreli
- **Grup mesajlasma** — Mesh topoloji, grup olusturma/uye ekleme-cikarma/admin yonetimi
- **Dosya transferi** — Resim, video, ses, dokuman gonderimi (WebRTC DataChannel uzerinden)
- **Mesaj durumu takibi** — SENDING -> SENT -> DELIVERED -> READ
- **Okundu bilgisi** — MarkAsRead mekanizmasi
- **Offline mesaj kuyrugu** — Baglanti kesildiginde mesajlar kuyrukta bekler, baglanti gelince gonderilir
- **Mesaj arama** — Sifreli mesajlarda full-text arama
- **Conversation arsivleme** — Sohbetleri arsive tasima
- **Conversation sabitleme** — Pin/unpin
- **Conversation sessize alma** — Mute/unmute
- **Mesaj silme** — Tekil mesaj silme

### 5.2 Sesli/Goruntulu Arama
- **1-to-1 sesli arama** — WebRTC uzerinden, P2P
- **1-to-1 goruntulu arama** — WebRTC, kamera degistirme, mute, hoparlor
- **Grup arama** — Mesh topoloji (her katilimci digerlerinde ayri PeerConnection)
- **Arama durumu yonetimi** — IDLE -> RINGING -> CONNECTING -> ACTIVE -> ENDED
- **Gelen arama bildirimi** — Full-screen incoming call UI
- **Cevapsiz arama takibi** — MissedCallTracker
- **Arama foreground servisi** — Arka planda arama devam eder

### 5.3 Rehber & Kullanici Kesfi
- **Gizlilik korumali kesif** — Telefon numaralari SHA-256 hash'lenerek sunucuya gonderilir
- **Otomatik rehber senkronizasyonu** — Izin verildiginde cihaz rehberinden kayitli kullanicilari bulur
- **Manuel kullanici ID girisi** — Rehber izni olmadan dogrudan User ID ile sohbet baslatma
- **Telefon numarasi normalizasyonu** — 3 katmanli: Google libphonenumber -> regex -> ham dijit

### 5.4 Guvenlik
- **Signal Protocol** — X3DH anahtar degisimi + Double Ratchet (her mesajda yeni anahtar)
- **SQLCipher** — Veritabani AES-256 ile sifreli
- **Android Keystore** — Private key'ler donanim destekli guvenli alanda
- **Certificate Pinning** — MITM korumasi
- **FLAG_SECURE** — Ekran goruntusu engelleme
- **Bellek sifirlama** — Hassas veriler kullanim sonrasi bellekten temizlenir

### 5.5 Bildirimler & Arka Plan
- **FCM Push** — Firebase Cloud Messaging ile uzak bildirim
- **WorkManager** — Arka plan senkronizasyonu
- **Foreground Service** — Aktif arama sirasinda
- **Boot Receiver** — Cihaz yeniden baslatildiginda baglanti kurma

### 5.6 UI & UX
- **17 ekran** (asagida detayli)
- **Dark/Light tema** — ThemeManager ile dinamik
- **Splash screen** — Animasyonlu acilis
- **QR kod** — Kullanici paylasimi
- **Profil yonetimi** — Avatar, isim duzenleme
- **Ayarlar** — Bildirim, gizlilik, tema, guvenlik ayarlari

---

## 6. Ekran Envanteri (17 Ekran)

| # | Ekran | ViewModel | Aciklama |
|---|-------|-----------|----------|
| 1 | SplashScreen | SplashViewModel | Acilis, oturum kontrolu |
| 2 | LoginScreen | LoginViewModel | Telefon ile giris |
| 3 | OtpScreen | OtpViewModel | SMS dogrulama |
| 4 | ConversationsScreen | ConversationsViewModel | Sohbet listesi (ana ekran) |
| 5 | ChatScreen | ChatViewModel | Mesajlasma ekrani |
| 6 | ContactsScreen | ContactsViewModel | Rehber & kullanici kesfi |
| 7 | CreateGroupScreen | CreateGroupViewModel | Grup olusturma |
| 8 | GroupInfoScreen | GroupInfoViewModel | Grup detay/uye yonetimi |
| 9 | CallScreen | CallViewModel | Aktif arama ekrani |
| 10 | IncomingCallScreen | — | Gelen arama bildirimi |
| 11 | ProfileScreen | ProfileViewModel | Profil goruntuleme/duzenleme |
| 12 | SettingsScreen | SettingsViewModel | Uygulama ayarlari |
| 13 | ArchivedScreen | ArchivedViewModel | Arsivlenmis sohbetler |
| 14 | StarredMessagesScreen | — | Yildizli mesajlar |
| 15 | MediaGalleryScreen | — | Medya galerisi |
| 16 | QrCodeScreen | — | QR kod paylasim |
| 17 | SearchScreen | — | Mesaj arama |

---

## 7. Veritabani Semasi (Room + SQLCipher)

**Versiyon:** 12 | **Tablo sayisi:** 9

```
+------------------+     +------------------+
|  conversations   |---->|    messages       |
|------------------|     |------------------|
| id (PK)          |     | id (PK)          |
| peerId           |     | conversationId(FK|
| peerName         |     | senderId         |
| peerPhone        |     | content (sifreli)|
| isGroup          |     | contentType      |
| groupMembers     |     | timestamp        |
| groupAdmins      |     | status           |
| lastMessage      |     | isOutgoing       |
| unreadCount      |     | isStarred        |
| isMuted/isPinned |     | replyToId        |
| isArchived       |     | fileUri/fileName |
+------------------+     +------------------+

+------------------+     +------------------+
|    contacts      |     |  signal_sessions |
|------------------|     |------------------|
| id (PK)          |     | id (PK, auto)    |
| phoneNumber      |     | address          |
| phoneHash        |     | deviceId         |
| displayName      |     | sessionData(BLOB)|
| isRegistered     |     +------------------+
+------------------+
                         +------------------+
+------------------+     | signal_prekeys   |
| signal_identities|     |------------------|
|------------------|     | id (PK)          |
| id (PK, auto)    |     | preKeyId         |
| address          |     | record (BLOB)    |
| identityKey(BLOB)|     +------------------+
| trusted          |
+------------------+     +------------------+
                         |signal_signed_pkey|
+------------------+     |------------------|
|  offline_queue   |     | id (PK)          |
|------------------|     | signedPreKeyId   |
| id (PK, auto)    |     | record (BLOB)    |
| signalJson       |     +------------------+
| timestamp        |
| retryCount       |     +------------------+
| recipientId      |     |  pending_reads   |
+------------------+     |------------------|
                         | conversationId(PK|
                         | timestamp        |
                         +------------------+
```

---

## 8. Veri Akis Semalari

### 8.1 Mesaj Gonderme Akisi

```
Kullanici mesaj yazar
       |
       v
 ChatViewModel.sendMessage()
       |
       v
 SendMessageUseCase
       |
       v
 MessageRepository.sendMessage()
       |
       +-->  Room DB'ye SENDING durumunda kaydet
       |
       v
 CryptoManager.encrypt()
       |  (Signal Protocol Double Ratchet)
       v
 SignalingClient.sendSignal()
       |  (WebSocket uzerinden sifreli mesaj)
       v
 Signaling Server (sadece routing, icerik gormez)
       |
       v
 Alici cihaz -> CryptoManager.decrypt() -> Room DB -> UI
```

### 8.2 Mesaj Durumu Yasam Dongusu

```
  SENDING ----WebSocket----> SENT ----Alici onay----> DELIVERED ----Okundu----> READ
     |                         |
     |  (Baglanti yoksa)       |  (Alici cevrimi disi)
     v                         v
  OFFLINE_QUEUE             Sunucu bekletir
     |                         |
     |  (Baglanti gelince)     |  (Alici baglaninca)
     +-------> SENDING         +-------> DELIVERED
```

### 8.3 Arama Akisi

```
Arayan: CallManager.initiateCall()
       |
       +-->  WebRTC PeerConnection olustur
       +-->  ICE candidate topla
       +-->  SDP Offer olustur
       |
       v
 SignalingClient -> CALL_OFFER sinyali gonder
       |
       v
 Aranan: IncomingCallHandler -> IncomingCallScreen goster
       |
       v
 Kullanici kabul ederse:
       |
       +-->  SDP Answer olustur ve gonder
       +-->  ICE candidate degisimi
       +-->  P2P baglanti kurulur
       |
       v
 WebRTC MediaStream (ses/video dogrudan P2P)
```

### 8.4 Grup Arama (Mesh Topoloji)

```
         +--------+
         | Kisi A |
         +---+----+
            /|\
           / | \
          /  |  \     Her katilimci digerlerine
         /   |   \    ayri PeerConnection acar
        v    v    v
  +------+ +------+
  |Kisi B| |Kisi C|
  +--+---+ +---+--+
     |         |
     +---------+
   PeerConnection
```

### 8.5 Kullanici Kesfi Akisi

```
Rehber izni verilir
       |
       v
ContactsProvider -> Cihaz rehberini oku
       |
       v
PhoneNumberNormalizer -> Numaralari standartlastir
       |  (3 katman: libphonenumber -> regex -> ham dijit)
       v
SHA-256 Hash -> Numaralari hash'le
       |
       v
DiscoveryApiService -> Hash listesini sunucuya gonder
       |
       v
Sunucu: Hash'leri kayitli kullanicilarla eslestir
       |
       v
Eslesen userId'leri dondur
       |
       v
ContactDao -> Kayitli kisileri veritabanina yaz
```

### 8.6 WebSocket Baglanti Yasam Dongusu

```
 Uygulama acilir
       |
       v
 SignalingClient.connect()
       |
       v
 +----------------------------------------------+
 |    DISCONNECTED                               |
 |         |                                     |
 |         v                                     |
 |    CONNECTING                                 |
 |         |                                     |
 |    +----+----+                                |
 |    v         v                                |
 | CONNECTED  FAILED                             |
 |    |         |                                |
 |    |    Exponential Backoff                   |
 |    |    (1s -> 2s -> 4s ... 30s + jitter)     |
 |    |         |                                |
 |    |         v                                |
 |    |    RECONNECTING ------+                  |
 |    |         |             |                  |
 |    |         +-- basarisiz +                  |
 |    v                                          |
 | AUTHENTICATED                                 |
 |    |                                          |
 |    v                                          |
 | Sinyal dinle / gonder                         |
 +----------------------------------------------+
```

---

## 9. Sifreleme Mimarisi

### Sifreleme Katmanlari

```
+-----------------------------------------------+
| Katman 1: Transport (TLS 1.3 + Cert Pinning)  |
|   Agda trafik sifreleme                        |
+-----------------------------------------------+
| Katman 2: Signal Protocol (E2E)                |
|   X3DH + Double Ratchet                        |
|   Forward Secrecy + Post-Compromise Security   |
+-----------------------------------------------+
| Katman 3: Storage (SQLCipher AES-256)          |
|   Yerel veritabani sifreleme                   |
+-----------------------------------------------+
| Katman 4: Key Storage (Android Keystore)       |
|   AES-256-GCM ile anahtar koruma              |
+-----------------------------------------------+
```

### Signal Protocol Anahtar Degisimi (X3DH)

```
     ALICE (Gonderen)                    BOB (Alici)
     ================                    ===========

  1. Bob'un PreKeyBundle'ini al
     (IdentityKey + SignedPreKey + OneTimePreKey)
           |
           v
  2. Ephemeral key cifti olustur
           |
           v
  3. 4x DH hesapla:
     DH1 = IK_A  x SPK_B
     DH2 = EK_A  x IK_B
     DH3 = EK_A  x SPK_B
     DH4 = EK_A  x OPK_B
           |
           v
  4. Shared Secret = KDF(DH1 || DH2 || DH3 || DH4)
           |
           v
  5. Double Ratchet baslar
     (Her mesajda yeni simetrik anahtar turetilir)
```

### Anahtar Yasam Dongusu

| Anahtar | Olusturma | Kullanim | Omur |
|---------|-----------|----------|------|
| Identity Key | Kayit sirasinda | Kimlik dogrulama | Kalici |
| Signed PreKey | Periyodik | X3DH'de kullanilir | ~30 gun |
| One-Time PreKey | Toplu olusturma | Tek kullanim | Tek seferlik |
| Ratchet Key | Her mesajda | Mesaj sifreleme | Tek mesaj |
| DB Key | Ilk kurulumda | SQLCipher | Kalici (Keystore'da) |

---

## 10. Sinyal Mesaj Tipleri (20 Tip)

| Kategori | Mesaj Tipi | Aciklama |
|----------|-----------|----------|
| **Mesaj** | ChatMessage | Sifreli metin mesaji |
| | DeliveryReceipt | Teslim edildi bildirimi |
| | ReadReceipt | Okundu bildirimi |
| | TypingIndicator | Yaziyor gostergesi |
| | DeleteMessage | Mesaj silme sinyali |
| **Arama** | CallOffer | Arama baslatma (SDP Offer) |
| | CallAnswer | Arama kabul (SDP Answer) |
| | CallReject | Arama reddetme |
| | CallEnd | Arama sonlandirma |
| | IceCandidate | ICE aday bilgisi |
| **Grup** | GroupNotification | Grup olusturma/guncelleme |
| | GroupMessage | Grup mesaji |
| | GroupCallOffer | Grup arama teklifi |
| | GroupCallAnswer | Grup arama yaniti |
| | GroupCallEnd | Grup arama sonu |
| | GroupIceCandidate | Grup ICE adayi |
| **Anahtar** | PreKeyBundle | Signal Protocol anahtar paketi |
| | KeyExchange | Anahtar degisimi |
| **Sistem** | Authenticate | Kimlik dogrulama |
| | Ping/Pong | Baglanti canlilik kontrolu |

---

## 11. Hilt Dependency Injection Modulleri

| Modul | Saglanan Bagimliliklar |
|-------|----------------------|
| AppModule | UserSession, SharedPreferences, Context |
| NetworkModule | SignalingClient, OkHttpClient, NetworkMonitor |
| StorageModule | AppDatabase, tum DAO'lar, SharedPreferences(@Named) |
| CryptoModule | CryptoManager, SignalProtocolStore, KeyManager |
| MediaModule | CallManager, CallAudioManager, FileTransferManager |
| ContactsModule | ContactsProvider, ContactSearchManager, UserDiscoveryService |
| UseCaseModule | SendMessageUseCase, ObserveMessagesUseCase, vb. |

---

## 12. Manifest Izinleri

| Izin | Kullanim |
|------|----------|
| INTERNET | WebSocket, API |
| CAMERA | Goruntulu arama |
| RECORD_AUDIO | Sesli arama |
| READ_CONTACTS | Rehber kesfi |
| POST_NOTIFICATIONS | Bildirimler |
| FOREGROUND_SERVICE | Arama servisi |
| READ/WRITE_EXTERNAL_STORAGE | Dosya transferi |
| RECEIVE_BOOT_COMPLETED | Otomatik baglanti |
| VIBRATE | Bildirim titresimi |
| ACCESS_NETWORK_STATE | Baglanti durumu |
| WAKE_LOCK | Arka plan islemleri |

---

## 13. Test Durumu

| Modul | Test Sayisi | Framework |
|-------|-------------|-----------|
| app | 82+ | JUnit 4 + MockK + Turbine |
| network | 86+ | JUnit 4 + MockK |
| media | 179+ | JUnit 4 + MockK |
| storage | var | JUnit 4 + MockK |
| contacts | var | JUnit 4 + MockK |
| crypto | var | JUnit 4 + MockK |
| common | var | JUnit 4 |

**Test altyapisi:** MockK (Kotlin mocking), Turbine (Flow testing), Google Truth (assertions)

---

## 14. Build Yapilandirmasi

- **Build Variant'lar:** `devDebug`, `devRelease`, `prodDebug`, `prodRelease`
- **ProGuard/R8:** Release build'lerde aktif
- **Signing:** Release icin keystore yapilandirmasi mevcut
- **testOptions:** `unitTests.isReturnDefaultValues = true` (JVM testlerde Android stub'lari icin)
- **Compose:** BOM ile versiyon yonetimi

---

## 15. Uygulama Navigasyon Grafi

```
  SplashScreen
       |
       +--- Oturum var ---> ConversationsScreen (Ana Ekran)
       |                         |
       +--- Oturum yok --> LoginScreen --> OtpScreen --> ConversationsScreen
                                 |
                +----------------+----------------+
                |                |                |
                v                v                v
          ChatScreen      ContactsScreen    SettingsScreen
               |                |                |
               v                v                v
        GroupInfoScreen   CreateGroupScreen  ProfileScreen
                                             ArchivedScreen

  CallScreen <--- (herhangi bir yerden arama baslatilabilir)
  IncomingCallScreen <--- (gelen arama bildirimi)
```

---

## 16. Guvenlik Ozet Tablosu

| Tehdit | Koruma |
|--------|--------|
| Ag dinleme (MITM) | TLS 1.3 + Certificate Pinning |
| Sunucu ihlali | E2E sifreleme (sunucu icerik gormez) |
| Cihaz calinmasi | SQLCipher + Android Keystore |
| Anahtar ele gecirilmesi | Forward Secrecy (Double Ratchet) |
| Ekran goruntusu | FLAG_SECURE |
| Bellek dump | Kullanim sonrasi sifirlama |
| Rehber gizliligi | SHA-256 hash ile kesif |
| Replay saldirisi | Mesaj ID + timestamp dogrulama |

---

*Bu rapor 2026-04-28 tarihinde SecureChat kaynak kodu taranarak olusturulmustur.*
