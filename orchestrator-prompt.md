Sen SecureChat projesinin **orchestrator**'ısın. Tüm phase'leri sırayla, kullanıcı müdahalesi olmadan çalıştıracaksın.

## Proje
WhatsApp benzeri güvenli haberleşme Android uygulaması. Uçtan uca şifreli, P2P, sesli/görüntülü arama, yerel SQLite.

## Çalışma Planı

Aşağıdaki 4 phase'i SIRALI olarak çalıştır. Her phase'de:
1. İlgili SKILL.md dosyasını oku (`.claude/skills/<agent-name>/SKILL.md`)
2. SKILL.md'deki talimatları eksiksiz uygula
3. Kodu yaz, testleri yaz
4. Sonraki phase'e geç

---

### PHASE 1A: infra-agent
`.claude/skills/infra-agent/SKILL.md` dosyasını oku ve talimatları uygula.
- Multi-module Android projesi oluştur (app, crypto, network, storage, media, contacts, common, signaling-server)
- `settings.gradle.kts`, root `build.gradle.kts`, `gradle/libs.versions.toml`
- Her modül için `build.gradle.kts`
- Hilt DI kurulumu, Application sınıfı
- AndroidManifest.xml (tüm permissions)
- ProGuard kuralları
- `./gradlew assembleDebug` çalışır durumda olmalı

### PHASE 1B: crypto-agent
`.claude/skills/crypto-agent/SKILL.md` dosyasını oku ve talimatları uygula.
- `:crypto` modülünde çalış
- Signal Protocol: SignalProtocolStore, SessionManager, MessageEncryptor, PreKeyManager
- Android Keystore entegrasyonu (KeyStoreManager)
- CallCryptoManager (SRTP key derivation)
- EncryptedEnvelope, PreKeyBundle model sınıfları
- Unit testler

### PHASE 2A: storage-agent
`.claude/skills/storage-agent/SKILL.md` dosyasını oku ve talimatları uygula.
- `:storage` modülünde çalış
- Room Database + SQLCipher
- Entity'ler: MessageEntity, ConversationEntity, ContactEntity, PreKeyEntity, SignedPreKeyEntity, SessionEntity, IdentityEntity
- DAO'lar: MessageDao, ConversationDao, ContactDao, PreKeyDao, SignedPreKeyDao, SessionDao, IdentityDao
- Repository implementasyonları
- DataCleanupManager
- Hilt DI module
- Unit testler

### PHASE 2B: network-agent
`.claude/skills/network-agent/SKILL.md` dosyasını oku ve talimatları uygula.
- `:network` modülünde çalış
- SignalingClient (WebSocket, OkHttp)
- SignalMessage sealed class (SDP, ICE, EncryptedMessage, PreKeyBundle, CallControl)
- PeerConnectionManager (WebRTC)
- P2PMessageTransport (DataChannel üzerinden şifreli mesaj)
- OfflineMessageQueue
- ConnectionState yönetimi
- Hilt DI module
- Unit testler

### PHASE 3A: contacts-agent
`.claude/skills/contacts-agent/SKILL.md` dosyasını oku ve talimatları uygula.
- `:contacts` modülünde çalış
- ContactPermissionManager
- ContactsProvider (ContactsContract API, E.164 normalizasyon)
- UserDiscoveryService (SHA-256 hash tabanlı, privacy-first)
- ContactsObserver (ContentObserver)
- ContactSearchManager
- DiscoveryApiService (Retrofit interface)
- Hilt DI module
- Unit testler

### PHASE 3B: media-agent
`.claude/skills/media-agent/SKILL.md` dosyasını oku ve talimatları uygula.
- `:media` modülünde çalış
- CallManager (initiate, accept, end, toggle mute/camera/speaker)
- CallSession, CallState modelleri
- CallAudioManager (speaker, earpiece, bluetooth)
- CallForegroundService
- IncomingCallHandler (full-screen intent)
- Hilt DI module
- Unit testler

### PHASE 4: ui-agent
`.claude/skills/ui-agent/SKILL.md` dosyasını oku ve talimatları uygula.
- `:app` modülünde çalış
- SecureChatTheme (Material 3, dark/light)
- SecureChatNavHost (tüm navigation)
- Ekranlar: ConversationsScreen, ChatScreen (mesaj baloncukları + input bar), ContactsScreen, CallScreen, SettingsScreen, PhoneVerificationScreen
- ViewModel'ler: ConversationsViewModel, ChatViewModel, CallViewModel
- UseCase sınıfları: SendMessageUseCase, ObserveMessagesUseCase, MarkAsReadUseCase
- SecureChatActivity (FLAG_SECURE)
- Tüm modüllerle entegrasyon
- Unit testler

---

## Kurallar
- Her phase'de önce SKILL.md'yi oku, sonra kodla
- Bir phase bitince sonraki phase'e otomatik geç
- Kullanıcıya soru sorma, kararları kendin ver
- Hata alırsan düzelt ve devam et
- Tüm kod Kotlin, Jetpack Compose, Material 3
- Güvenlik kurallarına kesinlikle uy (plaintext log yasak, Keystore zorunlu, SQLCipher zorunlu)

BAŞLA. Phase 1A'dan başla, SKILL.md'yi oku ve projeyi oluşturmaya başla.
