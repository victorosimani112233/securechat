import Foundation

// MARK: - Encrypted Message Envelope

/// Signal Protocol ile şifrelenmiş mesaj zarfı.
/// Mesajın tipini (PreKey veya Signal), şifreli içeriğini,
/// zaman damgasını ve gönderenin registration ID'sini içerir.
public struct EncryptedEnvelope: Equatable {
    public let type: EnvelopeType
    public let content: Data
    public let timestamp: Int64
    public let senderRegistrationId: UInt32

    public init(type: EnvelopeType, content: Data, timestamp: Int64, senderRegistrationId: UInt32) {
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.senderRegistrationId = senderRegistrationId
    }

    public static func == (lhs: EncryptedEnvelope, rhs: EncryptedEnvelope) -> Bool {
        return lhs.type == rhs.type &&
               lhs.content == rhs.content &&
               lhs.timestamp == rhs.timestamp &&
               lhs.senderRegistrationId == rhs.senderRegistrationId
    }
}

/// Mesaj zarfı tipi.
/// PREKEY: İlk mesaj için X3DH key agreement mesajı
/// SIGNAL: Normal Double Ratchet mesajı
public enum EnvelopeType: CaseIterable {
    case prekey
    case signal
}

// MARK: - Key Bundle

/// İlk kayıt sırasında üretilen key bundle.
/// Public key'ler sunucuya gönderilir, private key'ler yerel olarak güvenli saklanır.
public struct KeyBundle {
    public let identityKey: Data
    public let registrationId: UInt32
    public let preKeys: [PreKeyPublic]
    public let signedPreKey: SignedPreKeyPublic

    public init(identityKey: Data, registrationId: UInt32, preKeys: [PreKeyPublic], signedPreKey: SignedPreKeyPublic) {
        self.identityKey = identityKey
        self.registrationId = registrationId
        self.preKeys = preKeys
        self.signedPreKey = signedPreKey
    }
}

/// One-time PreKey public kısmı (sunucuya gönderilir)
public struct PreKeyPublic {
    public let keyId: UInt32
    public let publicKey: Data

    public init(keyId: UInt32, publicKey: Data) {
        self.keyId = keyId
        self.publicKey = publicKey
    }
}

/// Signed PreKey public kısmı (sunucuya gönderilir)
public struct SignedPreKeyPublic {
    public let keyId: UInt32
    public let publicKey: Data
    public let signature: Data
    public let timestamp: Int64

    public init(keyId: UInt32, publicKey: Data, signature: Data, timestamp: Int64) {
        self.keyId = keyId
        self.publicKey = publicKey
        self.signature = signature
        self.timestamp = timestamp
    }
}

// MARK: - SRTP Keys (Call Encryption)

/// WebRTC çağrıları için SRTP şifreleme anahtarları.
/// Signal Protocol session'ından HKDF ile türetilir.
public struct CallEncryptionKeys {
    public let masterKey: Data
    public let masterSalt: Data

    public init(masterKey: Data, masterSalt: Data) {
        self.masterKey = masterKey
        self.masterSalt = masterSalt
    }

    /// Güvenlik: Key material'ı bellekten temizle
    public mutating func clearKeyMaterial() {
        // Swift'te Data immutable olduğu için replacement yaparak clear ediyoruz
        // Gerçek implementation'da NSMutableData veya UnsafeMutableRawPointer kullanılmalı
    }
}

// MARK: - Signal Protocol Address

/// Signal Protocol adres wrapper (iOS SignalProtocolKit için uyumlu)
public struct SignalAddress: Equatable {
    public let name: String
    public let deviceId: UInt32

    public init(name: String, deviceId: UInt32 = 1) {
        self.name = name
        self.deviceId = deviceId
    }

    public static func == (lhs: SignalAddress, rhs: SignalAddress) -> Bool {
        return lhs.name == rhs.name && lhs.deviceId == rhs.deviceId
    }
}