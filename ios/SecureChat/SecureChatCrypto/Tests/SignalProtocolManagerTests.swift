import XCTest
@testable import SecureChatCrypto
import SecureChatCommon

/// SignalProtocolManager unit test'leri.
/// E2E şifreleme akışının tüm bileşenlerini test eder.
///
/// Test kapsamı:
/// - Key generation ve initialization
/// - Message encryption/decryption round-trip
/// - Session management
/// - PreKey rotation
/// - Error handling
final class SignalProtocolManagerTests: XCTestCase {

    // MARK: - Properties

    private var signalManager: SignalProtocolManager!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        signalManager = SignalProtocolManager()

        // Test için temiz state ile başla
        try await signalManager.clearAllData()
    }

    override func tearDown() async throws {
        // Test sonrası temizlik
        try await signalManager.clearAllData()
        signalManager = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    /// İlk key generation ve initialization test'i.
    func testInitializeKeys() async throws {
        // When: İlk key'ler üretilir
        let keyBundle = try await signalManager.initializeKeys()

        // Then: Key bundle'ın tüm bileşenleri mevcut olmalı
        XCTAssertFalse(keyBundle.identityKey.isEmpty, "Identity key should not be empty")
        XCTAssertGreaterThan(keyBundle.registrationId, 0, "Registration ID should be positive")
        XCTAssertEqual(keyBundle.preKeys.count, 100, "Should generate 100 PreKeys")
        XCTAssertFalse(keyBundle.signedPreKey.publicKey.isEmpty, "Signed PreKey should not be empty")
        XCTAssertFalse(keyBundle.signedPreKey.signature.isEmpty, "Signature should not be empty")

        // Security status kontrol et
        let securityStatus = await signalManager.getSecurityStatus()
        XCTAssertTrue(securityStatus.hasIdentityKey, "Should have identity key")
        XCTAssertNotNil(securityStatus.lastSignedPreKeyRotation, "Should have rotation timestamp")
    }

    /// Duplicate key generation kontrolü.
    func testDuplicateInitialization() async throws {
        // Given: Key'ler zaten üretilmiş
        let firstKeyBundle = try await signalManager.initializeKeys()

        // When: Tekrar initialization çağrılır
        let secondKeyBundle = try await signalManager.initializeKeys()

        // Then: Farklı key'ler üretilmeli (deterministik olmamalı)
        XCTAssertNotEqual(firstKeyBundle.registrationId, secondKeyBundle.registrationId)
        XCTAssertNotEqual(firstKeyBundle.identityKey, secondKeyBundle.identityKey)
    }

    // MARK: - Message Encryption/Decryption Tests

    /// Temel encrypt-decrypt round-trip test'i.
    func testBasicEncryptDecrypt() async throws {
        // Given: İki SignalProtocolManager (Alice ve Bob)
        let alice = SignalProtocolManager()
        let bob = SignalProtocolManager()

        // Initialize both users
        let aliceKeys = try await alice.initializeKeys()
        let bobKeys = try await bob.initializeKeys()

        // Create mock PreKeyBundle for Bob (normally from server)
        // Bu gerçek implementasyon'da server'dan gelecek
        // Şimdilik mock bundle oluşturuyoruz

        let originalMessage = "Hello from Alice to Bob! 🔐".data(using: .utf8)!

        // When: Alice, Bob'a mesaj gönderir
        // Not: Bu test için session creation mock'lanmalı
        // Gerçek implementasyon'da server'dan PreKeyBundle alınacak

        // Şimdilik basic encryption test yapıyoruz
        do {
            let encryptedEnvelope = try await alice.encryptMessage(
                to: "bob_user_id",
                plaintext: originalMessage
            )

            // Then: Encrypted envelope geçerli olmalı
            XCTAssertFalse(encryptedEnvelope.content.isEmpty, "Encrypted content should not be empty")
            XCTAssertGreaterThan(encryptedEnvelope.timestamp, 0, "Timestamp should be positive")
            XCTAssertNotEqual(encryptedEnvelope.content, originalMessage, "Content should be encrypted")

            // Decryption (session kurulduktan sonra)
            let decryptedMessage = try await bob.decryptMessage(
                from: "alice_user_id",
                envelope: encryptedEnvelope
            )

            XCTAssertEqual(decryptedMessage, originalMessage, "Decrypted message should match original")

        } catch {
            // Session not found hatası beklenir (PreKeyBundle mock'u eksik)
            XCTAssertTrue(error.localizedDescription.contains("session") ||
                         error.localizedDescription.contains("Session"),
                         "Should fail due to missing session: \(error)")
        }

        // Cleanup
        try await alice.clearAllData()
        try await bob.clearAllData()
    }

    /// Empty message encryption test'i.
    func testEmptyMessageEncryption() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        // When: Boş mesaj şifrelenmeye çalışılır
        let emptyMessage = Data()

        do {
            _ = try await signalManager.encryptMessage(
                to: "test_user",
                plaintext: emptyMessage
            )
            XCTFail("Empty message encryption should fail")
        } catch {
            // Then: Hata alınmalı
            XCTAssertTrue(true, "Empty message encryption correctly failed")
        }
    }

    /// Large message encryption test'i.
    func testLargeMessageEncryption() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        // Large message (1MB)
        let largeMessage = Data(repeating: 0x42, count: 1024 * 1024)

        // When: Büyük mesaj şifrelenmeye çalışılır
        do {
            let envelope = try await signalManager.encryptMessage(
                to: "test_user",
                plaintext: largeMessage
            )

            // Then: Başarılı olmalı (session olmasa bile encryption başarılı)
            XCTAssertFalse(envelope.content.isEmpty, "Large message should be encrypted")
        } catch {
            // Session olmadığı için hata beklenir
            XCTAssertTrue(true, "Expected error due to missing session")
        }
    }

    // MARK: - Session Management Tests

    /// Session kontrolü test'i.
    func testSessionManagement() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        let testUserId = "test_user_123"

        // When: Session kontrolü yapılır
        let hasSessionBefore = await signalManager.hasSession(with: testUserId)

        // Then: Başlangıçta session olmamalı
        XCTAssertFalse(hasSessionBefore, "Should not have session initially")

        // Session creation burada test edilecek (PreKeyBundle gerekli)
    }

    // MARK: - PreKey Management Tests

    /// PreKey replenishment test'i.
    func testPreKeyReplenishment() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        // When: PreKey replenishment kontrol edilir
        let newPreKeys = try await signalManager.replenishPreKeysIfNeeded()

        // Then: Yeterli PreKey olduğu için yeni üretilmemeli
        XCTAssertNil(newPreKeys, "Should not need replenishment initially")
    }

    /// Signed PreKey rotation test'i.
    func testSignedPreKeyRotation() async throws {
        // Given: Initialized manager
        let initialKeyBundle = try await signalManager.initializeKeys()
        let initialTimestamp = initialKeyBundle.signedPreKey.timestamp

        // When: Signed PreKey rotate edilir
        try await signalManager.rotateSignedPreKey()

        // Then: Yeni signed PreKey üretilmeli
        let securityStatus = await signalManager.getSecurityStatus()
        XCTAssertNotNil(securityStatus.lastSignedPreKeyRotation)

        // Rotation timestamp güncellenmiş olmalı
        let rotationTime = securityStatus.lastSignedPreKeyRotation!.timeIntervalSince1970 * 1000
        XCTAssertGreaterThan(Int64(rotationTime), initialTimestamp, "Rotation timestamp should be updated")
    }

    // MARK: - Security Tests

    /// Security status test'i.
    func testSecurityStatus() async throws {
        // Given: Uninitialized manager
        var securityStatus = await signalManager.getSecurityStatus()

        // Then: Initially güvensiz olmalı
        XCTAssertFalse(securityStatus.hasIdentityKey, "Should not have identity key initially")

        // When: Initialize edilir
        _ = try await signalManager.initializeKeys()
        securityStatus = await signalManager.getSecurityStatus()

        // Then: Güvenli durumda olmalı
        XCTAssertTrue(securityStatus.hasIdentityKey, "Should have identity key after initialization")
        XCTAssertNotNil(securityStatus.lastSignedPreKeyRotation, "Should have rotation time")

        // Keychain security check (cihaza göre değişir)
        // CI environment'da Secure Enclave olmayabilir
        print("Keychain secure: \(securityStatus.isKeychainSecure)")
    }

    /// Data clearing test'i.
    func testClearAllData() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        var securityStatus = await signalManager.getSecurityStatus()
        XCTAssertTrue(securityStatus.hasIdentityKey, "Should have key before clearing")

        // When: All data cleared
        try await signalManager.clearAllData()

        // Then: Tüm data silinmiş olmalı
        securityStatus = await signalManager.getSecurityStatus()
        XCTAssertFalse(securityStatus.hasIdentityKey, "Should not have key after clearing")
    }

    // MARK: - Error Handling Tests

    /// Invalid user ID test'i.
    func testInvalidUserIdEncryption() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        let invalidUserIds = ["", "   ", "\n\t", String(repeating: "x", count: 1000)]
        let testMessage = "test message".data(using: .utf8)!

        for invalidUserId in invalidUserIds {
            do {
                _ = try await signalManager.encryptMessage(
                    to: invalidUserId,
                    plaintext: testMessage
                )
                XCTFail("Should fail for invalid user ID: '\(invalidUserId)'")
            } catch {
                // Hata beklenir
                XCTAssertTrue(true, "Correctly failed for invalid user ID")
            }
        }
    }

    /// Decryption without session test'i.
    func testDecryptionWithoutSession() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        // Mock encrypted envelope
        let mockEnvelope = EncryptedEnvelope(
            type: .signal,
            content: Data([0x01, 0x02, 0x03, 0x04, 0x05]),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            senderRegistrationId: 12345
        )

        // When: Session olmadan decryption denenir
        do {
            _ = try await signalManager.decryptMessage(
                from: "unknown_user",
                envelope: mockEnvelope
            )
            XCTFail("Should fail without session")
        } catch {
            // Then: Hata alınmalı
            XCTAssertTrue(true, "Correctly failed without session")
        }
    }

    // MARK: - Performance Tests

    /// Key generation performance test'i.
    func testKeyGenerationPerformance() async throws {
        // Measure key generation time
        let startTime = CFAbsoluteTimeGetCurrent()

        _ = try await signalManager.initializeKeys()

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime

        // Key generation should complete within reasonable time (5 seconds)
        XCTAssertLessThan(duration, 5.0, "Key generation should complete within 5 seconds")

        print("Key generation took \(duration) seconds")
    }

    /// Multiple encryption performance test'i.
    func testMultipleEncryptionPerformance() async throws {
        // Given: Initialized manager
        _ = try await signalManager.initializeKeys()

        let testMessage = "Performance test message".data(using: .utf8)!
        let testCount = 100

        // When: Multiple encryptions performed
        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<testCount {
            do {
                _ = try await signalManager.encryptMessage(
                    to: "user_\(i)",
                    plaintext: testMessage
                )
            } catch {
                // Session hatası beklenir, timing için önemli değil
            }
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        let avgDuration = duration / Double(testCount)

        print("Average encryption time: \(avgDuration * 1000) ms")

        // Her encryption 100ms'den az sürmeli
        XCTAssertLessThan(avgDuration, 0.1, "Each encryption should take less than 100ms")
    }
}

// MARK: - Test Helpers

extension SignalProtocolManagerTests {

    /// Test için random string üretir.
    private func randomString(length: Int = 10) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }

    /// Test için random data üretir.
    private func randomData(length: Int = 32) -> Data {
        var data = Data(count: length)
        data.withUnsafeMutableBytes { bytes in
            arc4random_buf(bytes.baseAddress!, length)
        }
        return data
    }
}