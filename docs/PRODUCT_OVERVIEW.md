# elçim (SecureChat) — Ürün ve Mimari Dökümanı

> **Versiyon:** 1.0.76-8aeaf79 (Haziran 2026)
> **Platform:** Android (min SDK 26, target SDK 34)
> **Hedef pazar:** Türkiye, gizlilik-öncelikli mesajlaşma

---

## İçindekiler

1. [Genel bakış](#1-genel-bakış)
2. [Mimari katmanlar](#2-mimari-katmanlar)
3. [Modül yapısı](#3-modül-yapısı)
4. [Veri katmanı (Room + SQLCipher)](#4-veri-katmanı)
5. [Sinyal protokolü (31 mesaj tipi)](#5-sinyal-protokolü)
6. [Güvenlik mimarisi](#6-güvenlik-mimarisi)
7. [Ekranlar — detaylı](#7-ekranlar)
8. [Use case'ler](#8-use-caseler)
9. [ViewModel + manager pattern](#9-viewmodel--manager-pattern)
10. [Server-side (signaling-server)](#10-server-side)
11. [bot-api (programatik gönderim)](#11-bot-api)
12. [Build + deploy](#12-build--deploy)
13. [Bilinen sınırlamalar + roadmap](#13-bilinen-sınırlamalar)

---

## 1. Genel bakış

elçim, **WhatsApp benzeri uçtan uca şifreli mesajlaşma** uygulamasıdır. Hedef:

- 1:1 ve grup mesajlaşma (max 256 üye)
- Sesli + görüntülü arama (mesh 2-3 kişi, Janus SFU 4+ kişi)
- Tek gösterimlik mesaj/medya (view-once)
- Süreli/disappearing mesaj
- Planlı (scheduled) mesaj
- Toplu (bulk) mesaj
- Sohbet dışa aktarma + admin-only encrypted audit log
- Programatik gönderim için bot API + admin CLI

**Gizlilik öncelikleri:**
- 1:1 mesajlar Signal Protocol (Double Ratchet + X3DH) ile E2EE
- Grup mesajları Sender Keys ile E2EE (Signal/WhatsApp aynı protokol)
- Lokal DB SQLCipher ile şifreli (passphrase ANDROID_ID + HMAC-SHA256 derived)
- Sunucu zero-knowledge: PostgreSQL'de mesaj saklamaz, Redis transient queue (30 gün)
- FLAG_SECURE varsayılan açık (ekran görüntüsü engelli)
- TLS certificate pinning zorunlu
- WS auth JWT EdDSA sub-userId match doğrulama

**Tech stack:**
- Kotlin + Jetpack Compose + Material 3
- Hilt DI
- Coroutines + Flow
- Room + SQLCipher
- libsignal-android 2.8.1
- WebRTC (sesli/görüntülü)
- Janus Gateway (SFU)
- Ktor (signaling-server, bot-api)
- Firebase Cloud Messaging (push notification)
- PostgreSQL 16 + Redis 7 (server)
- Docker compose + Nginx + Prometheus + Grafana

---

## 2. Mimari katmanlar

```
┌─────────────────────────────────────────┐
│  UI (Compose Screens)                   │  ← 22 ekran
├─────────────────────────────────────────┤
│  ViewModel + Manager pattern            │  ← 13 VM + 5 manager (Faz 9)
├─────────────────────────────────────────┤
│  UseCase (saf business logic)           │  ← 9 use case
├─────────────────────────────────────────┤
│  Repository (interface) + Impl          │  ← MessageRepository, ContactRepository
├─────────────────────────────────────────┤
│  DataSource — Room DAO + Network        │  ← 12 DAO, SignalingClient, FileTransferManager
└─────────────────────────────────────────┘
                    ↓                ↓
            Local SQLite        WebSocket
           (SQLCipher)      (signaling-server)
```

**Akış kuralı:** Her katman bir alt katmana bağlıdır, ters yön YASAK. UI bilmediği bir UseCase'i çağıramaz; UseCase signaling-server detayını bilmez.

---

## 3. Modül yapısı

11 Gradle modülü, multi-module Android projesi:

| Modül | Tip | Sorumluluk |
|---|---|---|
| **app** | Android application | UI, ViewModels, UseCases, navigation, Application class |
| **common** | Android library | Ortak utility (HapticManager, formatters) |
| **crypto** | Android library | Signal Protocol entegrasyonu (MessageEncryptor, SessionManager, SenderKey storage) |
| **network** | Android library | WebSocket client (SignalingClient), SignalMessage sealed class (31 tip), WebRTC PeerConnectionManager |
| **storage** | Android library | Room DB (SecureChatDatabase v19), SQLCipher, DAO, Entity, Repository impl |
| **media** | Android library | CallManager, FileTransferManager, audio routing, ringtone, telecom integration |
| **contacts** | Android library | ContactsContract bridge, PhoneEncryptor (hash-based discovery), ContactRepository |
| **signaling-server** | JVM (Ktor) | WebSocket relay, Postgres/Redis backend, FCM push tetikleme, REST API (PreKey, OTP) |
| **bot-api** | JVM (Ktor) | Programatik mesaj gönderme API'si, admin endpoints, Signal Protocol JVM variant |
| **bot-admin-cli** | JVM | Komut satırı admin aracı (bot client CRUD, emergency-stop) |

**Bağımlılık yönü** (yukarıdan aşağı):
```
app → media, contacts → network → crypto, common
                     → storage → crypto, common
signaling-server (bağımsız)
bot-api → crypto (pure-Java variant)
```

---

## 4. Veri katmanı

**Room DB:** `SecureChatDatabase` version 19 (`storage/SecureChatDatabase.kt`).
**Şifreleme:** SQLCipher, passphrase deterministic (ANDROID_ID + HMAC-SHA256, `KeyStoreManager.getOrCreateDbPassphrase`).
**Migration:** v17→v18 (export feature), v18→v19 (SenderKey storage). Veri kaybı yok.

### 12 Entity

| Entity | İçerik |
|---|---|
| **MessageEntity** | Mesaj — id, conversationId, senderId, content, contentType, timestamp, status, replyToId, isOutgoing, expiresAt, isViewOnce, isStarred, isDeleted, caption, reactions (JSON), editedAt |
| **ConversationEntity** | Sohbet — id, peerId, peerName, peerPhone, lastMessage, unreadCount, isMuted, isPinned, isGroup, groupMembers (CSV), groupAdmins (CSV), isArchived, disappearingDuration, isFavorite, isLocked (biyometrik), isExportEnabled |
| **ContactEntity** | Rehber kişisi — userId, phoneNumber, displayName, isRegistered |
| **CallLogEntity** | Arama geçmişi — id, peerId, type (VOICE/VIDEO), direction (INCOMING/OUTGOING/MISSED), duration, timestamp |
| **ScheduledMessageEntity** | Planlı mesaj — id, conversationId, content, scheduledFor, status |
| **ExportLogEntity** | Admin-only audit log — id, groupId, actorUserId, eventType, timestamp, messageCount, firstMsgTs, lastMsgTs |
| **PendingTimerUpdateEntity** | Offline süreli mesaj timer kuyruğu |
| **IdentityEntity** | Signal Protocol identity key store |
| **PreKeyEntity** | Signal Protocol one-time prekey'ler |
| **SignedPreKeyEntity** | Signal Protocol signed prekey'ler |
| **SessionEntity** | Signal Protocol Double Ratchet session state |
| **SenderKeyEntity** | Grup E2EE Sender Key state — groupId, senderId, deviceId, record (BLOB) |

### DAO'lar

Tüm DAO'lar `suspend` + Flow tabanlı. Örnekler:

- `ConversationDao` — getAll (Flow), markAsRead, updateMuted, updateGroupMembers, updateLastMessageById
- `MessageDao` — search, getMediaMessages (Flow), deleteExpiredMessages, applyRetroactiveExpiry, consumeViewOnceText
- `ExportLogDao` — observeForGroup (Flow), insert, deleteForGroup

---

## 5. Sinyal protokolü

**31 SignalMessage tipi** (`network/SignalMessage.kt`), kotlinx.serialization sealed class.

### Mesajlaşma
| Tip | Amaç |
|---|---|
| `EncryptedMessage` | 1:1 ya da grup mesaj envelope (Signal Protocol ciphertext) |
| `GroupMessageFanout` | Server fanout için recipient→ciphertext map (artık tek payload ile gönderilir Sender Keys ile) |
| `FileTransfer` | Dosya/medya chunk (128KB), groupId opsiyonel, encryption flag |
| `DeliveryReceipt` | Status update — DELIVERED ya da READ |
| `MessageDelete` | Karşı tarafta mesajı silme bildirimi |
| `MessageEdit` | Karşı tarafta mesajı düzenleme |
| `MessageReaction` | Emoji reaksiyon ekleme/kaldırma |
| `TypingIndicator` | "X yazıyor" durum bildirimi |
| `PresenceUpdate` | Online/offline + lastSeen |
| `PresenceSubscribe` / `PresenceUnsubscribe` | Karşı taraf presence izleme |
| `DisappearingTimer` | Süreli mesaj timer ayar değişikliği |

### Grup
| Tip | Amaç |
|---|---|
| `GroupNotification` | Grup olayları (CREATE, ADD_MEMBER, REMOVE_MEMBER, LEAVE_GROUP, UPDATE_NAME, UPDATE_ADMIN, DEMOTE_ADMIN, UPDATE_EXPORT_POLICY) |
| `AdminEncryptedLog` | Admin-only zero-knowledge audit (export olayları) |

### Çağrı
| Tip | Amaç |
|---|---|
| `SdpOffer` / `SdpAnswer` | WebRTC handshake |
| `IceCandidate` | NAT traversal |
| `CallControl` | RING/ACCEPT/REJECT/HANGUP/BUSY |
| `CallControlAck` | Server ACK |
| `AudioData` / `VideoData` | (deprecated — WebRTC P2P kullanılıyor) |

### Grup çağrı
| Tip | Amaç |
|---|---|
| `GroupCallInvite` | Aramaya davet |
| `GroupCallMemberJoined` / `MemberLeft` | Katılım/ayrılma |
| `GroupCallCoordinatorChanged` | Koordinatör değişimi |
| `GroupCallJoinRequest` | Geç katılım isteği |
| `GroupCallStatusQuery` / `StatusResponse` | Aktif arama sorgusu (ChatScreen banner için) |
| `SfuRoomCreated` | 4+ kişi → Janus SFU room bilgisi |

### Diğer
- `PreKeyBundleMessage` — X3DH key exchange
- `ServerShutdown` — graceful shutdown bildirimi

### Wire format prefix'leri (envelope içinde)
```
MSGID:<id>:REPLY:<rid>:EXP:<absoluteMs>:VIEWONCE:POLL:icerik
```
- **MSGID** — mesaj UUID (delivery receipt ve view-once edit için)
- **REPLY** — yanıt verilen mesaj
- **EXP** — mutlak expiresAt ms (süreli mesaj)
- **VIEWONCE** — tek gösterimlik bayrağı (sadece TEXT)
- **POLL** — anket JSON
- **POLLVOTE:`<pollMsgId>`:`<optionIdx>`** — anket oy

Parser: `data/incoming/parser/MessageEnvelopeParser.kt`

### Grup E2EE wire format
```
GROUPSK:v1:<groupId>:<groupName>:<base64ciphertext>
SKDM:<groupId>:<base64skdm>   (1:1 envelope içinde Sender Key dağıtımı)
```

---

## 6. Güvenlik mimarisi

### E2EE — 1:1
- **Protocol:** Signal Protocol Double Ratchet + X3DH
- **Implementation:** `crypto/MessageEncryptor` + `SessionManager`
- **Session bootstrap:** `PreKeyBundleFetcher` (server'dan PreKeyBundle) → `SessionManager.createSession` (X3DH)
- **Forward secrecy:** Her mesajda ratchet (Double Ratchet)
- **Wire format:** `E2EE:v1:<envelopeType>:<senderRegId>:<base64ciphertext>` (SendMessageUseCase)

### E2EE — Grup (Sender Keys)
- **Protocol:** Signal Protocol Sender Keys
- **Implementation:** `crypto/SecureChatSenderKeyStore` + `GroupSenderKeyDistributor`
- **Sender Key Distribution Message (SKDM):** Her üyeye 1:1 Signal session üzerinden gönderilir
- **Encryption:** `GroupCipher.encrypt(plaintext)` → tek ciphertext tüm gruba
- **Key rotation:** Üye çıkarıldığında otomatik + 7 günlük periyodik (`SenderKeyRotationWorker`)
- **New member:** Mevcut üyeler yeni üyeye kendi sender key'lerini SKDM olarak gönderir

### Lokal storage güvenliği
- **DB:** SQLCipher AES-256, passphrase ANDROID_ID derived (deterministic, her açılışta aynı)
- **Private key'ler:** Android Keystore (KeyStoreManager)
- **Plaintext zeroize:** `ByteArray.useAndZeroize { ... }` extension — exception olsa bile `fill(0)` garanti
- **Sensitive state:** ChatViewModel.onCleared'da messages/searchQuery/draft/readReceiptSentIds drop

### Transport güvenliği
- **WS auth:** JWT EdDSA imzalı (AuthService.verifyToken), sub claim ile userId match zorunlu
- **TLS pinning:** Certificate pinner aktif (`network/NetworkModule`)
- **Server pinning rotation:** `scripts/rotate_cert_pin.sh`

### View-once davranışı
- **TEXT:** Açıldıktan sonra `messageDao.consumeViewOnceText` — `content = ''` + `is_viewed = 1`
- **IMAGE/VIDEO:** `is_viewed = 1`, dosya cleanup'i `deleteExpiredMessages` ile
- **UI:** `ViewOnceImageViewer` / `ViewOnceTextViewer` (FLAG_SECURE altında)
- **Sohbet preview:** `previewText` her zaman "🔒 Tek gösterimlik mesaj" (içerik sızmaz)

### Disappearing mesaj
- **Sender:** SendMessageUseCase envelope'a `EXP:<absoluteMs>` gömer
- **Receiver:** `applyRetroactiveExpiry` — timer signal mesajdan önce geldiyse son 60sn'i retroaktif uygular
- **Cleanup:** `ChatDisappearingManager.startCleanupLoop` — dinamik interval (5/15/60 sn)
- **Fiziksel dosya:** `MessageRepositoryImpl.deleteExpiredMessages` — FILE/IMAGE/VOICE_NOTE için path parse + `File.delete()`

### Admin-only encrypted audit log
- **Use case:** Grup admin'i export olduğunda diğer admin'lerin haberinin olması
- **Wire:** `AdminEncryptedLog(adminPayloads: Map<adminId, ciphertext>)`
- **Encryption:** Her admin için ayrı Signal Protocol session
- **Server:** Sadece relay, içerik göremez
- **Client:** `AdminEncryptedLogHandler` — kendi userId payloads'ta yoksa sessizce drop
- **Yeni admin:** Atanmadan önceki logları göremez (kasıtlı zero-knowledge)

### FLAG_SECURE
SecureChatActivity'de varsayılan açık — ekran görüntüsü, ekran kaydı, son uygulamalarda preview engelli.

---

## 7. Ekranlar

**22 ekran**, navigation: Compose Navigation (`SecureChatNavHost.kt`).

### Auth + onboarding flow

#### 1. SplashScreen
- Pulse animasyonlu logo + ekran açılış animasyonu
- 2 saniye gösterilir, sonra:
  - `OnboardingAckStore.isOnboardingCompleted` false → `onboarding`
  - `isPermissionsWalkthroughSeen` false → `permissions_walkthrough`
  - Login yok → `auth/phone`
  - Hepsi tamam → `main`

#### 2. OnboardingScreen (Faz 13)
- 3 sayfalık HorizontalPager intro:
  - 🔒 Uçtan uca şifreli (Signal Protocol vurgusu)
  - 📞 P2P sesli/görüntülü arama (WebRTC)
  - 🛡️ Tam gizlilik kontrolü (view-once / disappearing / export)
- Atla butonu (sağ üst) + Devam/Başlayalım butonu (alt)
- Animasyonlu sayfa indicator

#### 3. PermissionWalkthroughScreen (Faz 13)
- 4 izin sırayla rationale ile:
  - Bildirimler (Android 13+)
  - Rehber (E.164 hash discovery için)
  - Mikrofon
  - Kamera
- Her kart: ikon + başlık + "Neden gerekli" + "İzin ver" butonu
- Verildi ise yeşil tick

#### 4. PhoneVerificationScreen
- Telefon numarası + ülke kodu seçici (CountryCodePicker)
- E.164 normalize edilir
- Server'a `/api/v1/auth/phone/start` → OTP gönderilir
- Sonra `auth/otp/{phoneNumber}` route'una geçer

#### 5. OtpVerificationScreen
- 6 haneli OTP girişi
- Yedek geri yükleme prompt'u (önceki yedek varsa)
- Başarılı → JWT access token alınır → `auth/email_otp/{name}/{phone}` (yeni kullanıcı) veya `main`

#### 6. EmailOtpScreen
- Yeni kullanıcı için email doğrulama (opsiyonel)
- `OtpApiClient` ile ZapMail server'a istek

#### 7. CallReadinessScreen
- İlk açılışta arama altyapı testi (mikrofon, kamera, network)
- "Tamam" → `main`

### Ana ekran (4-tab pager)

#### 8. ConversationsScreen (MAIN tab 1)
- Sohbet listesi — `messageRepository.getConversations()` Flow
- Her satır: avatar (initial-based veya generated), peerName/groupName, son mesaj preview, timestamp, unread badge
- Sağ üst: yeni sohbet, ayarlar
- Swipe: arşivle, sil (henüz tam değil)
- Long-press: pin, mute, sil
- FAB: yeni grup oluştur, toplu mesaj, planlı mesajlar
- Pull-to-refresh

#### 9. ContactsScreen (MAIN tab 2)
- Cihaz rehberinden elçim kullanıcıları
- `ContactRepository.discoverRegisteredContacts` — telefon numarası hash'leri server'a gönderir, kayıtlı olanlar döner (plaintext numara server'a gitmez)
- "Kayıtlı kullanıcılar" + "Davet et" bölümleri
- Avatar + isim + telefon → tap = direct chat aç

#### 10. CallHistoryScreen (MAIN tab 3)
- Arama geçmişi — CallLogEntity'den
- Gelen (yeşil), giden (gri), cevapsız (kırmızı) ikonları
- Tap: kişiye geri ara
- Long-press: aramayı sil

#### 11. SettingsScreen (MAIN tab 4)
- Profil ayarları (isim, durum)
- Privacy (last seen, online status visibility)
- Yedek + geri yükleme (BackupScreen → ayrı module)
- Tema (dark/light/system)
- Bildirim ayarları
- Hakkında — versionName (commit-count-shortSha)
- Çıkış

### Sohbet ekranları

#### 12. ChatScreen (3883 satır, ana mesajlaşma)
**Yapılabilenler:**
- Mesaj yazıp gönder (text)
- Atachman menüsü → MediaPreviewScreen'e geç (foto/video/dosya)
- Tek gösterimlik metin "1" toggle
- Long-press mesaj → menü (Kopyala, Yıldız, Sil, İlet, Reply, Edit, React, "Herkesten sil", Mesaj bilgisi)
- Reply'a tap → orijinal mesaja scroll + highlight
- Sohbet ara (üst bardan)
- TopBar: peerName + son görülme/online + arama + çağrı (sesli/görüntülü) + overflow menü (sohbet info, sessize al, sohbet kilidi, süreli mesaj, sohbeti dışa aktar, sil)
- View-once foto/metin tap → tam ekran viewer (FLAG_SECURE)
- Banner'lar: aktif grup arama (yeşil), export izni uyarı (turuncu, one-time)
- Mesaj durumu: ⏰ SENDING, ✓ SENT, ✓✓ DELIVERED (gri), ✓✓ READ (mavi)
- Sistem mesajları: grup olayları, arama logları, CALL|... format

**State manager pattern** (Faz 9):
- `ChatReceiptManager` — READ receipt + 800ms gecikme
- `ChatPresenceManager` — typing/online
- `ChatSearchManager` — in-chat arama
- `ChatDisappearingManager` — timer + cleanup loop
- `ChatExportManager` — TXT export + admin log

#### 13. ChatInfoScreen
- 1:1 sohbet info — peer profili
- Avatar (büyük), isim, telefon
- Medya / Dosyalar / Yıldızlı mesajlar tabları
- Süreli mesajlar ayarı
- Sessize al
- Sohbet kilidi (biyometrik)
- Özel bildirim sesi
- Kişiye not
- Rehbere ekle (kayıtlı değilse)
- **Mesaj gönder** butonu (rehberde olmayan grup üyesinden açıldığında — conversation entity yoksa otomatik oluştur + chat'e git)

#### 14. GroupInfoScreen
- Grup info — admin'e ek özellikler
- Grup adı + üye sayısı
- Üye listesi (admin rozeti, "Sen" işareti)
- Üye ekle (admin)
- Üye çıkar (admin)
- Admin yap/admin'liği al
- Üyeye tap → ChatInfoScreen(memberId)
- Süreli mesajlar (sadece admin)
- Biyometrik kilit
- **Sohbet dışa aktarma** toggle (admin)
- **Dışa aktarma geçmişi** (sadece admin)
- Gruptan çık

#### 15. ExportHistoryScreen (Faz 8 export feature)
- Admin'e özel: o grupta yapılmış tüm export olayları
- Her satır: aktör adı, tarih + saat, mesaj sayısı, tarih aralığı
- Boş state: "Henüz dışa aktarma yapılmadı"
- Admin değilse "Bu ekran sadece grup yöneticilerine açıktır" notice

### Mesajlaşma yardımcı ekranları

#### 16. MediaPreviewScreen
- Galeri/dosya seçtikten sonra önizleme
- Caption girme alanı
- "1" tek gösterimlik toggle
- "Süreli mesaj" zaten aktifse uyarı
- Gönder/iptal

#### 17. CreateGroupScreen
- Grup adı + ilk üye seçimi (rehber listesi multi-select)
- Min 2 üye + ben + grup adı zorunlu
- Oluştur → otomatik `chat/{groupId}` route

#### 18. AddGroupMemberScreen
- Mevcut gruba yeni üye ekleme
- Rehber listesi + arama
- Çoklu seçim, ekle butonu → AddGroupMemberUseCase

#### 19. ScheduledMessagesScreen
- Planlı mesajlar listesi (`ScheduledMessageEntity`)
- Tarih/saat picker ile yeni planlı mesaj
- Iptal/düzenle

#### 20. BulkMessageScreen
- Toplu mesaj — birden fazla kişiye aynı mesaj
- Rehberden multi-select
- Her bir alıcıya ayrı normal mesaj gönderilir (grup oluşturmaz)
- Rate limit + progress göstergesi

### Çağrı

#### 21. CallScreen
- Aktif arama UI
- Peer avatar + isim + state (Aranıyor.../Bağlandı/Süre)
- Mute, kamera aç/kapat, hoparlör, kamera çevir, kapat butonları
- Görüntülü: yerel video preview + uzak video tam ekran
- Mesh/SFU otomatik geçiş (4. kişi join'de)
- Bluetooth headset desteği

### Yedek

#### 22. BackupScreen (app/backup/)
- Sohbet yedeği oluştur — şifreli (parola ile)
- Dosya paylaş (Storage Access Framework)
- Geri yükle — yedek dosyası seç + parola gir
- Adaptif dosya boyutu (`formatFileSize` — KB/MB/GB)

---

## 8. Use case'ler

`app/domain/usecase/` altında **9 use case**, saf business logic:

| UseCase | Sorumluluk |
|---|---|
| **SendMessageUseCase** | Mesaj DB'ye yaz (SENDING) → envelope prefix'ler → 1:1 Signal encrypt veya grup Sender Keys encrypt → signalingClient.sendSignal → retry (max 3x2sn) → SENT/FAILED |
| **MarkAsReadUseCase** | Sohbet açılınca unread_count = 0 |
| **ObserveMessagesUseCase** | Belirli sohbet için mesaj listesi Flow (paging desteği ile) |
| **AddGroupMemberUseCase** | Admin → grup üye ekle → GroupNotification fanout → sender key dağıt |
| **RemoveGroupMemberUseCase** | Admin → grup üye çıkar → GroupNotification + sender key rotation |
| **PromoteToAdminUseCase** | Admin → başka üyeyi admin yap → GroupNotification(UPDATE_ADMIN) |
| **UpdateGroupNameUseCase** | Grup adı değiştir → GroupNotification(UPDATE_NAME) |
| **ToggleExportPolicyUseCase** | Admin → "Sohbet dışa aktarma" toggle → GroupNotification(UPDATE_EXPORT_POLICY) + sistem mesajı |
| **RecordExportEventUseCase** | Export olduğunda admin'lere encrypted log → her admin için SessionEnsurer ile session garanti et + Signal encrypt → AdminEncryptedLog signal |

---

## 9. ViewModel + manager pattern

**13 ViewModel**, her ekran için ayrı. ChatViewModel'da extra:

### ChatViewModel manager pattern (Faz 9)
Tek 1340 satırlık dosya yerine 5 manager:

```kotlin
class ChatViewModel {
    private val receiptManager = ChatReceiptManager(...)        // READ receipt + 800ms
    private val presenceManager = ChatPresenceManager(...)      // typing/online
    private val searchManager = ChatSearchManager(...)          // in-chat search
    private val disappearingManager = ChatDisappearingManager(...) // timer + cleanup
    private val exportManager = ChatExportManager(...)          // TXT + admin log

    val searchQuery: StateFlow<String> get() = searchManager.query
    val peerIsTyping: StateFlow<Boolean> get() = presenceManager.peerIsTyping
    // ... vb. delegate getter'lar
}
```

UI değişmez — `viewModel.searchQuery` aynı çalışır, sadece logic ayrı class'ta.

### Diğer önemli ViewModel'lar
- **ConversationsViewModel** — ana liste, archive/unarchive
- **GroupInfoViewModel** — üye listesi, admin işlemleri, export toggle
- **CallViewModel** — aktif çağrı state, CallManager bridge
- **SettingsViewModel** — kullanıcı ayarları, dark mode, biyometrik

---

## 10. Server-side

### signaling-server
- Ktor 2.x, JVM 17
- WebSocket relay + REST API
- PostgreSQL 16 (user registry, prekeys, audit log)
- Redis 7 (offline message queue 30 gün TTL, presence cache)
- FCM Admin SDK (push notification)
- Janus orchestrator (4+ kişi grup arama için SFU room)
- Prometheus metrics export
- Flyway migrations (V1, V2, V3 — bot_api)

**Endpointler:**
- `WS /ws?userId=X` (Bearer JWT auth)
- `GET /` — server status (online users count)
- `GET /health` — Postgres + Redis healthcheck
- `GET /metrics` — Prometheus
- `GET /api/v1/users/{userId}/prekeys` — PreKeyBundle
- `POST /api/v1/users/check` — telefon hash discovery (rate limited)
- `POST /api/v1/auth/phone/start` — OTP başlat
- `POST /api/v1/auth/phone/verify` — OTP doğrula → JWT
- `POST /api/v1/auth/refresh` — refresh token → yeni access
- `POST /api/v1/auth/email/start` — email OTP
- `GET /api/v1/latest-version` — (Faz 7) güncelleme bilgisi

**Güvenlik:**
- WS sentinel filter: `SYSTEM`/`server`/`broadcast` recipient'a route etmez
- WS connect rate limit: 10/sn/IP
- WS message rate limit: per-user
- File transfer byte rate limit: 5 MB/dk/user
- Group fanout: sender üye olmalı + recipient'lar üye olmalı (M7 fix)
- JwtBlacklist + jti revoke
- IP anonymization (audit log için GDPR)

**Docker compose stack:**
- nginx (TLS termination)
- securechat-backend (Ktor)
- securechat-bot-api (Ktor)
- securechat-postgres
- securechat-redis
- securechat-janus (WebRTC SFU)
- securechat-prometheus
- securechat-grafana
- securechat-node-exporter, postgres-exporter, redis-exporter

---

## 11. bot-api

**Amaç:** Programatik mesaj gönderim — script/cron'dan mesaj atmak için (kişisel kullanım, send-only).

**Endpoint'ler:**
- `POST /v1/send` — şifreli mesaj gönder (Signal Protocol)
- `POST /v1/admin/clients` — client CRUD (admin CLI)
- `POST /v1/admin/emergency-stop` — acil durumda durdurma

**Auth:**
- API client'lar EdDSA key pair ile JWT mint eder
- Body hash header (replay attack koruması)
- Idempotency key (duplicate prevention)
- Rate limit + allow list

**Admin CLI** (`bot-admin-cli`):
```
bot-admin client list
bot-admin client create --name "MyBot"
bot-admin emergency stop
```

---

## 12. Build + deploy

### APK build (Android)

**Online makine:**
```bash
./scripts/refresh-version.sh    # VERSION dosyası güncelle
./gradlew :app:assembleDevDebug
# APK: app/build/outputs/apk/dev/debug/app-dev-debug.apk
```

**Offline makine:** VERSION dosyasından okur. `local-repo/` Shadow plugin + transitif deps dahildir.

**Version artırma:** Her commit'te otomatik (commit-count + short-sha).
Format: `1.0.<count>-<sha>` örn. `1.0.76-8aeaf79`

### Server deploy

`signaling-server` veya `bot-api` değiştiyse:

```bash
./gradlew -PincludeServer :signaling-server:fatJar
scp signaling-server/build/libs/signaling-server-all.jar root@94.73.180.226:/opt/securechat/signaling-server/build/libs/
ssh root@94.73.180.226 'cd /opt/securechat/infra && \
  docker compose build backend && \
  docker compose up -d --force-recreate backend'
```

**Önemli:** JDK 17 toolchain kullanılır (`signaling-server/build.gradle.kts`). Lokal JDK 21 olsa bile sınıf dosyaları JDK 17 uyumlu üretilir.

### CI

`.github/workflows/android-pr.yml` — her PR'da otomatik:
- Build dev/debug
- Unit testler (continue-on-error: true legacy uyumluluğu için)
- Sensitive log lint (plaintext loglayan kodu reject)
- TODO/FIXME yoğunluğu uyarı
- APK artifact upload

### Release prosedürü

`docs/release-checklist.md` — 8 bölüm 30-45 dakikalık manuel checklist:
1. Pre-flight (VERSION + CHANGELOG)
2. Build doğrulama
3. Test pass
4. Manuel smoke test (30 dakika, gerçek cihaz)
5. Server-side healthcheck
6. Güvenlik kontrolleri
7. Release artefact'leri (APK signed, .aab)
8. Deploy + 24 saat monitoring

### Hotfix prosedürü

`docs/HOTFIX_WORKFLOW.md` — P0 critical bug için:
1. Prod tag'ten branch dal (main'den DEĞİL)
2. Minimal fix + regression test
3. VERSION refresh + build
4. Server deploy gerekirse
5. Hotfix tag oluştur, cherry-pick to main
6. Postmortem aç (`docs/incidents/TEMPLATE.md`)

---

## 13. Bilinen sınırlamalar

### Var olan ama eksik
- **Çoklu cihaz desteği yok** — bir hesap tek cihazda
- **Web client yok** (Signal Desktop benzeri)
- **Stories/status/kanal yok** (kapsam dışı)
- **Tablet/foldable layout** — WindowSizeClass infrastructure hazır (Faz 15) ama 2-pane layout henüz tüm ekranlarda yok
- **A11y full audit** — checklist hazır (`docs/accessibility-audit.md`), uygulanmadı
- **i18n** — sadece Türkçe (tasarım kararı)

### Refactor borçları
- **ChatScreen 3883 satır** — MessageBubble (770 satır) 8-helper bağımlılığı yüzünden henüz extract edilemedi
- **IncomingMessageHandler 1949 satır** — FileTransfer/EncryptedMessage/CallSignal/GroupNotification handler'ları henüz içeride (4-5 handler kaldı)
- **CallManagerTest** — `@Ignore` (refactor sonrası assertion'lar bozuk)
- **JaCoCo** — pure-JVM modüllerde aktif, Android modüllerde variant-aware konfig gerekli

### Test coverage
- **Mevcut tahmin: %30-40** (gerçek ölçüm yok, JaCoCo full kurulumu sonraki sprint)
- Hedef: crypto %95, network %80, storage %80, domain %90, ui %50
- **Bug pattern**: sureli-mesaj 5 fazda fix, okundu tikleri 2 deneme — test-first eksikliği

### Güvenlik notları
- WS auth JWT artık zorunlu (Faz 1) — eski APK kullanıcıları yeni token akışına geçmeli
- Memory zeroize sistematik (Faz 3) — `useAndZeroize` extension var, tüm `decrypt` çağrılarında uygulanmalı (sonraki sprint)
- Crashlytics interface hazır (Faz 4) — Firebase Console'da Crashlytics enable + impl class lazım

### Server-side
- **Offline message TTL: 30 gün** — sonrası kayıp (Signal/WhatsApp ile aynı)
- **File chunk TTL: 24 saat** + 10 MB/user cap
- **HMS push yok** — Huawei cihazlarda backup polling channel ihtiyacı (TODO)
- **TURN server yok** — STUN ile NAT traversal, restrictive NAT'lerde başarısız olabilir

### Roadmap referansları
- `docs/IMPROVEMENT_ROADMAP.md` — 15 faz, 6 sprint planı, P0-P3 öncelikler
- `docs/soak-test-checklist.md` — telecom soak test (12 senaryo, 4+ OEM)
- `docs/accessibility-audit.md` — WCAG 2.1 AA hedefi

---

## Ek: hızlı başlangıç komutları

```bash
# Build (online makine)
./scripts/refresh-version.sh
./gradlew :app:assembleDevDebug

# Offline build (Windows)
.\gradlew.bat --offline assembleDevDebug

# APK install
adb uninstall com.securechat.app.debug  # signing mismatch için
adb install app/build/outputs/apk/dev/debug/app-dev-debug.apk

# APK version doğrula
$ANDROID_HOME/build-tools/35.0.0/aapt2 dump badging \
  app/build/outputs/apk/dev/debug/app-dev-debug.apk | head -1

# Server log
ssh root@94.73.180.226 'docker logs --tail 50 securechat-backend'

# Redis offline queue (debug)
ssh root@94.73.180.226 << 'EOF'
PW='$(openssl rand -base64 32 | tr -d '"'"'/+='"'"' | head -c 32)'
docker exec -i securechat-redis redis-cli --no-auth-warning -a "$PW" KEYS 'offline_queue:*'
EOF

# Changelog üret
./scripts/generate-changelog.sh v1.0.50 HEAD

# Server deploy
./gradlew -PincludeServer :signaling-server:fatJar
scp signaling-server/build/libs/signaling-server-all.jar root@94.73.180.226:/opt/securechat/signaling-server/build/libs/
ssh root@94.73.180.226 'cd /opt/securechat/infra && docker compose build backend && docker compose up -d --force-recreate backend'
```

---

## Ek: önemli dosya konumları

| İçerik | Yol |
|---|---|
| Tüm UI screens | `app/src/main/java/com/securechat/app/ui/screen/` |
| Chat alt-composable'lar | `app/src/main/java/com/securechat/app/ui/screen/chat/` |
| ViewModels | `app/src/main/java/com/securechat/app/ui/theme/viewmodel/` |
| Chat manager'lar (Faz 9) | `app/src/main/java/com/securechat/app/ui/viewmodel/chat/` |
| Use cases | `app/src/main/java/com/securechat/app/domain/usecase/` |
| Incoming handler'lar (Faz 10) | `app/src/main/java/com/securechat/app/data/incoming/handlers/` |
| Envelope parser | `app/src/main/java/com/securechat/app/data/incoming/parser/` |
| Crypto core | `crypto/src/main/java/com/securechat/crypto/` |
| Storage entity + DAO | `storage/src/main/java/com/securechat/storage/{entity,dao}/` |
| Signal protocol wire | `network/src/main/java/com/securechat/network/SignalMessage.kt` |
| Server WS routes | `signaling-server/src/main/kotlin/com/securechat/signaling/WebSocketRoutes.kt` |
| Server HTTP routes | `signaling-server/src/main/kotlin/com/securechat/signaling/HttpRoutes.kt` |
| Docker compose | `infra/docker-compose.yml` |
| CLAUDE.md kurallar | `/CLAUDE.md` |
| Roadmap | `/docs/IMPROVEMENT_ROADMAP.md` |

---

**Son güncelleme:** 2026-06-08, commit `2cd3ce9`
**Kapsam:** Faz 1-15 (kalan: Faz 8 MessageBubble extract, Faz 10 büyük handler'lar — `docs/IMPROVEMENT_ROADMAP.md` Sprint 4)
