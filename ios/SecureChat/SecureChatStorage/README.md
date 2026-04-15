# SecureChatStorage - iOS Core Data + SQLCipher Storage Module

## Genel Bakış

SecureChatStorage modülü, Android Room implementasyonuna denk işlevsellik sağlayan iOS Core Data + SQLCipher tabanlı depolama sistemidir. Tüm veriler cihaz üzerinde şifrelenerek saklanır ve sunucuya hiçbir mesaj içeriği gönderilmez.

## Mimari

```
Sources/
├── CoreDataManager.swift           # Ana Core Data stack manager
├── Models/                         # Enum ve model tanımları
│   ├── MessageStatus.swift
│   ├── MessageContentType.swift
│   └── TrustLevel.swift
├── DAO/                           # Data Access Objects
│   ├── MessageDAO.swift
│   ├── ConversationDAO.swift
│   ├── ContactDAO.swift
│   ├── PreKeyDAO.swift
│   ├── SignedPreKeyDAO.swift
│   ├── SessionDAO.swift
│   ├── IdentityDAO.swift
│   └── KeyValueDAO.swift
├── Repository/                    # Domain layer interfaces
│   ├── MessageRepository.swift
│   ├── ConversationRepository.swift
│   └── CryptoStores/             # Signal Protocol store implementations
│       ├── CryptoPreKeyStoreImpl.swift
│       ├── CryptoSignedPreKeyStoreImpl.swift
│       ├── CryptoSessionStoreImpl.swift
│       └── CryptoIdentityStoreImpl.swift
└── DataCleanupManager.swift       # Temizlik ve bakım işlemleri

Resources/
└── SecureChatModel.xcdatamodeld/   # Core Data model

Tests/
├── CoreDataManagerTests.swift
├── MessageDAOTests.swift
└── [Diğer DAO testleri]
```

## Güvenlik Özellikleri

### SQLCipher Şifreleme
- **Veritabanı şifreli**: Tüm SQLite veritabanı SQLCipher ile AES-256 şifrelenir
- **Passphrase güvenliği**: DB passphrase KeychainManager'dan alınır, iOS Keychain'de saklanır
- **WAL mode**: Performans ve eşzamanlılık için SQLite WAL mode aktif
- **Memory güvenliği**: SQL query logging kapalı, plaintext veriler loga yazılmaz

### Veri İzolasyonu
- **Local-only**: Hiçbir mesaj içeriği sunucuya gönderilmez
- **Cascade delete**: Konuşma silindiğinde mesajlar otomatik silinir
- **VACUUM support**: Silinen verinin diskten temizlenmesi
- **Factory reset**: Panic button ile tüm verilerin kalıcı silinmesi

## Core Data Entity'leri

### Message Entity
- **Primary Key**: id (UUID)
- **Foreign Key**: conversationID → Conversation.id
- **İndeksler**: conversation_id+timestamp, sender_id, status
- **İçerik**: Şifrelenmemiş metin (DB seviyesinde SQLCipher ile şifreli)

### Conversation Entity
- **Primary Key**: id (UUID)
- **Alanlar**: peerID, peerName, lastMessage, unreadCount, isPinned, isMuted
- **İndeks**: lastMessageTimestamp (sıralama için)

### Contact Entity
- **Primary Key**: id (UUID)
- **Güvenlik**: phoneHash (SHA-256), plaintext numara asla sunucuya gönderilmez
- **Kayıt durumu**: isRegistered boolean

### Kriptografik Entity'ler
- **PreKey**: One-time kullanım anahtarları (BLOB record)
- **SignedPreKey**: İmzalanmış anahtarlar + createdAt timestamp
- **Session**: userId:deviceId formatında session kayıtları
- **Identity**: Uzak kullanıcı kimlik anahtarları + güven seviyesi

## DAO (Data Access Object) Katmanı

### Reactive Programming
```swift
// Flow tabanlı reactive queries
messageDAO.getMessages(conversationId: "conversation-id")
    .sink { messages in
        // UI otomatik güncellenir
    }
    .store(in: &cancellables)
```

### CRUD Operasyonları
```swift
// Async/await pattern
try await messageDAO.insert(messageData)
try await messageDAO.updateStatus(messageId: id, status: .delivered)
try await messageDAO.delete(messageId: id)
```

## Repository Pattern

### Domain Layer Interface
```swift
protocol MessageRepository {
    func saveMessage(_ message: LocalMessage) async throws
    func getMessages(conversationId: String) -> AnyPublisher<[LocalMessage], Never>
    func deleteConversation(conversationId: String) async throws
}
```

### Implementation
```swift
class MessageRepositoryImpl: MessageRepository {
    // DAO'ları kullanarak domain logic
    // Core Data'dan bağımsız domain modelleri
}
```

## Signal Protocol Integration

### Crypto Store Implementations
SecureChat, Signal Protocol için gerekli olan 4 store interface'ini implement eder:

1. **PreKeyStore**: One-time prekey yönetimi
2. **SignedPreKeyStore**: İmzalanmış prekey rotation
3. **SessionStore**: Peer-to-peer session management
4. **IdentityStore**: Remote identity key güven yönetimi

### Key Management
```swift
// PreKey stock kontrolü
let stockStatus = try await preKeyStore.checkPreKeyStock()
if stockStatus.needsGeneration {
    try await preKeyStore.managePreKeys()
}

// SignedPreKey rotation
if try await signedPreKeyStore.needsRotation() {
    try await signedPreKeyStore.manageSignedPreKeys()
}
```

## Veri Temizleme ve Bakım

### DataCleanupManager
```swift
let cleanupManager = DataCleanupManager()

// Otomatik temizlik (app startup'da)
let result = try await cleanupManager.performAutomaticCleanup()

// Retention policy (eski mesajları sil)
try await cleanupManager.cleanOldMessages(retentionDays: 30)

// Güvenlik temizliği (şüpheli aktivite sonrası)
try await cleanupManager.performSecurityCleanup()

// Factory reset (panic button)
try await cleanupManager.nukeAllData()
```

### Database Optimization
```swift
// VACUUM operasyonu
try await coreDataManager.vacuum()

// Disk kullanım istatistikleri
let stats = try await cleanupManager.getDiskUsageStatistics()
print("Database size: \(stats.databaseSizeMB) MB")
```

## Test Stratejisi

### Unit Testing
- **In-memory Core Data**: Hızlı test execution
- **DAO testleri**: CRUD operasyonları, reactive flow
- **Repository testleri**: Domain logic validation
- **Cleanup testleri**: Veri temizleme doğrulaması

### Test Çalıştırma
```bash
# iOS Simulator'da testleri çalıştır
xcodebuild test -scheme SecureChatStorage -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Performans Optimizasyonları

### Index Strategy
- **Composite index**: conversation_id + timestamp (mesaj listesi için)
- **Single indexes**: sender_id, status (filtreleme için)
- **Timestamp index**: Conversation.lastMessageTimestamp (sıralama için)

### Batch Operations
```swift
// Batch insert (rehber sync için)
try await contactDAO.insertBatch(contacts)

// Batch delete (cleanup için)
try await messageDAO.deleteOlderThan(cutoff: timestamp)
```

### Memory Management
```swift
// Background context (heavy operations için)
let backgroundContext = coreDataManager.newBackgroundContext()

// Context merge policy
context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
```

## Hata Yönetimi

### Core Data Errors
```swift
enum CoreDataError: Error {
    case storeNotFound
    case migrationFailed
    case encryptionFailed
    case saveFailed(Error)
}
```

### Encryption Failures
- **Fatal crash**: DB şifrelemesi başarısız olursa app crash
- **Güvenlik önceliği**: Corrupt/unencrypted DB asla kabul edilmez
- **Recovery**: Store yeniden oluşturma ile data loss

## Migration Stratejisi

### Schema Versioning
- **exportSchema: true**: Migration doğrulaması için
- **Automatic migration**: Basit değişiklikler için
- **Manual migration**: Karmaşık schema değişiklikleri için

### Backward Compatibility
- **Android uyumluluğu**: Aynı veri formatları
- **Cross-platform sync**: Gelecekte iCloud/backup desteği için

## Entegrasyon

### Diğer Modüllerle Bağımlılıklar
```swift
import SecureChatCrypto  // KeychainManager için
import SecureChatCommon  // Shared modeller için
```

### Dependency Injection
```swift
// Repository injection
let messageRepo = MessageRepositoryImpl(
    messageDAO: MessageDAO(coreDataManager: coreDataManager),
    conversationDAO: ConversationDAO(coreDataManager: coreDataManager)
)
```

## Monitoring ve Debugging

### Logging
```swift
// Güvenlik: Mesaj içerikleri asla loga yazılmaz
print("SecureChat: Message saved with ID: \(messageId)")  // ✅ OK
print("SecureChat: Message content: \(content)")          // ❌ FORBIDDEN
```

### Debug Tools
```swift
#if DEBUG
let stats = try await cleanupManager.getDiskUsageStatistics()
print(stats.description)
#endif
```

## Güvenlik Kontrolü

### Code Review Checklist
- [ ] Plaintext mesaj içeriği loga yazılmıyor
- [ ] Database passphrase KeychainManager'dan alınıyor
- [ ] SQLCipher configuration doğru
- [ ] Memory cleanup yapılıyor
- [ ] Cascade delete çalışıyor
- [ ] Factory reset tüm verileri temizliyor

### Penetration Testing
- [ ] Encrypted database dosyası açılamıyor (passphrase olmadan)
- [ ] Memory dump'ında plaintext veri yok
- [ ] App backgrounding sırasında hassas veri korunuyor
- [ ] Jailbroken device'larda ek güvenlik önlemleri

## Gelecek Geliştirmeler

### v1.1 Hedefleri
- [ ] iCloud backup encryption
- [ ] Cross-device sync
- [ ] Advanced query optimization
- [ ] Automatic schema migration

### Performance İyileştirmeleri
- [ ] Message pagination
- [ ] Lazy loading
- [ ] Background fetch optimization
- [ ] Memory footprint reduction

---

**Not**: Bu implementasyon Android Room + SQLCipher'a %100 uyumlu interface sağlar ve tüm güvenlik gereksinimlerini karşılar. Production kullanımı için ek penetration testing ve security audit önerilir.