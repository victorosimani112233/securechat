import Foundation
import SignalProtocolKit
import SecureChatCommon

/// PreKey üretimi ve yönetimi.
/// İlk kayıt sırasında identity key pair, registration ID, one-time PreKey'ler
/// ve signed PreKey üretir. Periyodik olarak PreKey stokunu kontrol eder
/// ve gerektiğinde yeni batch üretir.
///
/// Key hierarchy:
/// - Identity Key Pair: Uzun ömürlü, cihaz başına 1
/// - Signed PreKey: Orta ömürlü, her 7 günde rotate edilir
/// - One-Time PreKey: Tek kullanımlık, batch halinde üretilir
public class PreKeyManager {

    // MARK: - Constants

    private struct Constants {
        /// Her batch'te üretilecek one-time PreKey sayısı
        static let preKeyBatchSize = 100

        /// Bu eşik altına düşülürse yeni PreKey batch üretilir
        static let preKeyRefreshThreshold = 20

        /// Signed PreKey rotation periyodu (saniye)
        static let signedPreKeyRotationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    }

    // MARK: - Properties

    private let protocolStore: SecureChatProtocolStore
    private let identityStore: CryptoIdentityStore
    private let keychainManager: KeychainManager

    // MARK: - Initialization

    public init(
        protocolStore: SecureChatProtocolStore,
        identityStore: CryptoIdentityStore,
        keychainManager: KeychainManager
    ) {
        self.protocolStore = protocolStore
        self.identityStore = identityStore
        self.keychainManager = keychainManager
    }

    // MARK: - Initial Key Generation

    /// İlk kayıt sırasında tüm kriptografik anahtarları üretir.
    /// Identity key pair, registration ID, one-time PreKey'ler ve signed PreKey oluşturur.
    ///
    /// GÜVENLIK: Identity key pair iOS Keychain ile korunur.
    ///
    /// - Returns: Üretilen key bundle (sunucuya gönderilmek üzere)
    /// - Throws: Key generation veya storage hatası
    public func generateInitialKeys() async throws -> KeyBundle {
        // Identity key pair üret
        let identityKeyPair = try SPKIdentityKeyPair.generateKeyPair()

        // Registration ID üret (24-bit random)
        let registrationId = try generateRegistrationId()

        // Identity key pair'ı güvenli sakla
        let identityKeyData = identityKeyPair.keyData
        let success = await identityStore.storeIdentityKeyPair(identityKeyData)
        guard success else {
            throw PreKeyError.storageFailure("Failed to store identity key pair")
        }

        // Registration ID'yi sakla
        let registrationStored = await identityStore.storeLocalRegistrationId(registrationId)
        guard registrationStored else {
            throw PreKeyError.storageFailure("Failed to store registration ID")
        }

        // One-time PreKey'leri üret
        let preKeys = try await generatePreKeyBatch(startId: 0, count: Constants.preKeyBatchSize)

        // Signed PreKey üret
        let signedPreKey = try generateSignedPreKey(identityKeyPair: identityKeyPair, signedPreKeyId: 0)

        // PreKey'leri store'a kaydet
        for preKey in preKeys {
            let stored = await protocolStore.preKeyStore.storePreKey(preKey.keyId, record: preKey.data)
            guard stored else {
                throw PreKeyError.storageFailure("Failed to store prekey \(preKey.keyId)")
            }
        }

        // Signed PreKey'i store'a kaydet
        let signedStored = await protocolStore.signedPreKeyStore.storeSignedPreKey(
            signedPreKey.keyId,
            record: signedPreKey.data
        )
        guard signedStored else {
            throw PreKeyError.storageFailure("Failed to store signed prekey")
        }

        // Rotation zamanını kaydet
        await protocolStore.signedPreKeyStore.updateRotationTime(Date())

        // Public key bundle oluştur
        let keyBundle = KeyBundle(
            identityKey: identityKeyPair.publicKey.keyData,
            registrationId: registrationId,
            preKeys: preKeys.map { PreKeyPublic(keyId: $0.keyId, publicKey: $0.publicKey) },
            signedPreKey: SignedPreKeyPublic(
                keyId: signedPreKey.keyId,
                publicKey: signedPreKey.publicKey,
                signature: signedPreKey.signature,
                timestamp: signedPreKey.timestamp
            )
        )

        // Private key material'ı bellekten temizle
        var mutableKeyData = identityKeyData
        mutableKeyData.resetBytes(in: 0..<identityKeyData.count)

        print("✅ Initial keys generated successfully")
        return keyBundle
    }

    // MARK: - PreKey Replenishment

    /// Mevcut PreKey stokunu kontrol eder ve eşik altındaysa yeni batch üretir.
    ///
    /// - Returns: Yeni üretilen PreKey listesi, veya yeterli stok varsa nil
    /// - Throws: PreKey generation hatası
    public func replenishPreKeysIfNeeded() async throws -> [PreKeyPublic]? {
        let availableCount = await protocolStore.getAvailablePreKeyCount()

        guard availableCount < Constants.preKeyRefreshThreshold else {
            return nil // Yeterli PreKey mevcut
        }

        print("🔄 Replenishing PreKeys (current: \(availableCount), threshold: \(Constants.preKeyRefreshThreshold))")

        let nextId = await protocolStore.getNextPreKeyId()
        let newPreKeys = try await generatePreKeyBatch(startId: nextId, count: Constants.preKeyBatchSize)

        // Yeni PreKey'leri store'a kaydet
        for preKey in newPreKeys {
            let stored = await protocolStore.preKeyStore.storePreKey(preKey.keyId, record: preKey.data)
            guard stored else {
                throw PreKeyError.storageFailure("Failed to store new prekey \(preKey.keyId)")
            }
        }

        let publicKeys = newPreKeys.map { PreKeyPublic(keyId: $0.keyId, publicKey: $0.publicKey) }

        print("✅ Generated \(newPreKeys.count) new PreKeys")
        return publicKeys
    }

    // MARK: - Signed PreKey Rotation

    /// Signed PreKey'i rotate eder. Yeni signed PreKey üretir ve store'a kaydeder.
    /// Eski signed PreKey'ler bir süre daha tutulur (geç gelen mesajlar için).
    ///
    /// GÜVENLIK: Identity key iOS Keychain'den okunur.
    ///
    /// - Throws: Key rotation hatası
    public func rotateSignedPreKey() async throws {
        print("🔄 Starting signed PreKey rotation")

        // Identity key pair'ı yükle
        guard let identityKeyData = await identityStore.getIdentityKeyPair() else {
            throw PreKeyError.missingIdentityKey("Identity key pair not found")
        }

        let identityKeyPair: SPKIdentityKeyPair
        do {
            identityKeyPair = try SPKIdentityKeyPair(keyData: identityKeyData)
        } catch {
            throw PreKeyError.invalidKeyData("Failed to load identity key pair: \(error)")
        }

        // Sıradaki signed PreKey ID'sini al
        let nextSignedPreKeyId = await protocolStore.signedPreKeyStore.getNextSignedPreKeyId()

        // Yeni signed PreKey üret
        let newSignedPreKey = try generateSignedPreKey(
            identityKeyPair: identityKeyPair,
            signedPreKeyId: nextSignedPreKeyId
        )

        // Yeni signed PreKey'i store'a kaydet
        let stored = await protocolStore.signedPreKeyStore.storeSignedPreKey(
            newSignedPreKey.keyId,
            record: newSignedPreKey.data
        )
        guard stored else {
            throw PreKeyError.storageFailure("Failed to store new signed prekey")
        }

        // Rotation zamanını güncelle
        await protocolStore.signedPreKeyStore.updateRotationTime(Date())

        // Eski signed PreKey'leri temizle
        let cleanedCount = await protocolStore.signedPreKeyStore.cleanupOldSignedPreKeys()

        // Identity key material'ı bellekten temizle
        var mutableKeyData = identityKeyData
        mutableKeyData.resetBytes(in: 0..<identityKeyData.count)

        print("✅ Signed PreKey rotated successfully (ID: \(nextSignedPreKeyId), cleaned: \(cleanedCount) old keys)")
    }

    /// Signed PreKey rotation'ın gerekli olup olmadığını kontrol eder.
    ///
    /// - Returns: true eğer rotation gerekiyorsa
    public func needsSignedPreKeyRotation() async -> Bool {
        return await protocolStore.signedPreKeyStore.needsRotation()
    }

    // MARK: - Key Generation Helpers

    /// PreKey batch üretir.
    ///
    /// - Parameters:
    ///   - startId: Başlangıç PreKey ID
    ///   - count: Üretilecek PreKey sayısı
    /// - Returns: Üretilen PreKey'ler
    /// - Throws: Key generation hatası
    private func generatePreKeyBatch(startId: UInt32, count: Int) async throws -> [PreKeyInfo] {
        var preKeys: [PreKeyInfo] = []

        for i in 0..<count {
            let preKeyId = (startId + UInt32(i)) % 16777215 // 24-bit max value

            do {
                let preKeyRecord = try SPKPreKeyRecord.generatePreKey(withId: preKeyId)
                let publicKeyData = preKeyRecord.publicKey().keyData

                let preKeyInfo = PreKeyInfo(
                    keyId: preKeyId,
                    data: preKeyRecord.data,
                    publicKey: publicKeyData
                )
                preKeys.append(preKeyInfo)
            } catch {
                throw PreKeyError.keyGenerationFailed("Failed to generate PreKey \(preKeyId): \(error)")
            }
        }

        return preKeys
    }

    /// Signed PreKey üretir.
    ///
    /// - Parameters:
    ///   - identityKeyPair: Identity key pair
    ///   - signedPreKeyId: Signed PreKey ID
    /// - Returns: Üretilen signed PreKey bilgisi
    /// - Throws: Key generation hatası
    private func generateSignedPreKey(
        identityKeyPair: SPKIdentityKeyPair,
        signedPreKeyId: UInt32
    ) throws -> SignedPreKeyInfo {
        do {
            let signedPreKeyRecord = try SPKSignedPreKeyRecord.generateSignedPreKey(
                withId: signedPreKeyId,
                identityKeyPair: identityKeyPair,
                generatedAt: Date()
            )

            let publicKeyData = signedPreKeyRecord.publicKey().keyData
            let signature = signedPreKeyRecord.signature()
            let timestamp = Int64(signedPreKeyRecord.generatedAt().timeIntervalSince1970 * 1000) // milliseconds

            return SignedPreKeyInfo(
                keyId: signedPreKeyId,
                data: signedPreKeyRecord.data,
                publicKey: publicKeyData,
                signature: signature,
                timestamp: timestamp
            )
        } catch {
            throw PreKeyError.keyGenerationFailed("Failed to generate signed PreKey: \(error)")
        }
    }

    /// Registration ID üretir (24-bit random).
    ///
    /// - Returns: Registration ID
    /// - Throws: Random number generation hatası
    private func generateRegistrationId() throws -> UInt32 {
        var randomBytes = [UInt8](repeating: 0, count: 3)
        let status = SecRandomCopyBytes(kSecRandomDefault, 3, &randomBytes)

        guard status == errSecSuccess else {
            throw PreKeyError.randomGenerationFailed("Failed to generate random bytes")
        }

        // 24-bit değer oluştur (0x000000 - 0xFFFFFF)
        let registrationId = UInt32(randomBytes[0]) << 16 |
                           UInt32(randomBytes[1]) << 8 |
                           UInt32(randomBytes[2])

        return registrationId & 0xFFFFFF // 24-bit mask
    }
}

// MARK: - Helper Models

private struct PreKeyInfo {
    let keyId: UInt32
    let data: Data
    let publicKey: Data
}

private struct SignedPreKeyInfo {
    let keyId: UInt32
    let data: Data
    let publicKey: Data
    let signature: Data
    let timestamp: Int64
}

// MARK: - PreKey Errors

public enum PreKeyError: LocalizedError {
    case keyGenerationFailed(String)
    case storageFailure(String)
    case missingIdentityKey(String)
    case invalidKeyData(String)
    case randomGenerationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let message):
            return "Key generation failed: \(message)"
        case .storageFailure(let message):
            return "Storage failure: \(message)"
        case .missingIdentityKey(let message):
            return "Missing identity key: \(message)"
        case .invalidKeyData(let message):
            return "Invalid key data: \(message)"
        case .randomGenerationFailed(let message):
            return "Random generation failed: \(message)"
        }
    }
}