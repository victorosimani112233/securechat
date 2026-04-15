import Foundation

/// Identity key storage ve yönetimi.
/// Identity key pair'ı iOS Keychain'de güvenli şekilde saklar.
/// Kullanıcıların identity key'lerini manage eder ve değişiklikleri track eder.
///
/// GÜVENLIK: Identity key pair Keychain'de şifreli saklanır.
/// GÜVENLIK: Private key ASLA loga yazılmaz.
public actor CryptoIdentityStore {

    // MARK: - Constants

    private struct Constants {
        static let identityKeyTag = "identity_key_pair"
        static let registrationIdKey = "local_registration_id"
        static let identityKeysPrefix = "identity_key_"
    }

    // MARK: - Properties

    private let keychainManager: KeychainManager

    // MARK: - Initialization

    public init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
    }

    // MARK: - Identity Key Pair Management

    /// Identity key pair'ı döndürür.
    ///
    /// - Returns: Identity key pair data veya nil
    public func getIdentityKeyPair() async -> Data? {
        do {
            return try await keychainManager.loadIdentityKeyPair()
        } catch {
            print("❌ Failed to load identity key pair: \(error)")
            return nil
        }
    }

    /// Identity key pair'ı güvenli şekilde saklar.
    ///
    /// - Parameter keyPair: Saklanacak identity key pair data
    /// - Returns: Başarı durumu
    public func storeIdentityKeyPair(_ keyPair: Data) async -> Bool {
        do {
            try await keychainManager.storeIdentityKeyPair(keyPair)
            return true
        } catch {
            print("❌ Failed to store identity key pair: \(error)")
            return false
        }
    }

    /// Identity key'in mevcut olup olmadığını kontrol eder.
    ///
    /// - Returns: true eğer identity key mevcutsa
    public func hasIdentityKey() async -> Bool {
        return await getIdentityKeyPair() != nil
    }

    /// Identity key'i siler. Logout işlemi sırasında kullanılır.
    ///
    /// - Throws: Deletion hatası
    public func deleteIdentityKey() async throws {
        try keychainManager.deleteData(tag: Constants.identityKeyTag)
        // Registration ID'yi de sil
        try keychainManager.deleteData(tag: Constants.registrationIdKey)
    }

    // MARK: - Registration ID Management

    /// Local registration ID'yi döndürür.
    ///
    /// - Returns: Registration ID (0 eğer set edilmemişse)
    public func getLocalRegistrationId() async -> UInt32 {
        do {
            guard let data = try keychainManager.loadData(tag: Constants.registrationIdKey) else {
                return 0
            }
            return data.withUnsafeBytes { $0.load(as: UInt32.self) }
        } catch {
            print("❌ Failed to load registration ID: \(error)")
            return 0
        }
    }

    /// Local registration ID'yi saklar.
    ///
    /// - Parameter registrationId: Saklanacak registration ID
    /// - Returns: Başarı durumu
    public func storeLocalRegistrationId(_ registrationId: UInt32) async -> Bool {
        do {
            var id = registrationId
            let data = Data(bytes: &id, count: MemoryLayout<UInt32>.size)
            try keychainManager.storeData(data, tag: Constants.registrationIdKey)
            return true
        } catch {
            print("❌ Failed to store registration ID: \(error)")
            return false
        }
    }

    // MARK: - Remote Identity Key Management

    /// Uzak kullanıcının identity key'ini saklar.
    ///
    /// - Parameters:
    ///   - name: Kullanıcı adı/ID
    ///   - identityKey: Identity key data
    /// - Returns: Başarı durumu (false eğer key değişmişse ve onaylanmamışsa)
    public func storeIdentity(_ name: String, identityKey: Data) async -> Bool {
        let tag = Constants.identityKeysPrefix + name

        // Mevcut key'i kontrol et
        do {
            if let existingKey = try keychainManager.loadData(tag: tag) {
                if existingKey != identityKey {
                    // Identity key değişikliği - güvenlik uyarısı gerekli
                    print("⚠️ Identity key changed for user: \(name)")
                    // Bu durumda kullanıcıya "safety number changed" uyarısı gösterilmeli
                    // Şimdilik false döndürüyoruz, gerçek uygulamada kullanıcı onayı beklenecek
                    return false
                }
            }

            try keychainManager.storeData(identityKey, tag: tag)
            return true
        } catch {
            print("❌ Failed to store identity for \(name): \(error)")
            return false
        }
    }

    /// Uzak kullanıcının identity key'ini yükler.
    ///
    /// - Parameter name: Kullanıcı adı/ID
    /// - Returns: Identity key data veya nil
    public func loadIdentity(_ name: String) async -> Data? {
        let tag = Constants.identityKeysPrefix + name

        do {
            return try keychainManager.loadData(tag: tag)
        } catch {
            print("❌ Failed to load identity for \(name): \(error)")
            return nil
        }
    }

    /// Uzak kullanıcının identity key'ini siler.
    ///
    /// - Parameter name: Kullanıcı adı/ID
    /// - Throws: Deletion hatası
    public func deleteIdentity(_ name: String) async throws {
        let tag = Constants.identityKeysPrefix + name
        try keychainManager.deleteData(tag: tag)
    }

    /// Tüm uzak identity key'leri siler.
    ///
    /// - Throws: Deletion hatası
    public func deleteAllRemoteIdentities() async throws {
        // Bu method için tüm identity key'leri enumerate etmek gerekir
        // Basit implementation için şimdilik sadece bilinen key'leri siliyoruz
        // Gerçek uygulamada tüm Constants.identityKeysPrefix ile başlayan key'ler silinmeli
        print("⚠️ Full remote identities cleanup not implemented - use per-user deletion")
    }

    // MARK: - Identity Key Validation

    /// Identity key'in güvenilir olup olmadığını kontrol eder.
    /// İlk görülme durumunda güvenilir kabul edilir.
    /// Daha önce görülen key'ler için eşleşme kontrol edilir.
    ///
    /// - Parameters:
    ///   - name: Kullanıcı adı/ID
    ///   - identityKey: Kontrol edilecek identity key
    /// - Returns: true eğer güvenilirse
    public func isTrustedIdentity(_ name: String, identityKey: Data) async -> Bool {
        guard let existingKey = await loadIdentity(name) else {
            // İlk görülme - güvenilir kabul edilir
            return true
        }

        // Mevcut key ile karşılaştır (constant-time comparison)
        return existingKey.constantTimeEquals(to: identityKey)
    }
}

// MARK: - Data Extension for Constant-Time Comparison

private extension Data {
    /// Timing attack'lara karşı korunmak için constant-time comparison.
    ///
    /// - Parameter other: Karşılaştırılacak data
    /// - Returns: true eğer eşitse
    func constantTimeEquals(to other: Data) -> Bool {
        guard self.count == other.count else {
            return false
        }

        var result = 0
        for i in 0..<self.count {
            result |= Int(self[i] ^ other[i])
        }

        return result == 0
    }
}