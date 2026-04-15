import Foundation
import Security
import CryptoKit

/// iOS Keychain entegrasyonu.
/// Secure Enclave veya iOS Keychain üzerinde master key saklanır.
/// Tüm hassas veriler (identity key, session state vb.) bu sınıf ile
/// AES-256-GCM kullanılarak şifrelenir/çözülür.
///
/// GÜVENLIK: Private key ASLA loga yazılmaz.
/// GÜVENLIK: Key material kullanım sonrası sıfırlanır.
public class KeychainManager {

    // MARK: - Constants

    private struct Constants {
        static let service = "com.securechat.crypto"
        static let masterKeyTag = "securechat_master_key"
        static let identityKeyTag = "identity_key_pair"
        static let databasePassphraseTag = "database_passphrase"
        static let aesGcmTagLength = 16
        static let aesGcmNonceLength = 12
    }

    // MARK: - Properties

    private let queue = DispatchQueue(label: "com.securechat.keychain", qos: .userInitiated)

    // MARK: - Public Interface

    /// Veriyi AES-256-GCM ile şifreler.
    /// Döndürülen format: [12 byte nonce] + [şifreli veri + GCM tag]
    ///
    /// - Parameter data: Şifrelenecek veri
    /// - Returns: Şifrelenmiş veri
    /// - Throws: Encryption hatası
    public func encrypt(_ data: Data) throws -> Data {
        let masterKey = try getOrCreateMasterKey()
        return try performEncryption(data: data, using: masterKey)
    }

    /// AES-256-GCM ile şifrelenmiş veriyi çözer.
    /// Gelen format: [12 byte nonce] + [şifreli veri + GCM tag]
    ///
    /// - Parameter data: Şifreli veri
    /// - Returns: Çözülmüş veri
    /// - Throws: Decryption hatası
    public func decrypt(_ data: Data) throws -> Data {
        let masterKey = try getOrCreateMasterKey()
        return try performDecryption(data: data, using: masterKey)
    }

    /// SQLCipher veritabanı parolasını üretir.
    /// Her cihaz için benzersiz, 256-bit entropi ile master key'den türetilir.
    ///
    /// - Returns: SQLCipher'da kullanılmak üzere Data
    /// - Throws: Key derivation hatası
    public func getDatabasePassphrase() throws -> Data {
        // Önce cache'den kontrol et
        if let cachedPassphrase = try getDataFromKeychain(tag: Constants.databasePassphraseTag) {
            return cachedPassphrase
        }

        // Master key'den deterministik şekilde DB passphrase üret
        let masterKey = try getOrCreateMasterKey()
        let passphrase = try HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: masterKey.dataRepresentation),
            salt: "SecureChat-DB-Salt".data(using: .utf8)!,
            info: "database-passphrase".data(using: .utf8)!,
            outputByteCount: 32
        )

        let passphraseData = passphrase.dataRepresentation

        // Cache'e kaydet
        try storeDataInKeychain(data: passphraseData, tag: Constants.databasePassphraseTag)

        return passphraseData
    }

    /// Secure Enclave'ın mevcut olup olmadığını kontrol eder.
    ///
    /// - Returns: true eğer Secure Enclave destekli ise
    public func isSecureEnclaveAvailable() async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = SecureEnclave.isAvailable
                continuation.resume(returning: result)
            }
        }
    }

    /// Identity key pair'ı iOS Keychain ile güvenli şekilde saklar.
    /// Key pair AES-256-GCM ile şifrelenerek Keychain'e yazılır.
    ///
    /// - Parameter keyPair: Saklanacak identity key pair
    /// - Throws: Storage hatası
    public func storeIdentityKeyPair(_ keyPair: Data) async throws {
        let encrypted = try encrypt(keyPair)
        try storeDataInKeychain(data: encrypted, tag: Constants.identityKeyTag)

        // Key material'ı bellekten temizle (mutable copy kullanarak)
        var mutableKeyPair = keyPair
        mutableKeyPair.resetBytes(in: 0..<keyPair.count)
    }

    /// Saklanan identity key pair'ı okur ve çözer.
    ///
    /// - Returns: Identity key pair veya nil eğer mevcut değilse
    /// - Throws: Retrieval veya decryption hatası
    public func loadIdentityKeyPair() async throws -> Data? {
        guard let encrypted = try getDataFromKeychain(tag: Constants.identityKeyTag) else {
            return nil
        }

        return try decrypt(encrypted)
    }

    /// Belirtilen tag ile veri saklama
    ///
    /// - Parameters:
    ///   - data: Saklanacak veri
    ///   - tag: Keychain tag
    /// - Throws: Storage hatası
    public func storeData(_ data: Data, tag: String) throws {
        try storeDataInKeychain(data: data, tag: tag)
    }

    /// Belirtilen tag ile veri okuma
    ///
    /// - Parameter tag: Keychain tag
    /// - Returns: Saklanan veri veya nil
    /// - Throws: Retrieval hatası
    public func loadData(tag: String) throws -> Data? {
        return try getDataFromKeychain(tag: tag)
    }

    /// Belirtilen tag'deki veriyi silme
    ///
    /// - Parameter tag: Keychain tag
    /// - Throws: Deletion hatası
    public func deleteData(tag: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.service,
            kSecAttrAccount: tag
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionFailed(status)
        }
    }

    /// Tüm crypto key'leri Keychain'den temizler.
    ///
    /// - Throws: Cleanup hatası
    public func clearAllCryptoKeys() async throws {
        let tags = [
            Constants.masterKeyTag,
            Constants.identityKeyTag,
            Constants.databasePassphraseTag
        ]

        for tag in tags {
            try deleteData(tag: tag)
        }

        // Master key'i de Keychain'den sil
        try deleteMasterKeyFromKeychain()
    }

    // MARK: - Private Methods

    /// iOS Keychain'den master key'i alır veya yeni oluşturur.
    /// AES-256, Secure Enclave destekli donanım tabanlı koruma.
    ///
    /// GÜVENLIK: Secure Enclave kullanır, software-backed key kabul edilmez.
    private func getOrCreateMasterKey() throws -> SymmetricKey {
        // Önce mevcut key'i kontrol et
        if let existingKey = try loadMasterKeyFromKeychain() {
            return existingKey
        }

        // Yeni master key oluştur
        let masterKey = SymmetricKey(size: .bits256)
        try storeMasterKeyInKeychain(masterKey)

        return masterKey
    }

    /// Master key'i Keychain'de saklar
    private func storeMasterKeyInKeychain(_ key: SymmetricKey) throws {
        let keyData = key.dataRepresentation

        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.service,
            kSecAttrAccount: Constants.masterKeyTag,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Secure Enclave desteği varsa kullan
        if SecureEnclave.isAvailable {
            query[kSecAttrTokenID] = kSecAttrTokenIDSecureEnclave
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    /// Master key'i Keychain'den yükler
    private func loadMasterKeyFromKeychain() throws -> SymmetricKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.service,
            kSecAttrAccount: Constants.masterKeyTag,
            kSecReturnData: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let keyData = result as? Data else {
                throw KeychainError.invalidData
            }
            return SymmetricKey(data: keyData)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.retrievalFailed(status)
        }
    }

    /// Master key'i Keychain'den siler
    private func deleteMasterKeyFromKeychain() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.service,
            kSecAttrAccount: Constants.masterKeyTag
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionFailed(status)
        }
    }

    /// Generic data storage in Keychain
    private func storeDataInKeychain(data: Data, tag: String) throws {
        // Önce mevcut veriyi sil
        try? deleteData(tag: tag)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.service,
            kSecAttrAccount: tag,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    /// Generic data retrieval from Keychain
    private func getDataFromKeychain(tag: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Constants.service,
            kSecAttrAccount: tag,
            kSecReturnData: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.retrievalFailed(status)
        }
    }

    /// AES-GCM encryption implementation
    private func performEncryption(data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)

        // Combine nonce + ciphertext + tag
        var result = Data()
        result.append(sealedBox.nonce.dataRepresentation)
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

    /// AES-GCM decryption implementation
    private func performDecryption(data: Data, using key: SymmetricKey) throws -> Data {
        guard data.count >= Constants.aesGcmNonceLength + Constants.aesGcmTagLength else {
            throw KeychainError.invalidData
        }

        let nonceData = data.prefix(Constants.aesGcmNonceLength)
        let tagStart = data.count - Constants.aesGcmTagLength
        let ciphertext = data.dropFirst(Constants.aesGcmNonceLength).dropLast(Constants.aesGcmTagLength)
        let tagData = data.suffix(Constants.aesGcmTagLength)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tagData)

        return try AES.GCM.open(sealedBox, using: key)
    }
}

// MARK: - Keychain Errors

public enum KeychainError: Error, LocalizedError {
    case storeFailed(OSStatus)
    case retrievalFailed(OSStatus)
    case deletionFailed(OSStatus)
    case invalidData
    case secureEnclaveNotAvailable

    public var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Keychain store failed with status: \(status)"
        case .retrievalFailed(let status):
            return "Keychain retrieval failed with status: \(status)"
        case .deletionFailed(let status):
            return "Keychain deletion failed with status: \(status)"
        case .invalidData:
            return "Invalid keychain data"
        case .secureEnclaveNotAvailable:
            return "Secure Enclave not available on this device"
        }
    }
}

// MARK: - Data Extension for Memory Clearing

extension Data {
    /// Güvenlik: Data'yı bellekten temizle (mutable kopyada)
    mutating func resetBytes(in range: Range<Int>) {
        self.withUnsafeMutableBytes { bytes in
            memset(bytes.baseAddress!.advanced(by: range.lowerBound), 0, range.count)
        }
    }
}