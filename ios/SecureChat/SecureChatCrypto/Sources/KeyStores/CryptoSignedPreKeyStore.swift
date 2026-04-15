import Foundation

/// Signed PreKey storage ve yönetimi.
/// Signed PreKey'ler orta ömürlü olup, periyodik olarak rotate edilir.
/// Eski signed PreKey'ler geç gelen mesajlar için bir süre daha tutulur.
///
/// GÜVENLIK: SignedPreKey'ler Keychain'de şifreli saklanır.
public actor CryptoSignedPreKeyStore {

    // MARK: - Constants

    private struct Constants {
        static let signedPreKeyPrefix = "signed_prekey_"
        static let signedPreKeyIdsKey = "signed_prekey_ids"
        static let lastRotationKey = "signed_prekey_last_rotation"
        static let rotationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        static let maxSignedPreKeyAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    }

    // MARK: - Properties

    private let keychainManager: KeychainManager
    private var signedPreKeyIds: Set<UInt32> = []
    private var lastRotationTime: Date?

    // MARK: - Initialization

    public init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
        Task {
            await loadSignedPreKeyMetadata()
        }
    }

    // MARK: - SignedPreKey Management

    /// SignedPreKey'i yükler.
    ///
    /// - Parameter signedPreKeyId: SignedPreKey ID
    /// - Returns: SignedPreKey data veya nil
    public func loadSignedPreKey(_ signedPreKeyId: UInt32) async -> Data? {
        let tag = Constants.signedPreKeyPrefix + String(signedPreKeyId)

        do {
            return try keychainManager.loadData(tag: tag)
        } catch {
            print("❌ Failed to load signed prekey \(signedPreKeyId): \(error)")
            return nil
        }
    }

    /// SignedPreKey'i saklar.
    ///
    /// - Parameters:
    ///   - signedPreKeyId: SignedPreKey ID
    ///   - record: SignedPreKey data
    /// - Returns: Başarı durumu
    public func storeSignedPreKey(_ signedPreKeyId: UInt32, record: Data) async -> Bool {
        let tag = Constants.signedPreKeyPrefix + String(signedPreKeyId)

        do {
            try keychainManager.storeData(record, tag: tag)
            signedPreKeyIds.insert(signedPreKeyId)
            await saveSignedPreKeyMetadata()
            return true
        } catch {
            print("❌ Failed to store signed prekey \(signedPreKeyId): \(error)")
            return false
        }
    }

    /// SignedPreKey'in mevcut olup olmadığını kontrol eder.
    ///
    /// - Parameter signedPreKeyId: SignedPreKey ID
    /// - Returns: true eğer mevcutsa
    public func containsSignedPreKey(_ signedPreKeyId: UInt32) async -> Bool {
        return signedPreKeyIds.contains(signedPreKeyId)
    }

    /// SignedPreKey'i siler.
    ///
    /// - Parameter signedPreKeyId: Silinecek SignedPreKey ID
    /// - Returns: Başarı durumu
    public func removeSignedPreKey(_ signedPreKeyId: UInt32) async -> Bool {
        let tag = Constants.signedPreKeyPrefix + String(signedPreKeyId)

        do {
            try keychainManager.deleteData(tag: tag)
            signedPreKeyIds.remove(signedPreKeyId)
            await saveSignedPreKeyMetadata()
            return true
        } catch {
            print("❌ Failed to remove signed prekey \(signedPreKeyId): \(error)")
            return false
        }
    }

    /// Tüm SignedPreKey'lerin data'sını yükler.
    ///
    /// - Returns: SignedPreKey data array
    public func loadAllSignedPreKeys() async -> [Data] {
        var allKeys: [Data] = []

        for signedPreKeyId in signedPreKeyIds {
            if let keyData = await loadSignedPreKey(signedPreKeyId) {
                allKeys.append(keyData)
            }
        }

        return allKeys
    }

    /// Tüm SignedPreKey'leri siler. Cleanup işlemi sırasında kullanılır.
    ///
    /// - Throws: Deletion hatası
    public func removeAllSignedPreKeys() async throws {
        for signedPreKeyId in signedPreKeyIds {
            let tag = Constants.signedPreKeyPrefix + String(signedPreKeyId)
            try keychainManager.deleteData(tag: tag)
        }

        signedPreKeyIds.removeAll()
        lastRotationTime = nil
        await saveSignedPreKeyMetadata()
    }

    // MARK: - SignedPreKey Rotation

    /// Son rotation zamanını döndürür.
    ///
    /// - Returns: Son rotation tarihi veya nil
    public func getLastRotationTime() async -> Date? {
        return lastRotationTime
    }

    /// Rotation zamanını günceller.
    ///
    /// - Parameter date: Yeni rotation tarihi
    public func updateRotationTime(_ date: Date) async {
        lastRotationTime = date
        await saveSignedPreKeyMetadata()
    }

    /// SignedPreKey rotation'ın gerekli olup olmadığını kontrol eder.
    ///
    /// - Returns: true eğer rotation gerekiyorsa
    public func needsRotation() async -> Bool {
        guard let lastRotation = lastRotationTime else {
            return true // İlk rotation
        }

        let timeSinceLastRotation = Date().timeIntervalSince(lastRotation)
        return timeSinceLastRotation > Constants.rotationInterval
    }

    /// Eski SignedPreKey'leri temizler.
    /// Belirtilen yaşın üzerindeki SignedPreKey'ler silinir.
    ///
    /// - Parameter maxAge: Maksimum yaş (varsayılan 30 gün)
    /// - Returns: Temizlenen SignedPreKey sayısı
    public func cleanupOldSignedPreKeys(maxAge: TimeInterval = Constants.maxSignedPreKeyAge) async -> Int {
        // Bu basit implementation - gerçek uygulamada timestamp tracking gerekli
        // SignedPreKey'lerde creation timestamp saklanması gerekir

        let currentCount = signedPreKeyIds.count
        let maxKeysToKeep = 5 // En fazla 5 signed prekey tut

        if currentCount > maxKeysToKeep {
            let sortedIds = signedPreKeyIds.sorted() // En eski ID'ler önce
            let toRemove = Array(sortedIds.dropLast(maxKeysToKeep))

            var removedCount = 0
            for signedPreKeyId in toRemove {
                if await removeSignedPreKey(signedPreKeyId) {
                    removedCount += 1
                }
            }

            return removedCount
        }

        return 0
    }

    /// Mevcut SignedPreKey sayısını döndürür.
    ///
    /// - Returns: SignedPreKey sayısı
    public func getSignedPreKeyCount() async -> Int {
        return signedPreKeyIds.count
    }

    /// Sıradaki SignedPreKey ID'sini döndürür.
    ///
    /// - Returns: Yeni SignedPreKey ID
    public func getNextSignedPreKeyId() async -> UInt32 {
        if signedPreKeyIds.isEmpty {
            return 0
        } else {
            let maxId = signedPreKeyIds.max() ?? 0
            return maxId + 1
        }
    }

    /// Mevcut tüm SignedPreKey ID'lerini döndürür.
    ///
    /// - Returns: SignedPreKey ID'leri set
    public func getAllSignedPreKeyIds() async -> Set<UInt32> {
        return signedPreKeyIds
    }

    // MARK: - Private Helpers

    /// SignedPreKey metadata'sını Keychain'den yükler.
    private func loadSignedPreKeyMetadata() async {
        // SignedPreKey ID'lerini yükle
        do {
            if let idsData = try keychainManager.loadData(tag: Constants.signedPreKeyIdsKey) {
                signedPreKeyIds = try decodeSignedPreKeyIds(from: idsData)
            }
        } catch {
            print("❌ Failed to load signed prekey IDs: \(error)")
        }

        // Son rotation zamanını yükle
        do {
            if let rotationData = try keychainManager.loadData(tag: Constants.lastRotationKey) {
                let timestamp = rotationData.withUnsafeBytes { $0.load(as: TimeInterval.self) }
                lastRotationTime = Date(timeIntervalSince1970: timestamp)
            }
        } catch {
            print("❌ Failed to load last rotation time: \(error)")
        }
    }

    /// SignedPreKey metadata'sını Keychain'e kaydeder.
    private func saveSignedPreKeyMetadata() async {
        // SignedPreKey ID'lerini kaydet
        do {
            let idsData = try encodeSignedPreKeyIds(signedPreKeyIds)
            try keychainManager.storeData(idsData, tag: Constants.signedPreKeyIdsKey)
        } catch {
            print("❌ Failed to save signed prekey IDs: \(error)")
        }

        // Son rotation zamanını kaydet
        if let rotationTime = lastRotationTime {
            do {
                var timestamp = rotationTime.timeIntervalSince1970
                let rotationData = Data(bytes: &timestamp, count: MemoryLayout<TimeInterval>.size)
                try keychainManager.storeData(rotationData, tag: Constants.lastRotationKey)
            } catch {
                print("❌ Failed to save last rotation time: \(error)")
            }
        }
    }

    /// SignedPreKey ID'lerini Data'ya encode eder.
    private func encodeSignedPreKeyIds(_ ids: Set<UInt32>) throws -> Data {
        let encoder = JSONEncoder()
        let array = Array(ids)
        return try encoder.encode(array)
    }

    /// Data'dan SignedPreKey ID'lerini decode eder.
    private func decodeSignedPreKeyIds(from data: Data) throws -> Set<UInt32> {
        let decoder = JSONDecoder()
        let array = try decoder.decode([UInt32].self, from: data)
        return Set(array)
    }

    // MARK: - Health Status

    /// SignedPreKey store'un sağlık durumunu kontrol eder.
    ///
    /// - Returns: Sağlık raporu
    public func getHealthStatus() async -> SignedPreKeyHealthStatus {
        let count = signedPreKeyIds.count
        let needsRotation = await self.needsRotation()
        let nextId = await getNextSignedPreKeyId()

        return SignedPreKeyHealthStatus(
            signedPreKeyCount: count,
            nextSignedPreKeyId: nextId,
            needsRotation: needsRotation,
            lastRotationTime: lastRotationTime
        )
    }
}

// MARK: - SignedPreKey Health Status

public struct SignedPreKeyHealthStatus {
    public let signedPreKeyCount: Int
    public let nextSignedPreKeyId: UInt32
    public let needsRotation: Bool
    public let lastRotationTime: Date?

    public init(
        signedPreKeyCount: Int,
        nextSignedPreKeyId: UInt32,
        needsRotation: Bool,
        lastRotationTime: Date?
    ) {
        self.signedPreKeyCount = signedPreKeyCount
        self.nextSignedPreKeyId = nextSignedPreKeyId
        self.needsRotation = needsRotation
        self.lastRotationTime = lastRotationTime
    }
}