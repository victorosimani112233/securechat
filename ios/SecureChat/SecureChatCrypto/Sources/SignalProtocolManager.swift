import Foundation
import SignalProtocolKit
import Security
import SecureChatCommon

/// Ana Signal Protocol yönetim sınıfı.
/// iOS için SignalProtocolKit kullanarak E2E şifreleme sağlar.
/// Android crypto modülü ile uyumlu cross-platform messaging desteği.
///
/// GÜVENLIK: Private key'ler iOS Keychain'de saklanır.
/// GÜVENLIK: Plaintext mesaj içeriği ASLA loga yazılmaz.
public class SignalProtocolManager {

    // MARK: - Constants

    private struct Constants {
        static let preKeyBatchSize = 100
        static let preKeyRefreshThreshold = 20
        static let signedPreKeyRotationDays: TimeInterval = 7 * 24 * 60 * 60 // 7 days in seconds
    }

    // MARK: - Properties

    private let keychainManager: KeychainManager
    private let identityStore: CryptoIdentityStore
    private let preKeyStore: CryptoPreKeyStore
    private let signedPreKeyStore: CryptoSignedPreKeyStore
    private let sessionStore: CryptoSessionStore
    private let signalProtocolStore: SignalProtocolStore

    private let sessionManager: SessionManager
    private let messageEncryptor: MessageEncryptor
    private let preKeyManager: PreKeyManager
    private let callCryptoManager: CallCryptoManager

    // MARK: - Initialization

    public init() {
        self.keychainManager = KeychainManager()

        // Initialize key stores
        self.identityStore = CryptoIdentityStore(keychainManager: keychainManager)
        self.preKeyStore = CryptoPreKeyStore(keychainManager: keychainManager)
        self.signedPreKeyStore = CryptoSignedPreKeyStore(keychainManager: keychainManager)
        self.sessionStore = CryptoSessionStore(keychainManager: keychainManager)

        // Initialize protocol store
        self.signalProtocolStore = SecureChatProtocolStore(
            identityStore: identityStore,
            preKeyStore: preKeyStore,
            signedPreKeyStore: signedPreKeyStore,
            sessionStore: sessionStore
        )

        // Initialize managers
        self.sessionManager = SessionManager(protocolStore: signalProtocolStore)
        self.messageEncryptor = MessageEncryptor(protocolStore: signalProtocolStore)
        self.preKeyManager = PreKeyManager(
            protocolStore: signalProtocolStore,
            identityStore: identityStore,
            keychainManager: keychainManager
        )
        self.callCryptoManager = CallCryptoManager(protocolStore: signalProtocolStore)
    }

    // MARK: - Public Interface

    /// Uygulama ilk başlatıldığında kriptografik anahtarları oluşturur.
    /// Identity key pair, registration ID, one-time PreKey'ler ve signed PreKey üretir.
    ///
    /// GÜVENLIK: Identity key pair iOS Keychain ile korunur.
    ///
    /// - Returns: Üretilen key bundle (sunucuya gönderilmek üzere)
    /// - Throws: Key generation veya storage hatası
    public func initializeKeys() async throws -> KeyBundle {
        return try await preKeyManager.generateInitialKeys()
    }

    /// Mesajı Signal Protocol ile şifreler.
    /// Double Ratchet Algorithm ile her mesaj için benzersiz anahtar kullanır.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - plaintext: Şifrelenecek düz metin
    ///   - deviceId: Alıcı cihaz ID'si (varsayılan 1)
    /// - Returns: Şifrelenmiş mesaj zarfı
    /// - Throws: Encryption hatası veya session bulunamama
    public func encryptMessage(
        to recipientId: String,
        plaintext: Data,
        deviceId: UInt32 = 1
    ) async throws -> EncryptedEnvelope {
        return try await messageEncryptor.encrypt(
            recipientId: recipientId,
            plaintext: plaintext,
            deviceId: deviceId
        )
    }

    /// Şifrelenmiş mesajı çözümler.
    /// Double Ratchet Algorithm ile forward secrecy ve out-of-order message handling sağlar.
    ///
    /// - Parameters:
    ///   - senderId: Gönderen kullanıcı ID'si
    ///   - envelope: Şifrelenmiş mesaj zarfı
    ///   - deviceId: Gönderen cihaz ID'si (varsayılan 1)
    /// - Returns: Çözülmüş plaintext
    /// - Throws: Decryption hatası veya invalid message
    public func decryptMessage(
        from senderId: String,
        envelope: EncryptedEnvelope,
        deviceId: UInt32 = 1
    ) async throws -> Data {
        return try await messageEncryptor.decrypt(
            senderId: senderId,
            envelope: envelope,
            deviceId: deviceId
        )
    }

    /// Yeni bir session oluşturur ve SessionCipher döndürür.
    /// X3DH key agreement bu metod içerisinde gerçekleşir.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcının kullanıcı ID'si
    ///   - deviceId: Alıcının cihaz ID'si
    ///   - preKeyBundle: Alıcının public key bundle'ı
    /// - Throws: Session creation hatası
    public func createSession(
        with recipientId: String,
        deviceId: UInt32 = 1,
        preKeyBundle: SPKPreKeyBundle
    ) async throws {
        let address = SignalAddress(name: recipientId, deviceId: deviceId)
        try await sessionManager.createSession(recipientAddress: address, preKeyBundle: preKeyBundle)
    }

    /// Belirtilen kullanıcı ile aktif bir session olup olmadığını kontrol eder.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - deviceId: Cihaz ID'si (varsayılan 1)
    /// - Returns: Session mevcutsa true
    public func hasSession(with recipientId: String, deviceId: UInt32 = 1) async -> Bool {
        return await sessionManager.hasSession(recipientId: recipientId, deviceId: deviceId)
    }

    /// Mevcut PreKey stokunu kontrol eder ve eşik altındaysa yeni batch üretir.
    ///
    /// - Returns: Yeni üretilen PreKey listesi, veya yeterli stok varsa nil
    /// - Throws: PreKey generation hatası
    public func replenishPreKeysIfNeeded() async throws -> [PreKeyPublic]? {
        return try await preKeyManager.replenishPreKeysIfNeeded()
    }

    /// Signed PreKey'i rotate eder. Yeni signed PreKey üretir ve store'a kaydeder.
    /// Eski signed PreKey'ler bir süre daha tutulur (geç gelen mesajlar için).
    ///
    /// GÜVENLIK: Identity key iOS Keychain'den okunur.
    ///
    /// - Throws: Key rotation hatası
    public func rotateSignedPreKey() async throws {
        try await preKeyManager.rotateSignedPreKey()
    }

    /// WebRTC çağrıları için SRTP şifreleme anahtarları türetir.
    /// Signal Protocol session'ından HKDF ile paylaşılan anahtar elde eder.
    ///
    /// - Parameters:
    ///   - peerId: Karşı taraf kullanıcı ID'si
    ///   - deviceId: Karşı taraf cihaz ID'si (varsayılan 1)
    /// - Returns: SRTP master key ve salt
    /// - Throws: Key derivation hatası veya session bulunamama
    public func deriveCallEncryptionKeys(
        for peerId: String,
        deviceId: UInt32 = 1
    ) async throws -> CallEncryptionKeys {
        return try await callCryptoManager.deriveCallEncryptionKey(peerId: peerId, deviceId: deviceId)
    }

    /// Güvenlik durumunu kontrol eder.
    /// Master key'in hardware-backed olup olmadığını ve diğer güvenlik ayarlarını doğrular.
    ///
    /// - Returns: Güvenlik durumu raporu
    public func getSecurityStatus() async -> SecurityStatus {
        let isKeychainSecure = await keychainManager.isSecureEnclaveAvailable()
        let hasIdentityKey = await identityStore.hasIdentityKey()

        return SecurityStatus(
            isKeychainSecure: isKeychainSecure,
            hasIdentityKey: hasIdentityKey,
            lastSignedPreKeyRotation: await signedPreKeyStore.getLastRotationTime()
        )
    }

    /// Tüm session'ları ve key'leri temizler. Logout işlemi sırasında kullanılır.
    ///
    /// GÜVENLIK: Tüm key material bellekten ve storage'dan silinir.
    ///
    /// - Throws: Cleanup hatası
    public func clearAllData() async throws {
        try await sessionStore.deleteAllSessions()
        try await preKeyStore.removeAllPreKeys()
        try await signedPreKeyStore.removeAllSignedPreKeys()
        try await identityStore.deleteIdentityKey()
        try await keychainManager.clearAllCryptoKeys()
    }
}

// MARK: - Security Status

/// Güvenlik durumu raporu
public struct SecurityStatus {
    public let isKeychainSecure: Bool
    public let hasIdentityKey: Bool
    public let lastSignedPreKeyRotation: Date?

    public init(isKeychainSecure: Bool, hasIdentityKey: Bool, lastSignedPreKeyRotation: Date?) {
        self.isKeychainSecure = isKeychainSecure
        self.hasIdentityKey = hasIdentityKey
        self.lastSignedPreKeyRotation = lastSignedPreKeyRotation
    }

    public var needsSignedPreKeyRotation: Bool {
        guard let lastRotation = lastSignedPreKeyRotation else { return true }
        return Date().timeIntervalSince(lastRotation) > Constants.signedPreKeyRotationDays
    }
}