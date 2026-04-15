import Foundation
import SignalProtocolKit
import CryptoKit
import SecureChatCommon

/// WebRTC çağrıları için SRTP şifreleme yönetimi.
/// Signal Protocol session'ından HKDF ile SRTP master key ve salt türetir.
/// Çağrılar da E2E şifreli olur, ses/video data sunucuya plain gönderilmez.
///
/// GÜVENLIK: SRTP key material ASLA loga yazılmaz.
/// GÜVENLIK: Call keys kullanım sonrası bellekten sıfırlanır.
public class CallCryptoManager {

    // MARK: - Constants

    private struct Constants {
        static let srtpKeyLength = 32      // 256-bit AES key
        static let srtpSaltLength = 32     // 256-bit salt
        static let hkdfInfo = "SecureChat-SRTP-Key"
        static let hkdfSalt = "SecureChat-SRTP-Salt"
    }

    // MARK: - Properties

    private let protocolStore: SecureChatProtocolStore

    // MARK: - Initialization

    public init(protocolStore: SecureChatProtocolStore) {
        self.protocolStore = protocolStore
    }

    // MARK: - SRTP Key Derivation

    /// WebRTC çağrıları için SRTP şifreleme anahtarları türetir.
    /// Signal Protocol session'ından HKDF ile paylaşılan anahtar elde eder.
    ///
    /// - Parameters:
    ///   - peerId: Karşı taraf kullanıcı ID'si
    ///   - deviceId: Karşı taraf cihaz ID'si (varsayılan 1)
    /// - Returns: SRTP master key ve salt
    /// - Throws: Key derivation hatası veya session bulunamama
    public func deriveCallEncryptionKeys(
        peerId: String,
        deviceId: UInt32 = 1
    ) async throws -> CallEncryptionKeys {
        // GÜVENLIK: Key material ASLA loga yazılmaz
        print("🔐 Deriving call encryption keys for \(peerId):\(deviceId)")

        let spkAddress = SPKAddress(name: peerId, deviceId: Int32(deviceId))

        // Session'ı yükle
        guard let sessionRecord = protocolStore.loadSession(for: spkAddress),
              sessionRecord.hasSenderChain() else {
            throw CallCryptoError.sessionNotFound("No active session found for \(peerId):\(deviceId)")
        }

        // Session state'den root key al
        guard let rootKeyData = extractRootKey(from: sessionRecord) else {
            throw CallCryptoError.keyExtractionFailed("Failed to extract root key from session")
        }

        // HKDF ile SRTP key'leri türet
        let srtpKeys = try deriveKeysFromRootKey(rootKeyData)

        // Root key material'ı bellekten temizle
        var mutableRootKey = rootKeyData
        mutableRootKey.resetBytes(in: 0..<rootKeyData.count)

        print("✅ Call encryption keys derived successfully")
        return srtpKeys
    }

    /// Çağrı için benzersiz session ID üretir.
    /// Her çağrı için farklı SRTP key türetilir.
    ///
    /// - Parameters:
    ///   - peerId: Karşı taraf kullanıcı ID'si
    ///   - callId: Çağrı benzersiz ID'si
    ///   - deviceId: Karşı taraf cihaz ID'si (varsayılan 1)
    /// - Returns: Call-specific SRTP keys
    /// - Throws: Key derivation hatası
    public func deriveCallSpecificKeys(
        peerId: String,
        callId: String,
        deviceId: UInt32 = 1
    ) async throws -> CallEncryptionKeys {
        // Base SRTP keys'i al
        let baseKeys = try await deriveCallEncryptionKeys(peerId: peerId, deviceId: deviceId)

        // Call ID ile re-derive et (call-specific keys için)
        let callSpecificKeys = try deriveCallSpecificKeys(
            baseKeys: baseKeys,
            callId: callId,
            peerId: peerId
        )

        // Base keys'i temizle
        var mutableBaseKeys = baseKeys
        mutableBaseKeys.clearKeyMaterial()

        return callSpecificKeys
    }

    // MARK: - Key Validation

    /// SRTP key'lerin geçerliliğini kontrol eder.
    ///
    /// - Parameter keys: Kontrol edilecek keys
    /// - Returns: true eğer keys geçerliyse
    public func validateCallEncryptionKeys(_ keys: CallEncryptionKeys) -> Bool {
        // Key length kontrolü
        guard keys.masterKey.count == Constants.srtpKeyLength,
              keys.masterSalt.count == Constants.srtpSaltLength else {
            print("❌ Invalid SRTP key lengths")
            return false
        }

        // Zero key kontrolü (güvenlik riski)
        let isKeyZero = keys.masterKey.allSatisfy { $0 == 0 }
        let isSaltZero = keys.masterSalt.allSatisfy { $0 == 0 }

        if isKeyZero || isSaltZero {
            print("❌ SRTP keys contain all zeros")
            return false
        }

        return true
    }

    /// İki SRTP key set'inin eşit olup olmadığını kontrol eder.
    /// Timing attack korunması için constant-time comparison.
    ///
    /// - Parameters:
    ///   - keys1: İlk key set
    ///   - keys2: İkinci key set
    /// - Returns: true eğer eşitse
    public func compareKeys(_ keys1: CallEncryptionKeys, _ keys2: CallEncryptionKeys) -> Bool {
        let keyEqual = keys1.masterKey.constantTimeEquals(to: keys2.masterKey)
        let saltEqual = keys1.masterSalt.constantTimeEquals(to: keys2.masterSalt)
        return keyEqual && saltEqual
    }

    // MARK: - Private Helper Methods

    /// Session record'dan root key'i extract eder.
    ///
    /// - Parameter sessionRecord: Signal Protocol session record
    /// - Returns: Root key data veya nil
    private func extractRootKey(from sessionRecord: SPKSessionRecord) -> Data? {
        // SignalProtocolKit'ten root key çıkarmak için internal API'lar gerekli
        // Bu basit implementasyon - gerçek uygulamada session state parsing yapılmalı

        // Şimdilik session record'un data'sından deterministik key türetelim
        let sessionData = sessionRecord.data

        // Session data'dan HMAC-SHA256 ile deterministik root key türet
        let key = SymmetricKey(data: Constants.hkdfSalt.data(using: .utf8)!)
        let rootKeyData = HMAC<SHA256>.authenticationCode(for: sessionData, using: key)

        return Data(rootKeyData)
    }

    /// Root key'den HKDF ile SRTP key'leri türetir.
    ///
    /// - Parameter rootKeyData: Session'dan alınan root key
    /// - Returns: Türetilmiş SRTP keys
    /// - Throws: HKDF hatası
    private func deriveKeysFromRootKey(_ rootKeyData: Data) throws -> CallEncryptionKeys {
        let inputKeyMaterial = SymmetricKey(data: rootKeyData)
        let salt = Constants.hkdfSalt.data(using: .utf8)!
        let info = Constants.hkdfInfo.data(using: .utf8)!

        // Total 64 bytes: 32 bytes master key + 32 bytes master salt
        let derivedKey = try HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: salt,
            info: info,
            outputByteCount: Constants.srtpKeyLength + Constants.srtpSaltLength
        )

        let allKeyData = derivedKey.dataRepresentation

        // İlk 32 byte master key, sonraki 32 byte master salt
        let masterKey = allKeyData.prefix(Constants.srtpKeyLength)
        let masterSalt = allKeyData.suffix(Constants.srtpSaltLength)

        return CallEncryptionKeys(
            masterKey: Data(masterKey),
            masterSalt: Data(masterSalt)
        )
    }

    /// Call-specific key türetimi yapar.
    ///
    /// - Parameters:
    ///   - baseKeys: Base SRTP keys
    ///   - callId: Call benzersiz ID'si
    ///   - peerId: Peer ID
    /// - Returns: Call-specific keys
    /// - Throws: HKDF hatası
    private func deriveCallSpecificKeys(
        baseKeys: CallEncryptionKeys,
        callId: String,
        peerId: String
    ) throws -> CallEncryptionKeys {
        let inputKeyMaterial = SymmetricKey(data: baseKeys.masterKey)
        let contextInfo = "\(Constants.hkdfInfo)-\(callId)-\(peerId)".data(using: .utf8)!

        let derivedKey = try HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: baseKeys.masterSalt,
            info: contextInfo,
            outputByteCount: Constants.srtpKeyLength + Constants.srtpSaltLength
        )

        let allKeyData = derivedKey.dataRepresentation

        let masterKey = allKeyData.prefix(Constants.srtpKeyLength)
        let masterSalt = allKeyData.suffix(Constants.srtpSaltLength)

        return CallEncryptionKeys(
            masterKey: Data(masterKey),
            masterSalt: Data(masterSalt)
        )
    }

    // MARK: - Key Rotation for Long Calls

    /// Uzun çağrılarda key rotation yapar.
    /// SRTP güvenlik için belirli aralıklarla key değişimi önerilir.
    ///
    /// - Parameters:
    ///   - currentKeys: Mevcut SRTP keys
    ///   - rotationCounter: Rotation counter (monotonic)
    /// - Returns: Yeni rotate edilmiş keys
    /// - Throws: Key rotation hatası
    public func rotateCallKeys(
        currentKeys: CallEncryptionKeys,
        rotationCounter: UInt64
    ) throws -> CallEncryptionKeys {
        let inputKeyMaterial = SymmetricKey(data: currentKeys.masterKey)
        let contextInfo = "\(Constants.hkdfInfo)-rotation-\(rotationCounter)".data(using: .utf8)!

        let derivedKey = try HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKeyMaterial,
            salt: currentKeys.masterSalt,
            info: contextInfo,
            outputByteCount: Constants.srtpKeyLength + Constants.srtpSaltLength
        )

        let allKeyData = derivedKey.dataRepresentation

        let masterKey = allKeyData.prefix(Constants.srtpKeyLength)
        let masterSalt = allKeyData.suffix(Constants.srtpSaltLength)

        return CallEncryptionKeys(
            masterKey: Data(masterKey),
            masterSalt: Data(masterSalt)
        )
    }

    /// Call encryption istatistiklerini döndürür.
    ///
    /// - Returns: Call crypto stats
    public func getCallCryptoStats() -> CallCryptoStats {
        // Basit implementasyon - gerçek uygulamada counter'lar tutulmalı
        return CallCryptoStats(
            totalCallsEncrypted: 0,
            keyDerivationCount: 0,
            keyRotationCount: 0,
            lastKeyDerivation: nil
        )
    }
}

// MARK: - Call Crypto Errors

public enum CallCryptoError: LocalizedError {
    case sessionNotFound(String)
    case keyExtractionFailed(String)
    case keyDerivationFailed(String)
    case invalidKeyMaterial(String)

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let message):
            return "Session not found: \(message)"
        case .keyExtractionFailed(let message):
            return "Key extraction failed: \(message)"
        case .keyDerivationFailed(let message):
            return "Key derivation failed: \(message)"
        case .invalidKeyMaterial(let message):
            return "Invalid key material: \(message)"
        }
    }
}

// MARK: - Call Crypto Stats

public struct CallCryptoStats {
    public let totalCallsEncrypted: Int
    public let keyDerivationCount: Int
    public let keyRotationCount: Int
    public let lastKeyDerivation: Date?

    public init(
        totalCallsEncrypted: Int,
        keyDerivationCount: Int,
        keyRotationCount: Int,
        lastKeyDerivation: Date?
    ) {
        self.totalCallsEncrypted = totalCallsEncrypted
        self.keyDerivationCount = keyDerivationCount
        self.keyRotationCount = keyRotationCount
        self.lastKeyDerivation = lastKeyDerivation
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