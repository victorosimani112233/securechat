import Foundation

/// Signal Protocol Signed PreKey Store implementasyonu.
/// Core Data ile SignedPreKey'leri yönetir.
/// Periyodik rotation (varsayılan 7 gün) desteği.
public class CryptoSignedPreKeyStoreImpl {

    // MARK: - Properties

    private let signedPreKeyDAO: SignedPreKeyDAO

    // MARK: - Initialization

    public init(signedPreKeyDAO: SignedPreKeyDAO = SignedPreKeyDAO()) {
        self.signedPreKeyDAO = signedPreKeyDAO
    }

    // MARK: - Public Methods

    /// SignedPreKey kaydet
    public func storeSignedPreKey(_ signedPreKeyId: UInt32, signedPreKeyRecord: Data) async throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        try await signedPreKeyDAO.insert(id: Int32(signedPreKeyId), record: signedPreKeyRecord, createdAt: timestamp)
    }

    /// SignedPreKey yükle
    public func loadSignedPreKey(_ signedPreKeyId: UInt32) async throws -> Data? {
        if let (record, _) = try await signedPreKeyDAO.get(id: Int32(signedPreKeyId)) {
            return record
        }
        return nil
    }

    /// SignedPreKey var mı kontrol et
    public func containsSignedPreKey(_ signedPreKeyId: UInt32) async throws -> Bool {
        let signedPreKey = try await signedPreKeyDAO.get(id: Int32(signedPreKeyId))
        return signedPreKey != nil
    }

    /// SignedPreKey sil
    public func removeSignedPreKey(_ signedPreKeyId: UInt32) async throws {
        try await signedPreKeyDAO.delete(id: Int32(signedPreKeyId))
    }

    /// En güncel SignedPreKey
    public func getLatestSignedPreKey() async throws -> (id: UInt32, record: Data, createdAt: Date)? {
        if let (id, record, createdAt) = try await signedPreKeyDAO.getLatest() {
            let date = Date(timeIntervalSince1970: Double(createdAt) / 1000.0)
            return (UInt32(id), record, date)
        }
        return nil
    }

    /// Tüm SignedPreKey'leri getir
    public func getAllSignedPreKeys() async throws -> [(id: UInt32, record: Data, createdAt: Date)] {
        let signedPreKeys = try await signedPreKeyDAO.getAll()
        return signedPreKeys.map { (id, record, createdAt) in
            let date = Date(timeIntervalSince1970: Double(createdAt) / 1000.0)
            return (UInt32(id), record, date)
        }
    }

    /// En yüksek SignedPreKey ID
    public func getMaxSignedPreKeyId() async throws -> UInt32? {
        if let maxId = try await signedPreKeyDAO.maxId() {
            return UInt32(maxId)
        }
        return nil
    }

    /// SignedPreKey rotation gerekli mi
    public func needsRotation(rotationPeriodDays: Int = 7) async throws -> Bool {
        return try await signedPreKeyDAO.needsRotation(rotationPeriodDays: rotationPeriodDays)
    }

    /// Eski SignedPreKey'leri sil
    public func removeOldSignedPreKeys(olderThanDays: Int = 30, keepLatest: Bool = true) async throws {
        let cutoffTime = Int64(Date().timeIntervalSince1970 * 1000) - Int64(olderThanDays * 24 * 60 * 60 * 1000)
        try await signedPreKeyDAO.deleteOlderThan(timestamp: cutoffTime, keepLatest: keepLatest)
    }

    /// SignedPreKey temizliği (maximum N adet tut)
    public func cleanupSignedPreKeys(keepMaxCount: Int = 5) async throws {
        try await signedPreKeyDAO.cleanup(keepMaxCount: keepMaxCount)
    }

    /// Aktif SignedPreKey var mı
    public func hasValidSignedPreKey(maxAgeDays: Int = 30) async throws -> Bool {
        return try await signedPreKeyDAO.hasValidSignedPreKey(maxAgeDays: maxAgeDays)
    }

    /// Tüm SignedPreKey'leri sil
    public func clearAllSignedPreKeys() async throws {
        try await signedPreKeyDAO.deleteAll()
    }

    /// SignedPreKey ile timestamp'i birlikte kaydet
    public func storeSignedPreKeyWithTimestamp(
        _ signedPreKeyId: UInt32,
        signedPreKeyRecord: Data,
        timestamp: Date
    ) async throws {
        let timestampMs = Int64(timestamp.timeIntervalSince1970 * 1000)
        try await signedPreKeyDAO.insert(id: Int32(signedPreKeyId), record: signedPreKeyRecord, createdAt: timestampMs)
    }
}

// MARK: - SignedPreKey Management

extension CryptoSignedPreKeyStoreImpl {

    /// SignedPreKey'leri otomatik yönet (rotation + cleanup)
    public func manageSignedPreKeys() async throws -> SignedPreKeyManagementResult {
        var rotated = false
        var cleanedCount = 0

        // Rotation kontrol et
        if try await needsRotation() {
            try await rotateSignedPreKey()
            rotated = true
        }

        // Cleanup yap
        let beforeCount = try await signedPreKeyDAO.count()
        try await cleanupSignedPreKeys()
        let afterCount = try await signedPreKeyDAO.count()
        cleanedCount = beforeCount - afterCount

        return SignedPreKeyManagementResult(
            rotated: rotated,
            cleanedCount: cleanedCount
        )
    }

    /// SignedPreKey rotation yap
    private func rotateSignedPreKey() async throws {
        // Yeni SignedPreKey oluştur (gerçek implementasyonda Signal crypto modülü çağrılacak)
        let newId = ((try await getMaxSignedPreKeyId()) ?? 0) + 1
        let newRecord = Data() // Placeholder - gerçek implementasyonda Signal Protocol key generation

        try await storeSignedPreKey(newId, signedPreKeyRecord: newRecord)

        // Eski SignedPreKey'leri temizle (en son olanı hariç)
        try await removeOldSignedPreKeys(olderThanDays: 7, keepLatest: true)
    }

    /// SignedPreKey status kontrolü
    public func getSignedPreKeyStatus() async throws -> SignedPreKeyStatus {
        guard let latest = try await getLatestSignedPreKey() else {
            return .missing
        }

        let age = Date().timeIntervalSince(latest.createdAt)
        let ageDays = Int(age / (24 * 60 * 60))

        if ageDays > 30 {
            return .expired
        } else if ageDays > 7 {
            return .needsRotation
        } else {
            return .valid
        }
    }

    /// SignedPreKey backup için export
    public func exportSignedPreKeysForBackup() async throws -> [SignedPreKeyBackup] {
        let allSignedPreKeys = try await getAllSignedPreKeys()
        return allSignedPreKeys.map { (id, record, createdAt) in
            SignedPreKeyBackup(
                id: id,
                record: record,
                createdAt: createdAt
            )
        }
    }

    /// SignedPreKey backup'tan import
    public func importSignedPreKeysFromBackup(_ backups: [SignedPreKeyBackup]) async throws {
        for backup in backups {
            try await storeSignedPreKeyWithTimestamp(
                backup.id,
                signedPreKeyRecord: backup.record,
                timestamp: backup.createdAt
            )
        }
    }
}

// MARK: - SignedPreKey Status

public enum SignedPreKeyStatus {
    case missing        // Hiç SignedPreKey yok
    case expired        // 30+ gün eski
    case needsRotation  // 7+ gün eski
    case valid          // Güncel

    public var needsAction: Bool {
        switch self {
        case .missing, .expired, .needsRotation:
            return true
        case .valid:
            return false
        }
    }

    public var description: String {
        switch self {
        case .missing:
            return "No SignedPreKey found"
        case .expired:
            return "SignedPreKey expired (>30 days old)"
        case .needsRotation:
            return "SignedPreKey needs rotation (>7 days old)"
        case .valid:
            return "SignedPreKey is valid"
        }
    }
}

// MARK: - Management Result

public struct SignedPreKeyManagementResult {
    public let rotated: Bool
    public let cleanedCount: Int

    public var hasChanges: Bool {
        return rotated || cleanedCount > 0
    }

    public var description: String {
        var parts: [String] = []
        if rotated {
            parts.append("Rotated SignedPreKey")
        }
        if cleanedCount > 0 {
            parts.append("Cleaned \(cleanedCount) old SignedPreKeys")
        }
        if parts.isEmpty {
            return "No SignedPreKey management needed"
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Backup Model

public struct SignedPreKeyBackup: Codable {
    public let id: UInt32
    public let record: Data
    public let createdAt: Date

    public init(id: UInt32, record: Data, createdAt: Date) {
        self.id = id
        self.record = record
        self.createdAt = createdAt
    }
}