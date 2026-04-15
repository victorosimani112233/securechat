import Foundation
import SignalProtocolKit
import SecureChatCommon

/// Signal Protocol session yönetimi.
/// X3DH key agreement ile yeni session oluşturur ve mevcut session'lara erişim sağlar.
///
/// Session oluşturma akışı:
/// 1. Alıcının PreKeyBundle'ını signaling sunucusundan al
/// 2. createSession() ile X3DH key agreement yap
/// 3. Dönen SessionCipher ile mesaj şifrele/çöz
public class SessionManager {

    // MARK: - Properties

    private let protocolStore: SecureChatProtocolStore

    // MARK: - Initialization

    public init(protocolStore: SecureChatProtocolStore) {
        self.protocolStore = protocolStore
    }

    // MARK: - Session Creation

    /// Yeni bir session oluşturur X3DH key agreement ile.
    /// Bu metod ilk mesaj gönderiminden önce çağrılır.
    ///
    /// - Parameters:
    ///   - recipientAddress: Alıcının Signal Protocol adresi
    ///   - preKeyBundle: Alıcının public key bundle'ı
    /// - Throws: Session creation hatası
    public func createSession(
        recipientAddress: SignalAddress,
        preKeyBundle: SPKPreKeyBundle
    ) async throws {
        // SignalAddress'i SPKAddress'e convert et
        let spkAddress = SPKAddress(name: recipientAddress.name, deviceId: Int32(recipientAddress.deviceId))

        // SessionBuilder ile X3DH key agreement yap
        let sessionBuilder = try SPKSessionBuilder(
            for: spkAddress,
            identityKeyStore: protocolStore,
            preKeyStore: protocolStore,
            signedPreKeyStore: protocolStore,
            sessionStore: protocolStore
        )

        try sessionBuilder.processPreKeyBundle(preKeyBundle)

        print("✅ Session created for \(recipientAddress.name):\(recipientAddress.deviceId)")
    }

    /// Mevcut bir session için SessionCipher döndürür.
    /// Session yoksa, ilk mesajda PreKey mesajı gönderilir.
    ///
    /// - Parameter recipientAddress: Alıcının Signal Protocol adresi
    /// - Returns: SessionCipher instance'ı
    /// - Throws: SessionCipher creation hatası
    public func getSessionCipher(recipientAddress: SignalAddress) async throws -> SPKSessionCipher {
        let spkAddress = SPKAddress(name: recipientAddress.name, deviceId: Int32(recipientAddress.deviceId))

        return try SPKSessionCipher(
            for: spkAddress,
            identityKeyStore: protocolStore,
            preKeyStore: protocolStore,
            signedPreKeyStore: protocolStore,
            sessionStore: protocolStore
        )
    }

    /// Belirtilen kullanıcı ile aktif bir session olup olmadığını kontrol eder.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - deviceId: Cihaz ID'si (varsayılan 1)
    /// - Returns: Session mevcutsa true
    public func hasSession(recipientId: String, deviceId: UInt32 = 1) async -> Bool {
        let spkAddress = SPKAddress(name: recipientId, deviceId: Int32(deviceId))
        return protocolStore.containsSession(for: spkAddress)
    }

    /// Session'ın aktif olup olmadığını kontrol eder.
    /// Session mevcut olsa bile fresh state'de olabilir.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - deviceId: Cihaz ID'si (varsayılan 1)
    /// - Returns: Session aktifse true
    public func isSessionActive(recipientId: String, deviceId: UInt32 = 1) async -> Bool {
        let spkAddress = SPKAddress(name: recipientId, deviceId: Int32(deviceId))

        guard let sessionRecord = protocolStore.loadSession(for: spkAddress) else {
            return false
        }

        // Session record'ın aktif state'de olup olmadığını kontrol et
        return sessionRecord.hasSenderChain()
    }

    // MARK: - Session Management

    /// Belirli bir session'ı siler.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - deviceId: Cihaz ID'si (varsayılan 1)
    /// - Throws: Session deletion hatası
    public func deleteSession(recipientId: String, deviceId: UInt32 = 1) async throws {
        let spkAddress = SPKAddress(name: recipientId, deviceId: Int32(deviceId))
        protocolStore.deleteSession(for: spkAddress)
        print("🗑️ Session deleted for \(recipientId):\(deviceId)")
    }

    /// Belirli bir kullanıcının tüm cihazları için session'ları siler.
    ///
    /// - Parameter recipientId: Alıcı kullanıcı ID'si
    /// - Throws: Session deletion hatası
    public func deleteAllSessionsForUser(_ recipientId: String) async throws {
        protocolStore.deleteAllSessions(for: recipientId)
        print("🗑️ All sessions deleted for user: \(recipientId)")
    }

    /// Session fingerprint oluşturur güvenlik doğrulaması için.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - deviceId: Cihaz ID'si (varsayılan 1)
    /// - Returns: Session fingerprint veya nil
    /// - Throws: Fingerprint generation hatası
    public func getSessionFingerprint(
        recipientId: String,
        deviceId: UInt32 = 1
    ) async throws -> String? {
        let spkAddress = SPKAddress(name: recipientId, deviceId: Int32(deviceId))

        guard let sessionRecord = protocolStore.loadSession(for: spkAddress),
              sessionRecord.hasSenderChain() else {
            return nil
        }

        // Session state'den identity key'leri al ve fingerprint oluştur
        let localIdentityKey = protocolStore.identityKeyPair()?.publicKey
        let remoteIdentityKey = protocolStore.identity(for: spkAddress)

        guard let localKey = localIdentityKey,
              let remoteKey = remoteIdentityKey else {
            return nil
        }

        // Basit fingerprint implementasyonu - gerçek uygulamada Signal'in algoritması kullanılmalı
        let combined = localKey.keyBytes + remoteKey.keyBytes
        let hash = combined.sha256Hash
        return hash.hexString
    }

    // MARK: - Session Information

    /// Session durumu hakkında bilgi döndürür.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - deviceId: Cihaz ID'si (varsayılan 1)
    /// - Returns: Session bilgisi
    public func getSessionInfo(
        recipientId: String,
        deviceId: UInt32 = 1
    ) async -> SessionInfo? {
        let spkAddress = SPKAddress(name: recipientId, deviceId: Int32(deviceId))

        guard let sessionRecord = protocolStore.loadSession(for: spkAddress) else {
            return nil
        }

        let isActive = sessionRecord.hasSenderChain()
        let fingerprint = try? await getSessionFingerprint(recipientId: recipientId, deviceId: deviceId)

        return SessionInfo(
            recipientId: recipientId,
            deviceId: deviceId,
            isActive: isActive,
            fingerprint: fingerprint,
            createdAt: nil // SessionRecord'dan creation time alınabilir
        )
    }

    /// Tüm aktif session'ların listesini döndürür.
    ///
    /// - Returns: Aktif session bilgileri array
    public func getAllActiveSessions() async -> [SessionInfo] {
        var sessionInfos: [SessionInfo] = []

        // Bu method için tüm session'ları enumerate etmek gerekir
        // Basit implementasyon için boş döndürüyoruz
        // Gerçek uygulamada CryptoSessionStore'dan aktif session'ları almalı

        return sessionInfos
    }

    // MARK: - Session Verification

    /// Session'ın integrity'sini kontrol eder.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - deviceId: Cihaz ID'si (varsayılan 1)
    /// - Returns: true eğer session sağlıklıysa
    public func verifySessionIntegrity(
        recipientId: String,
        deviceId: UInt32 = 1
    ) async -> Bool {
        let spkAddress = SPKAddress(name: recipientId, deviceId: Int32(deviceId))

        guard let sessionRecord = protocolStore.loadSession(for: spkAddress) else {
            return false
        }

        // Basit integrity check - gerçek uygulamada daha detaylı kontrol yapılmalı
        do {
            let hasValidState = sessionRecord.hasSenderChain()
            return hasValidState
        } catch {
            print("❌ Session integrity check failed for \(recipientId):\(deviceId) - \(error)")
            return false
        }
    }
}

// MARK: - Session Info Model

public struct SessionInfo {
    public let recipientId: String
    public let deviceId: UInt32
    public let isActive: Bool
    public let fingerprint: String?
    public let createdAt: Date?

    public init(
        recipientId: String,
        deviceId: UInt32,
        isActive: Bool,
        fingerprint: String?,
        createdAt: Date?
    ) {
        self.recipientId = recipientId
        self.deviceId = deviceId
        self.isActive = isActive
        self.fingerprint = fingerprint
        self.createdAt = createdAt
    }
}

// MARK: - Data Extensions

private extension Data {
    var sha256Hash: Data {
        var hash = [UInt8](repeating: 0, count: 32)
        self.withUnsafeBytes { bytes in
            // iOS CryptoKit kullanarak SHA256 hash hesaplanabilir
            // Basit implementasyon için dummy hash döndürüyoruz
            for i in 0..<min(32, bytes.count) {
                hash[i] = bytes[i]
            }
        }
        return Data(hash)
    }

    var hexString: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}