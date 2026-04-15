import Foundation

/// Veritabanı temizlik ve bakım işlemleri manager'ı.
/// Periyodik temizlik, eski veri silme ve disk optimizasyonu.
/// Android DataCleanupManager implementasyonuna denk.
public class DataCleanupManager {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager
    private let messageDAO: MessageDAO
    private let conversationDAO: ConversationDAO
    private let preKeyDAO: PreKeyDAO
    private let signedPreKeyDAO: SignedPreKeyDAO
    private let sessionDAO: SessionDAO
    private let identityDAO: IdentityDAO
    private let keyValueDAO: KeyValueDAO

    // MARK: - Initialization

    public init(
        coreDataManager: CoreDataManager = .shared,
        messageDAO: MessageDAO = MessageDAO(),
        conversationDAO: ConversationDAO = ConversationDAO(),
        preKeyDAO: PreKeyDAO = PreKeyDAO(),
        signedPreKeyDAO: SignedPreKeyDAO = SignedPreKeyDAO(),
        sessionDAO: SessionDAO = SessionDAO(),
        identityDAO: IdentityDAO = IdentityDAO(),
        keyValueDAO: KeyValueDAO = KeyValueDAO()
    ) {
        self.coreDataManager = coreDataManager
        self.messageDAO = messageDAO
        self.conversationDAO = conversationDAO
        self.preKeyDAO = preKeyDAO
        self.signedPreKeyDAO = signedPreKeyDAO
        self.sessionDAO = sessionDAO
        self.identityDAO = identityDAO
        self.keyValueDAO = keyValueDAO
    }

    // MARK: - Public Methods

    /// Belirli süreden eski mesajları sil (kullanıcı ayarına göre)
    public func cleanOldMessages(retentionDays: Int) async throws -> Int {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(retentionDays * 24 * 60 * 60 * 1000)
        let beforeCount = try await messageDAO.count()
        try await messageDAO.deleteOlderThan(cutoff: cutoff)
        let afterCount = try await messageDAO.count()

        // Son temizlik tarihini kaydet
        try await keyValueDAO.setDate(key: "last_message_cleanup", value: Date())

        return beforeCount - afterCount
    }

    /// Tüm verileri sil (hesap silme / panic button)
    public func nukeAllData() async throws {
        try await coreDataManager.nukeAllData()
        print("SecureChat: All data has been permanently deleted")
    }

    /// Crypto key'leri temizle (logout için)
    public func clearCryptoData() async throws -> CryptoCleanupResult {
        let preKeyCount = try await preKeyDAO.count()
        let signedPreKeyCount = try await signedPreKeyDAO.count()
        let sessionCount = try await sessionDAO.count()
        let identityCount = try await identityDAO.count()

        try await preKeyDAO.deleteAll()
        try await signedPreKeyDAO.deleteAll()
        try await sessionDAO.deleteAll()
        try await identityDAO.deleteAll()

        return CryptoCleanupResult(
            deletedPreKeys: preKeyCount,
            deletedSignedPreKeys: signedPreKeyCount,
            deletedSessions: sessionCount,
            deletedIdentities: identityCount
        )
    }

    /// Veritabanı optimizasyonu (VACUUM)
    public func optimizeDatabase() async throws {
        try await coreDataManager.vacuum()
        try await keyValueDAO.setDate(key: "last_database_optimization", value: Date())
        print("SecureChat: Database optimization completed")
    }

    /// Otomatik temizlik (uygulama başlangıcında çalıştırılabilir)
    public func performAutomaticCleanup() async throws -> CleanupResult {
        var result = CleanupResult()

        // 1. Eski mesajları temizle (ayarlara göre)
        if let retentionDays = try? await keyValueDAO.getInt(key: "message_retention_days"), retentionDays > 0 {
            let deletedMessages = try await cleanOldMessages(retentionDays: retentionDays)
            result.deletedMessages = deletedMessages
        }

        // 2. PreKey temizliği (çok fazla varsa)
        let preKeyCount = try await preKeyDAO.count()
        if preKeyCount > 200 {
            let beforeCount = preKeyCount
            try await preKeyDAO.deleteOldest(count: preKeyCount - 100)
            result.deletedPreKeys = beforeCount - 100
        }

        // 3. SignedPreKey temizliği (eski olanları sil)
        try await signedPreKeyDAO.cleanup(keepMaxCount: 5)

        // 4. Corrupt session'ları temizle
        let validationResult = try await validateSessions()
        if validationResult.hasCorruptSessions {
            for sessionId in validationResult.invalidSessions {
                try await sessionDAO.delete(sessionId: sessionId)
                result.deletedCorruptSessions += 1
            }
        }

        // 5. Boş konuşmaları sil
        let deletedEmptyConversations = try await cleanEmptyConversations()
        result.deletedEmptyConversations = deletedEmptyConversations

        // 6. Son temizlik tarihini güncelle
        try await keyValueDAO.setDate(key: "last_automatic_cleanup", value: Date())

        result.completed = true
        return result
    }

    /// Disk kullanımı istatistikleri
    public func getDiskUsageStatistics() async throws -> DiskUsageStatistics {
        let messageCount = try await messageDAO.count()
        let conversationCount = try await conversationDAO.count()
        let preKeyCount = try await preKeyDAO.count()
        let signedPreKeyCount = try await signedPreKeyDAO.count()
        let sessionCount = try await sessionDAO.count()
        let identityCount = try await identityDAO.count()
        let keyValueCount = try await keyValueDAO.count()

        // Database dosya boyutu (tahmini)
        let databaseSize = try await estimateDatabaseSize()

        return DiskUsageStatistics(
            databaseSizeBytes: databaseSize,
            messageCount: messageCount,
            conversationCount: conversationCount,
            preKeyCount: preKeyCount,
            signedPreKeyCount: signedPreKeyCount,
            sessionCount: sessionCount,
            identityCount: identityCount,
            keyValueCount: keyValueCount
        )
    }

    /// Güvenlik temizliği (şüpheli activity sonrası)
    public func performSecurityCleanup(keepMessages: Bool = false) async throws -> SecurityCleanupResult {
        var result = SecurityCleanupResult()

        // 1. Tüm session'ları sil (yeniden kurulmaya zorla)
        let sessionCount = try await sessionDAO.count()
        try await sessionDAO.deleteAll()
        result.deletedSessions = sessionCount

        // 2. Güvenilmeyen identity'leri sil
        let untrustedIdentities = try await identityDAO.getUntrustedIdentities()
        for (addressName, _) in untrustedIdentities {
            try await identityDAO.delete(addressName: addressName)
            result.deletedUntrustedIdentities += 1
        }

        // 3. PreKey'leri yenile (mevcut olanları sil, yenileri generate edilmesi gerekecek)
        try await preKeyDAO.deleteAll()
        try await signedPreKeyDAO.deleteAll()
        result.clearedCryptoKeys = true

        // 4. Mesajları da silmek isteniyorsa
        if !keepMessages {
            let messageCount = try await messageDAO.count()
            try await messageDAO.deleteAll()
            try await conversationDAO.deleteAll()
            result.deletedMessages = messageCount
        }

        // 5. Database optimize et
        try await optimizeDatabase()

        result.completed = true
        try await keyValueDAO.setDate(key: "last_security_cleanup", value: Date())

        return result
    }

    // MARK: - Private Methods

    /// Boş konuşmaları temizle
    private func cleanEmptyConversations() async throws -> Int {
        // Bu işlem için özel bir sorgu gerekiyor
        // Şimdilik basit implementasyon
        return 0
    }

    /// Session validation
    private func validateSessions() async throws -> SessionValidationResult {
        let allSessions = try await sessionDAO.getAll()
        var validCount = 0
        var invalidSessions: [String] = []

        for (sessionId, record) in allSessions {
            if SignalAddress.from(sessionId: sessionId) != nil && !record.isEmpty {
                validCount += 1
            } else {
                invalidSessions.append(sessionId)
            }
        }

        return SessionValidationResult(
            totalSessions: allSessions.count,
            validSessions: validCount,
            invalidSessions: invalidSessions
        )
    }

    /// Database boyutu tahmini
    private func estimateDatabaseSize() async throws -> Int64 {
        // Core Data dosya boyutunu kontrol et
        let storeURL = coreDataManager.persistentContainer.persistentStoreDescriptions.first?.url
        if let url = storeURL {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        }
        return 0
    }
}

// MARK: - Result Models

public struct CleanupResult {
    public var deletedMessages: Int = 0
    public var deletedPreKeys: Int = 0
    public var deletedCorruptSessions: Int = 0
    public var deletedEmptyConversations: Int = 0
    public var completed: Bool = false

    public var description: String {
        var parts: [String] = []
        if deletedMessages > 0 { parts.append("\(deletedMessages) messages") }
        if deletedPreKeys > 0 { parts.append("\(deletedPreKeys) PreKeys") }
        if deletedCorruptSessions > 0 { parts.append("\(deletedCorruptSessions) corrupt sessions") }
        if deletedEmptyConversations > 0 { parts.append("\(deletedEmptyConversations) empty conversations") }

        if parts.isEmpty {
            return "No cleanup needed"
        } else {
            return "Cleaned: " + parts.joined(separator: ", ")
        }
    }
}

public struct CryptoCleanupResult {
    public let deletedPreKeys: Int
    public let deletedSignedPreKeys: Int
    public let deletedSessions: Int
    public let deletedIdentities: Int

    public var description: String {
        return """
        Crypto Cleanup:
        - PreKeys: \(deletedPreKeys)
        - SignedPreKeys: \(deletedSignedPreKeys)
        - Sessions: \(deletedSessions)
        - Identities: \(deletedIdentities)
        """
    }
}

public struct SecurityCleanupResult {
    public var deletedSessions: Int = 0
    public var deletedUntrustedIdentities: Int = 0
    public var deletedMessages: Int = 0
    public var clearedCryptoKeys: Bool = false
    public var completed: Bool = false

    public var description: String {
        var parts: [String] = []
        if deletedSessions > 0 { parts.append("\(deletedSessions) sessions") }
        if deletedUntrustedIdentities > 0 { parts.append("\(deletedUntrustedIdentities) untrusted identities") }
        if deletedMessages > 0 { parts.append("\(deletedMessages) messages") }
        if clearedCryptoKeys { parts.append("crypto keys cleared") }

        return "Security cleanup: " + parts.joined(separator: ", ")
    }
}

public struct DiskUsageStatistics {
    public let databaseSizeBytes: Int64
    public let messageCount: Int
    public let conversationCount: Int
    public let preKeyCount: Int
    public let signedPreKeyCount: Int
    public let sessionCount: Int
    public let identityCount: Int
    public let keyValueCount: Int

    public var databaseSizeMB: Double {
        return Double(databaseSizeBytes) / (1024 * 1024)
    }

    public var description: String {
        return """
        Disk Usage Statistics:
        - Database Size: \(String(format: "%.2f MB", databaseSizeMB))
        - Messages: \(messageCount)
        - Conversations: \(conversationCount)
        - PreKeys: \(preKeyCount)
        - SignedPreKeys: \(signedPreKeyCount)
        - Sessions: \(sessionCount)
        - Identities: \(identityCount)
        - Settings: \(keyValueCount)
        """
    }
}

// MARK: - Session Validation Result

public struct SessionValidationResult {
    public let totalSessions: Int
    public let validSessions: Int
    public let invalidSessions: [String]

    public var hasCorruptSessions: Bool {
        return !invalidSessions.isEmpty
    }
}

// MARK: - DAO Extensions for Count

extension MessageDAO {
    func count() async throws -> Int {
        let context = coreDataManager.viewContext
        return try await context.perform {
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            return try context.count(for: request)
        }
    }

    func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = Message.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }
}

extension ConversationDAO {
    func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = Conversation.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }
}