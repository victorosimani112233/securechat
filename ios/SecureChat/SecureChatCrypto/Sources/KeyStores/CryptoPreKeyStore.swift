import Foundation

/// One-time PreKey storage ve yönetimi.
/// PreKey'ler tek kullanımlık olup, kullanıldıktan sonra silinir.
/// Stok azaldığında otomatik olarak yeni batch üretilir.
///
/// GÜVENLIK: PreKey'ler Keychain'de şifreli saklanır.
public actor CryptoPreKeyStore {

    // MARK: - Constants

    private struct Constants {
        static let preKeyPrefix = "prekey_"
        static let preKeyCounterKey = "prekey_counter"
        static let preKeyIdsKey = "prekey_ids"
        static let maxPreKeyId: UInt32 = 16777215 // 24-bit max value
    }

    // MARK: - Properties

    private let keychainManager: KeychainManager
    private var preKeyIds: Set<UInt32> = []
    private var nextPreKeyId: UInt32 = 0

    // MARK: - Initialization

    public init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
        Task {
            await loadPreKeyMetadata()
        }
    }

    // MARK: - PreKey Management

    /// PreKey'i yükler.
    ///
    /// - Parameter preKeyId: PreKey ID
    /// - Returns: PreKey data veya nil
    public func loadPreKey(_ preKeyId: UInt32) async -> Data? {
        let tag = Constants.preKeyPrefix + String(preKeyId)

        do {
            return try keychainManager.loadData(tag: tag)
        } catch {
            print("❌ Failed to load prekey \(preKeyId): \(error)")
            return nil
        }
    }

    /// PreKey'i saklar.
    ///
    /// - Parameters:
    ///   - preKeyId: PreKey ID
    ///   - record: PreKey data
    /// - Returns: Başarı durumu
    public func storePreKey(_ preKeyId: UInt32, record: Data) async -> Bool {
        let tag = Constants.preKeyPrefix + String(preKeyId)

        do {
            try keychainManager.storeData(record, tag: tag)
            preKeyIds.insert(preKeyId)
            await savePreKeyMetadata()
            return true
        } catch {
            print("❌ Failed to store prekey \(preKeyId): \(error)")
            return false
        }
    }

    /// PreKey'in mevcut olup olmadığını kontrol eder.
    ///
    /// - Parameter preKeyId: PreKey ID
    /// - Returns: true eğer mevcutsa
    public func containsPreKey(_ preKeyId: UInt32) async -> Bool {
        return preKeyIds.contains(preKeyId)
    }

    /// PreKey'i siler (kullanıldıktan sonra).
    ///
    /// - Parameter preKeyId: Silinecek PreKey ID
    /// - Returns: Başarı durumu
    public func removePreKey(_ preKeyId: UInt32) async -> Bool {
        let tag = Constants.preKeyPrefix + String(preKeyId)

        do {
            try keychainManager.deleteData(tag: tag)
            preKeyIds.remove(preKeyId)
            await savePreKeyMetadata()
            return true
        } catch {
            print("❌ Failed to remove prekey \(preKeyId): \(error)")
            return false
        }
    }

    /// Batch halinde PreKey'leri saklar.
    ///
    /// - Parameter preKeys: PreKey dictionary (ID -> Data)
    /// - Returns: Başarılı olan PreKey sayısı
    public func storePreKeys(_ preKeys: [UInt32: Data]) async -> Int {
        var successCount = 0

        for (preKeyId, data) in preKeys {
            if await storePreKey(preKeyId, record: data) {
                successCount += 1
            }
        }

        return successCount
    }

    /// Tüm PreKey'leri siler. Cleanup işlemi sırasında kullanılır.
    ///
    /// - Throws: Deletion hatası
    public func removeAllPreKeys() async throws {
        for preKeyId in preKeyIds {
            let tag = Constants.preKeyPrefix + String(preKeyId)
            try keychainManager.deleteData(tag: tag)
        }

        preKeyIds.removeAll()
        await savePreKeyMetadata()
    }

    // MARK: - PreKey Statistics

    /// Mevcut kullanılabilir PreKey sayısını döndürür.
    ///
    /// - Returns: Kullanılabilir PreKey sayısı
    public func getAvailablePreKeyCount() async -> Int {
        return preKeyIds.count
    }

    /// Sıradaki PreKey ID'sini döndürür ve counter'ı artırır.
    ///
    /// - Returns: Yeni PreKey ID
    public func getNextPreKeyId() async -> UInt32 {
        let currentId = nextPreKeyId
        nextPreKeyId = (nextPreKeyId + 1) % Constants.maxPreKeyId
        await savePreKeyMetadata()
        return currentId
    }

    /// Batch üretimi için bir dizi PreKey ID döndürür.
    ///
    /// - Parameter count: İstenilen PreKey sayısı
    /// - Returns: PreKey ID'leri array
    public func generatePreKeyIds(count: Int) async -> [UInt32] {
        var ids: [UInt32] = []

        for _ in 0..<count {
            ids.append(await getNextPreKeyId())
        }

        return ids
    }

    /// Mevcut tüm PreKey ID'lerini döndürür.
    ///
    /// - Returns: PreKey ID'leri set
    public func getAllPreKeyIds() async -> Set<UInt32> {
        return preKeyIds
    }

    // MARK: - Private Helpers

    /// PreKey metadata'sını Keychain'den yükler.
    private func loadPreKeyMetadata() async {
        // PreKey counter'ı yükle
        do {
            if let counterData = try keychainManager.loadData(tag: Constants.preKeyCounterKey) {
                nextPreKeyId = counterData.withUnsafeBytes { $0.load(as: UInt32.self) }
            }
        } catch {
            print("❌ Failed to load prekey counter: \(error)")
        }

        // PreKey ID'lerini yükle
        do {
            if let idsData = try keychainManager.loadData(tag: Constants.preKeyIdsKey) {
                preKeyIds = try decodePreKeyIds(from: idsData)
            }
        } catch {
            print("❌ Failed to load prekey IDs: \(error)")
        }
    }

    /// PreKey metadata'sını Keychain'e kaydeder.
    private func savePreKeyMetadata() async {
        // PreKey counter'ı kaydet
        do {
            var counter = nextPreKeyId
            let counterData = Data(bytes: &counter, count: MemoryLayout<UInt32>.size)
            try keychainManager.storeData(counterData, tag: Constants.preKeyCounterKey)
        } catch {
            print("❌ Failed to save prekey counter: \(error)")
        }

        // PreKey ID'lerini kaydet
        do {
            let idsData = try encodePreKeyIds(preKeyIds)
            try keychainManager.storeData(idsData, tag: Constants.preKeyIdsKey)
        } catch {
            print("❌ Failed to save prekey IDs: \(error)")
        }
    }

    /// PreKey ID'lerini Data'ya encode eder.
    private func encodePreKeyIds(_ ids: Set<UInt32>) throws -> Data {
        let encoder = JSONEncoder()
        let array = Array(ids)
        return try encoder.encode(array)
    }

    /// Data'dan PreKey ID'lerini decode eder.
    private func decodePreKeyIds(from data: Data) throws -> Set<UInt32> {
        let decoder = JSONDecoder()
        let array = try decoder.decode([UInt32].self, from: data)
        return Set(array)
    }

    // MARK: - PreKey Rotation Management

    /// Belirtilen yaşın üzerindeki PreKey'leri temizler.
    /// Gereksiz PreKey'lerin temizlenmesi için kullanılır.
    ///
    /// - Parameter maxAge: Maksimum yaş (saniye)
    /// - Returns: Temizlenen PreKey sayısı
    public func cleanupOldPreKeys(maxAge: TimeInterval) async -> Int {
        // Bu implementation basit - gerçek uygulamada timestamp tracking gerekli
        // Şimdilik sadece fazla PreKey varsa eski olanları temizle
        let currentCount = preKeyIds.count
        let maxPreKeys = 150 // Threshold'dan fazla

        if currentCount > maxPreKeys {
            let toRemove = currentCount - maxPreKeys
            let oldestIds = Array(preKeyIds.prefix(toRemove))

            var removedCount = 0
            for preKeyId in oldestIds {
                if await removePreKey(preKeyId) {
                    removedCount += 1
                }
            }

            return removedCount
        }

        return 0
    }

    /// PreKey store'un sağlık durumunu kontrol eder.
    ///
    /// - Returns: Sağlık raporu
    public func getHealthStatus() async -> PreKeyHealthStatus {
        let count = preKeyIds.count
        let needsReplenishment = count < 20 // Constants.preKeyRefreshThreshold

        return PreKeyHealthStatus(
            availableCount: count,
            nextPreKeyId: nextPreKeyId,
            needsReplenishment: needsReplenishment
        )
    }
}

// MARK: - PreKey Health Status

public struct PreKeyHealthStatus {
    public let availableCount: Int
    public let nextPreKeyId: UInt32
    public let needsReplenishment: Bool

    public init(availableCount: Int, nextPreKeyId: UInt32, needsReplenishment: Bool) {
        self.availableCount = availableCount
        self.nextPreKeyId = nextPreKeyId
        self.needsReplenishment = needsReplenishment
    }
}