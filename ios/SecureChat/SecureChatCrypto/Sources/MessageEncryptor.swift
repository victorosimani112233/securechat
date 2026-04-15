import Foundation
import SignalProtocolKit
import SecureChatCommon

/// Mesaj şifreleme ve çözme işlemleri.
/// Signal Protocol'un Double Ratchet Algorithm'ini kullanarak
/// her mesaj için benzersiz anahtar türetir (forward secrecy).
///
/// GÜVENLIK: Plaintext mesaj içeriği ASLA loga yazılmaz.
/// GÜVENLIK: Çözülmüş plaintext kullanım sonrası bellekten sıfırlanmalıdır.
public class MessageEncryptor {

    // MARK: - Properties

    private let protocolStore: SecureChatProtocolStore

    // MARK: - Initialization

    public init(protocolStore: SecureChatProtocolStore) {
        self.protocolStore = protocolStore
    }

    // MARK: - Message Encryption

    /// Mesajı Signal Protocol ile şifreler.
    /// Double Ratchet Algorithm ile her mesaj için benzersiz anahtar kullanır.
    ///
    /// - Parameters:
    ///   - recipientId: Alıcı kullanıcı ID'si
    ///   - plaintext: Şifrelenecek düz metin (Data)
    ///   - deviceId: Alıcı cihaz ID'si (varsayılan 1)
    /// - Returns: Şifrelenmiş mesaj zarfı
    /// - Throws: Encryption hatası veya session bulunamama
    public func encrypt(
        recipientId: String,
        plaintext: Data,
        deviceId: UInt32 = 1
    ) async throws -> EncryptedEnvelope {
        // GÜVENLIK: Plaintext ASLA loga yazılmaz
        // print("Encrypting message...") // Plaintext loglanmaz!

        let address = SignalAddress(name: recipientId, deviceId: deviceId)
        let spkAddress = SPKAddress(name: address.name, deviceId: Int32(address.deviceId))

        // SessionCipher oluştur
        let cipher = try SPKSessionCipher(
            for: spkAddress,
            identityKeyStore: protocolStore,
            preKeyStore: protocolStore,
            signedPreKeyStore: protocolStore,
            sessionStore: protocolStore
        )

        // Signal Protocol encryption (Double Ratchet)
        let ciphertextMessage: SPKCipherTextMessage
        do {
            ciphertextMessage = try cipher.encrypt(plaintext)
        } catch {
            throw CryptoError.encryptionFailed("Failed to encrypt message for \(recipientId): \(error)")
        }

        // Plaintext'i bellekten temizle (mutable copy kullanarak)
        var mutablePlaintext = plaintext
        mutablePlaintext.resetBytes(in: 0..<plaintext.count)

        // Message type'ını belirle
        let envelopeType: EnvelopeType
        if ciphertextMessage is SPKPreKeySignalMessage {
            envelopeType = .prekey
        } else {
            envelopeType = .signal
        }

        let envelope = EncryptedEnvelope(
            type: envelopeType,
            content: ciphertextMessage.data,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000), // milliseconds
            senderRegistrationId: await protocolStore.getLocalRegistrationId()
        )

        return envelope
    }

    /// Şifrelenmiş mesajı çözümler.
    /// Double Ratchet Algorithm ile forward secrecy ve out-of-order message handling sağlar.
    ///
    /// - Parameters:
    ///   - senderId: Gönderen kullanıcı ID'si
    ///   - envelope: Şifrelenmiş mesaj zarfı
    ///   - deviceId: Gönderen cihaz ID'si (varsayılan 1)
    /// - Returns: Çözülmüş plaintext (Data)
    /// - Throws: Decryption hatası veya invalid message
    public func decrypt(
        senderId: String,
        envelope: EncryptedEnvelope,
        deviceId: UInt32 = 1
    ) async throws -> Data {
        // GÜVENLIK: Plaintext ASLA loga yazılmaz
        // print("Decrypting message...") // Result loglanmaz!

        let address = SignalAddress(name: senderId, deviceId: deviceId)
        let spkAddress = SPKAddress(name: address.name, deviceId: Int32(address.deviceId))

        // SessionCipher oluştur
        let cipher = try SPKSessionCipher(
            for: spkAddress,
            identityKeyStore: protocolStore,
            preKeyStore: protocolStore,
            signedPreKeyStore: protocolStore,
            sessionStore: protocolStore
        )

        let decryptedData: Data
        do {
            switch envelope.type {
            case .prekey:
                // İlk mesaj - X3DH key agreement ile session kurulacak
                let message = try SPKPreKeySignalMessage(data: envelope.content)
                decryptedData = try cipher.decrypt(message)

            case .signal:
                // Normal mesaj - mevcut session ile Double Ratchet
                let message = try SPKSignalMessage(data: envelope.content)
                decryptedData = try cipher.decrypt(message)
            }
        } catch let error as SPKError {
            throw CryptoError.decryptionFailed("Failed to decrypt message from \(senderId): \(error.localizedDescription)")
        } catch {
            throw CryptoError.decryptionFailed("Failed to decrypt message from \(senderId): \(error)")
        }

        return decryptedData
    }

    // MARK: - Batch Operations

    /// Birden fazla mesajı aynı anda şifreler.
    ///
    /// - Parameters:
    ///   - messages: Şifrelenecek mesajlar (recipientId -> plaintext)
    /// - Returns: Şifreli mesajlar (recipientId -> EncryptedEnvelope)
    /// - Throws: Encryption hatası
    public func encryptBatch(
        messages: [String: Data]
    ) async throws -> [String: EncryptedEnvelope] {
        var encryptedMessages: [String: EncryptedEnvelope] = [:]

        for (recipientId, plaintext) in messages {
            do {
                let envelope = try await encrypt(recipientId: recipientId, plaintext: plaintext)
                encryptedMessages[recipientId] = envelope
            } catch {
                print("❌ Failed to encrypt message for \(recipientId): \(error)")
                // Batch işlemde hata olan mesajları skip et, diğerlerini devam ettir
            }
        }

        return encryptedMessages
    }

    /// Birden fazla mesajı aynı anda çözümler.
    ///
    /// - Parameters:
    ///   - messages: Çözülecek mesajlar (senderId -> EncryptedEnvelope)
    /// - Returns: Çözülmüş mesajlar (senderId -> Data)
    /// - Throws: Decryption hatası
    public func decryptBatch(
        messages: [String: EncryptedEnvelope]
    ) async throws -> [String: Data] {
        var decryptedMessages: [String: Data] = [:]

        for (senderId, envelope) in messages {
            do {
                let plaintext = try await decrypt(senderId: senderId, envelope: envelope)
                decryptedMessages[senderId] = plaintext
            } catch {
                print("❌ Failed to decrypt message from \(senderId): \(error)")
                // Batch işlemde hata olan mesajları skip et, diğerlerini devam ettir
            }
        }

        return decryptedMessages
    }

    // MARK: - Message Validation

    /// Şifrelenmiş mesajın geçerli olup olmadığını kontrol eder.
    ///
    /// - Parameter envelope: Kontrol edilecek mesaj zarfı
    /// - Returns: true eğer geçerliyse
    public func validateEncryptedMessage(_ envelope: EncryptedEnvelope) -> Bool {
        // Basit validation kontrolleri
        guard !envelope.content.isEmpty else {
            print("❌ Empty message content")
            return false
        }

        guard envelope.timestamp > 0 else {
            print("❌ Invalid timestamp")
            return false
        }

        // Message type'a göre minimum content size kontrolü
        let minContentSize: Int
        switch envelope.type {
        case .prekey:
            minContentSize = 100 // PreKeySignalMessage minimum size
        case .signal:
            minContentSize = 50  // SignalMessage minimum size
        }

        guard envelope.content.count >= minContentSize else {
            print("❌ Message content too small for type \(envelope.type)")
            return false
        }

        return true
    }

    /// Mesajın çok eskiyip olmadığını kontrol eder.
    ///
    /// - Parameters:
    ///   - envelope: Kontrol edilecek mesaj zarfı
    ///   - maxAge: Maksimum mesaj yaşı (saniye)
    /// - Returns: true eğer mesaj çok eskiyse
    public func isMessageTooOld(_ envelope: EncryptedEnvelope, maxAge: TimeInterval = 86400) -> Bool {
        let messageTime = TimeInterval(envelope.timestamp) / 1000.0 // milliseconds to seconds
        let currentTime = Date().timeIntervalSince1970
        let age = currentTime - messageTime

        return age > maxAge
    }

    // MARK: - Statistics

    /// Encryption/decryption istatistiklerini döndürür.
    ///
    /// - Returns: İstatistik bilgileri
    public func getEncryptionStats() -> EncryptionStats {
        // Basit implementasyon - gerçek uygulamada counter'lar tutulmalı
        return EncryptionStats(
            totalEncrypted: 0,
            totalDecrypted: 0,
            encryptionErrors: 0,
            decryptionErrors: 0
        )
    }
}

// MARK: - Crypto Errors

public enum CryptoError: LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case sessionNotFound(String)
    case invalidMessage(String)

    public var errorDescription: String? {
        switch self {
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .sessionNotFound(let userId):
            return "Session not found for user: \(userId)"
        case .invalidMessage(let details):
            return "Invalid message: \(details)"
        }
    }
}

// MARK: - Encryption Stats

public struct EncryptionStats {
    public let totalEncrypted: Int
    public let totalDecrypted: Int
    public let encryptionErrors: Int
    public let decryptionErrors: Int

    public init(totalEncrypted: Int, totalDecrypted: Int, encryptionErrors: Int, decryptionErrors: Int) {
        self.totalEncrypted = totalEncrypted
        self.totalDecrypted = totalDecrypted
        self.encryptionErrors = encryptionErrors
        self.decryptionErrors = decryptionErrors
    }

    public var successRate: Double {
        let totalOperations = totalEncrypted + totalDecrypted
        let totalErrors = encryptionErrors + decryptionErrors
        guard totalOperations > 0 else { return 0.0 }
        return Double(totalOperations - totalErrors) / Double(totalOperations)
    }
}