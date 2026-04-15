import Foundation

/// Signal Protocol PreKey Store implementasyonu.
/// Core Data ile PreKey'leri yönetir.
/// Android implementasyonuyla uyumlu interface sağlar.
public class CryptoPreKeyStoreImpl {

    // MARK: - Properties

    private let preKeyDAO: PreKeyDAO

    // MARK: - Initialization

    public init(preKeyDAO: PreKeyDAO = PreKeyDAO()) {
        self.preKeyDAO = preKeyDAO
    }

    // MARK: - Public Methods

    /// PreKey kaydet
    public func storePreKey(_ preKeyId: UInt32, preKeyRecord: Data) async throws {
        try await preKeyDAO.insert(id: Int32(preKeyId), record: preKeyRecord)
    }

    /// PreKey yükle
    public func loadPreKey(_ preKeyId: UInt32) async throws -> Data? {
        return try await preKeyDAO.get(id: Int32(preKeyId))
    }

    /// PreKey var mı kontrol et
    public func containsPreKey(_ preKeyId: UInt32) async throws -> Bool {
        let preKey = try await preKeyDAO.get(id: Int32(preKeyId))
        return preKey != nil
    }

    /// PreKey sil (one-time kullanım sonrası)
    public func removePreKey(_ preKeyId: UInt32) async throws {
        try await preKeyDAO.delete(id: Int32(preKeyId))
    }

    /// Mevcut tüm PreKey ID'leri
    public func getAllPreKeyIds() async throws -> [UInt32] {
        let ids = try await preKeyDAO.getAllIds()
        return ids.map { UInt32($0) }
    }

    /// PreKey sayısı
    public func getPreKeyCount() async throws -> Int {
        return try await preKeyDAO.count()
    }

    /// Random PreKey al ve sil (one-time)
    public func loadAndRemovePreKey(_ preKeyId: UInt32) async throws -> Data? {
        let preKeyRecord = try await loadPreKey(preKeyId)
        if preKeyRecord != nil {
            try await removePreKey(preKeyId)
        }
        return preKeyRecord
    }

    /// PreKey batch ekle
    public func storePreKeys(_ preKeys: [(id: UInt32, record: Data)]) async throws {
        let convertedPreKeys = preKeys.map { (Int32($0.id), $0.record) }
        try await preKeyDAO.insertBatch(convertedPreKeys)
    }

    /// En yüksek PreKey ID
    public func getMaxPreKeyId() async throws -> UInt32? {
        if let maxId = try await preKeyDAO.maxId() {
            return UInt32(maxId)
        }
        return nil
    }

    /// PreKey generation gerekli mi
    public func needsPreKeyGeneration(minimumCount: Int = 10) async throws -> Bool {
        return try await preKeyDAO.needsPreKeyGeneration(minimumCount: minimumCount)
    }

    /// Random PreKey al (silmeden)
    public func getRandomPreKey() async throws -> (id: UInt32, record: Data)? {
        if let (id, record) = try await preKeyDAO.getRandomPreKey() {
            return (UInt32(id), record)
        }
        return nil
    }

    /// Eski PreKey'leri temizle
    public func cleanupOldPreKeys(keepCount: Int = 100) async throws {
        let currentCount = try await preKeyDAO.count()
        if currentCount > keepCount {
            let deleteCount = currentCount - keepCount
            try await preKeyDAO.deleteOldest(count: deleteCount)
        }
    }

    /// Tüm PreKey'leri sil (factory reset)
    public func clearAllPreKeys() async throws {
        try await preKeyDAO.deleteAll()
    }

    /// PreKey stok durumunu kontrol et
    public func checkPreKeyStock() async throws -> PreKeyStockStatus {
        let count = try await getPreKeyCount()

        if count == 0 {
            return .empty
        } else if count < 10 {
            return .low
        } else if count < 50 {
            return .medium
        } else {
            return .full
        }
    }
}

// MARK: - PreKey Stock Status

public enum PreKeyStockStatus {
    case empty      // 0 PreKey
    case low        // < 10 PreKey
    case medium     // 10-49 PreKey
    case full       // >= 50 PreKey

    public var needsGeneration: Bool {
        switch self {
        case .empty, .low:
            return true
        case .medium, .full:
            return false
        }
    }

    public var recommendedGenerationCount: Int {
        switch self {
        case .empty:
            return 100  // İlk kez generation
        case .low:
            return 50   // Stock yenileme
        case .medium:
            return 25   // Kısmi yenileme
        case .full:
            return 0    // Generation gereksiz
        }
    }
}

// MARK: - PreKey Management Extensions

extension CryptoPreKeyStoreImpl {

    /// PreKey'leri otomatik yönet (generation + cleanup)
    public func managePreKeys() async throws -> PreKeyManagementResult {
        let stockStatus = try await checkPreKeyStock()
        var generatedCount = 0
        var cleanedCount = 0

        // PreKey generation gerekiyorsa
        if stockStatus.needsGeneration {
            let generateCount = stockStatus.recommendedGenerationCount
            let newPreKeys = try await generateNewPreKeys(count: generateCount)
            try await storePreKeys(newPreKeys)
            generatedCount = generateCount
        }

        // Cleanup yap (çok fazla PreKey varsa)
        let currentCount = try await getPreKeyCount()
        if currentCount > 200 {
            let keepCount = 100
            let beforeCount = currentCount
            try await cleanupOldPreKeys(keepCount: keepCount)
            cleanedCount = beforeCount - keepCount
        }

        return PreKeyManagementResult(
            stockStatus: stockStatus,
            generatedCount: generatedCount,
            cleanedCount: cleanedCount
        )
    }

    /// Yeni PreKey'ler oluştur (actual generation Signal modülünde olacak)
    private func generateNewPreKeys(count: Int) async throws -> [(id: UInt32, record: Data)] {
        // Bu method gerçek implementasyonda Signal crypto modülünü çağıracak
        // Şimdilik placeholder veri dönüyoruz
        var preKeys: [(id: UInt32, record: Data)] = []
        let startId = (try await getMaxPreKeyId()) ?? 0

        for i in 1...count {
            let preKeyId = startId + UInt32(i)
            let dummyRecord = Data() // Gerçek implementasyonda Signal Protocol key generation
            preKeys.append((preKeyId, dummyRecord))
        }

        return preKeys
    }
}

// MARK: - PreKey Management Result

public struct PreKeyManagementResult {
    public let stockStatus: PreKeyStockStatus
    public let generatedCount: Int
    public let cleanedCount: Int

    public var hasChanges: Bool {
        return generatedCount > 0 || cleanedCount > 0
    }

    public var description: String {
        var parts: [String] = []
        if generatedCount > 0 {
            parts.append("Generated \(generatedCount) PreKeys")
        }
        if cleanedCount > 0 {
            parts.append("Cleaned \(cleanedCount) old PreKeys")
        }
        if parts.isEmpty {
            return "No PreKey management needed"
        }
        return parts.joined(separator: ", ")
    }
}