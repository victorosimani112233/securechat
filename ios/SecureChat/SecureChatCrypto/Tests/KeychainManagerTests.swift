import XCTest
@testable import SecureChatCrypto

/// KeychainManager unit test'leri.
/// iOS Keychain entegrasyonu ve güvenlik özelliklerini test eder.
///
/// Test kapsamı:
/// - Encryption/decryption round-trip
/// - Keychain storage operations
/// - Security features (Secure Enclave)
/// - Error handling
/// - Data clearing
final class KeychainManagerTests: XCTestCase {

    // MARK: - Properties

    private var keychainManager: KeychainManager!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        keychainManager = KeychainManager()

        // Test için temiz state ile başla
        try await keychainManager.clearAllCryptoKeys()
    }

    override func tearDown() async throws {
        // Test sonrası temizlik
        try await keychainManager.clearAllCryptoKeys()
        keychainManager = nil
        try await super.tearDown()
    }

    // MARK: - Encryption/Decryption Tests

    /// Temel encrypt-decrypt round-trip test'i.
    func testBasicEncryptDecrypt() throws {
        // Given: Test data
        let originalData = "Hello, Keychain! 🔐".data(using: .utf8)!

        // When: Data encrypted and decrypted
        let encryptedData = try keychainManager.encrypt(originalData)
        let decryptedData = try keychainManager.decrypt(encryptedData)

        // Then: Decrypted data should match original
        XCTAssertEqual(decryptedData, originalData, "Decrypted data should match original")
        XCTAssertNotEqual(encryptedData, originalData, "Encrypted data should be different from original")
    }

    /// Empty data encryption test'i.
    func testEmptyDataEncryption() throws {
        // Given: Empty data
        let emptyData = Data()

        // When: Empty data encrypted and decrypted
        let encryptedData = try keychainManager.encrypt(emptyData)
        let decryptedData = try keychainManager.decrypt(encryptedData)

        // Then: Should handle empty data correctly
        XCTAssertEqual(decryptedData, emptyData, "Empty data should be handled correctly")
        XCTAssertGreaterThan(encryptedData.count, 0, "Encrypted empty data should have some content (nonce + tag)")
    }

    /// Large data encryption test'i.
    func testLargeDataEncryption() throws {
        // Given: Large data (100KB)
        let largeData = Data(repeating: 0x42, count: 100 * 1024)

        // When: Large data encrypted and decrypted
        let encryptedData = try keychainManager.encrypt(largeData)
        let decryptedData = try keychainManager.decrypt(encryptedData)

        // Then: Should handle large data correctly
        XCTAssertEqual(decryptedData, largeData, "Large data should be handled correctly")
        XCTAssertGreaterThan(encryptedData.count, largeData.count, "Encrypted data should be larger due to nonce and tag")
    }

    /// Random data encryption test'i.
    func testRandomDataEncryption() throws {
        // Given: Random binary data
        var randomData = Data(count: 1024)
        randomData.withUnsafeMutableBytes { bytes in
            arc4random_buf(bytes.baseAddress!, 1024)
        }

        // When: Random data encrypted and decrypted
        let encryptedData = try keychainManager.encrypt(randomData)
        let decryptedData = try keychainManager.decrypt(encryptedData)

        // Then: Should handle random data correctly
        XCTAssertEqual(decryptedData, randomData, "Random data should be handled correctly")
    }

    /// Multiple encryption determinism test'i.
    func testEncryptionNonDeterministic() throws {
        // Given: Same data
        let testData = "Same data for multiple encryptions".data(using: .utf8)!

        // When: Same data encrypted multiple times
        let encrypted1 = try keychainManager.encrypt(testData)
        let encrypted2 = try keychainManager.encrypt(testData)
        let encrypted3 = try keychainManager.encrypt(testData)

        // Then: Encrypted results should be different (due to random nonce)
        XCTAssertNotEqual(encrypted1, encrypted2, "Multiple encryptions should produce different results")
        XCTAssertNotEqual(encrypted2, encrypted3, "Multiple encryptions should produce different results")
        XCTAssertNotEqual(encrypted1, encrypted3, "Multiple encryptions should produce different results")

        // But all should decrypt to same original data
        let decrypted1 = try keychainManager.decrypt(encrypted1)
        let decrypted2 = try keychainManager.decrypt(encrypted2)
        let decrypted3 = try keychainManager.decrypt(encrypted3)

        XCTAssertEqual(decrypted1, testData, "All should decrypt to original data")
        XCTAssertEqual(decrypted2, testData, "All should decrypt to original data")
        XCTAssertEqual(decrypted3, testData, "All should decrypt to original data")
    }

    // MARK: - Keychain Storage Tests

    /// Generic data storage test'i.
    func testGenericDataStorage() throws {
        // Given: Test data and tag
        let testData = "Test data for Keychain storage".data(using: .utf8)!
        let testTag = "test_data_tag"

        // When: Data stored and retrieved
        try keychainManager.storeData(testData, tag: testTag)
        let retrievedData = try keychainManager.loadData(tag: testTag)

        // Then: Retrieved data should match stored data
        XCTAssertEqual(retrievedData, testData, "Retrieved data should match stored data")
    }

    /// Data overwrite test'i.
    func testDataOverwrite() throws {
        // Given: Initial data
        let initialData = "Initial data".data(using: .utf8)!
        let updatedData = "Updated data".data(using: .utf8)!
        let testTag = "overwrite_test_tag"

        // When: Data stored, then overwritten
        try keychainManager.storeData(initialData, tag: testTag)
        try keychainManager.storeData(updatedData, tag: testTag)

        // Then: Retrieved data should be the updated data
        let retrievedData = try keychainManager.loadData(tag: testTag)
        XCTAssertEqual(retrievedData, updatedData, "Should retrieve updated data")
    }

    /// Data deletion test'i.
    func testDataDeletion() throws {
        // Given: Stored data
        let testData = "Data to be deleted".data(using: .utf8)!
        let testTag = "deletion_test_tag"

        try keychainManager.storeData(testData, tag: testTag)

        // Verify data is stored
        let retrievedData = try keychainManager.loadData(tag: testTag)
        XCTAssertEqual(retrievedData, testData, "Data should be initially stored")

        // When: Data deleted
        try keychainManager.deleteData(tag: testTag)

        // Then: Data should no longer exist
        let deletedData = try keychainManager.loadData(tag: testTag)
        XCTAssertNil(deletedData, "Data should be nil after deletion")
    }

    /// Non-existent data retrieval test'i.
    func testNonExistentDataRetrieval() throws {
        // When: Attempt to load non-existent data
        let nonExistentData = try keychainManager.loadData(tag: "non_existent_tag")

        // Then: Should return nil
        XCTAssertNil(nonExistentData, "Non-existent data should return nil")
    }

    // MARK: - Identity Key Storage Tests

    /// Identity key storage test'i.
    func testIdentityKeyStorage() async throws {
        // Given: Test identity key data
        let testKeyData = randomData(length: 64) // Mock identity key

        // When: Identity key stored and retrieved
        try await keychainManager.storeIdentityKeyPair(testKeyData)
        let retrievedKeyData = try await keychainManager.loadIdentityKeyPair()

        // Then: Retrieved key should match stored key
        XCTAssertEqual(retrievedKeyData, testKeyData, "Retrieved identity key should match stored key")
    }

    /// Identity key overwrite test'i.
    func testIdentityKeyOverwrite() async throws {
        // Given: Initial and updated key data
        let initialKeyData = randomData(length: 64)
        let updatedKeyData = randomData(length: 64)

        // When: Identity key stored, then updated
        try await keychainManager.storeIdentityKeyPair(initialKeyData)
        try await keychainManager.storeIdentityKeyPair(updatedKeyData)

        // Then: Retrieved key should be the updated key
        let retrievedKeyData = try await keychainManager.loadIdentityKeyPair()
        XCTAssertEqual(retrievedKeyData, updatedKeyData, "Should retrieve updated identity key")
    }

    // MARK: - Database Passphrase Tests

    /// Database passphrase generation test'i.
    func testDatabasePassphraseGeneration() throws {
        // When: Database passphrase generated
        let passphrase1 = try keychainManager.getDatabasePassphrase()
        let passphrase2 = try keychainManager.getDatabasePassphrase()

        // Then: Should be consistent (deterministic)
        XCTAssertEqual(passphrase1, passphrase2, "Database passphrase should be deterministic")
        XCTAssertEqual(passphrase1.count, 32, "Passphrase should be 32 bytes (256-bit)")
        XCTAssertFalse(passphrase1.allSatisfy { $0 == 0 }, "Passphrase should not be all zeros")
    }

    // MARK: - Security Tests

    /// Secure Enclave availability test'i.
    func testSecureEnclaveAvailability() async {
        // When: Check Secure Enclave availability
        let isAvailable = await keychainManager.isSecureEnclaveAvailable()

        // Then: Log the result (varies by device/simulator)
        print("Secure Enclave available: \(isAvailable)")

        // In simulator, Secure Enclave is typically not available
        // On real devices with A7+ chips, it should be available
        #if targetEnvironment(simulator)
        // Simulator'da genellikle mevcut değil
        print("Running in simulator - Secure Enclave may not be available")
        #else
        // Gerçek cihazda mevcut olması beklenir
        XCTAssertTrue(isAvailable, "Secure Enclave should be available on real devices")
        #endif
    }

    /// Data clearing test'i.
    func testClearAllCryptoKeys() async throws {
        // Given: Stored identity key and other data
        let testKeyData = randomData(length: 64)
        let testData = "Test data".data(using: .utf8)!

        try await keychainManager.storeIdentityKeyPair(testKeyData)
        try keychainManager.storeData(testData, tag: "test_tag")

        // Verify data is stored
        let retrievedKey = try await keychainManager.loadIdentityKeyPair()
        let retrievedData = try keychainManager.loadData(tag: "test_tag")
        XCTAssertEqual(retrievedKey, testKeyData, "Key should be initially stored")
        XCTAssertEqual(retrievedData, testData, "Data should be initially stored")

        // When: All crypto keys cleared
        try await keychainManager.clearAllCryptoKeys()

        // Then: Identity key should be cleared, but other data might remain
        let clearedKey = try await keychainManager.loadIdentityKeyPair()
        XCTAssertNil(clearedKey, "Identity key should be cleared")

        // Regular data should also be cleared if it's crypto-related
        let remainingData = try keychainManager.loadData(tag: "test_tag")
        XCTAssertEqual(remainingData, testData, "Non-crypto data should remain")
    }

    // MARK: - Error Handling Tests

    /// Invalid encrypted data decryption test'i.
    func testInvalidDataDecryption() {
        // Given: Invalid encrypted data
        let invalidData = Data([0x00, 0x01, 0x02, 0x03]) // Too short for valid AES-GCM

        // When: Attempt to decrypt invalid data
        XCTAssertThrowsError(try keychainManager.decrypt(invalidData)) { error in
            // Then: Should throw appropriate error
            print("Correctly threw error for invalid data: \(error)")
        }
    }

    /// Corrupted encrypted data test'i.
    func testCorruptedDataDecryption() throws {
        // Given: Valid encrypted data, then corrupted
        let originalData = "Data to be corrupted".data(using: .utf8)!
        var encryptedData = try keychainManager.encrypt(originalData)

        // Corrupt the encrypted data
        encryptedData[encryptedData.count - 1] ^= 0xFF // Flip bits in tag

        // When: Attempt to decrypt corrupted data
        XCTAssertThrowsError(try keychainManager.decrypt(encryptedData)) { error in
            // Then: Should throw decryption error
            print("Correctly threw error for corrupted data: \(error)")
        }
    }

    /// Keychain access error simulation.
    func testKeychainErrorHandling() {
        // This is difficult to test directly without mocking Keychain APIs
        // In real scenarios, we might get errors like:
        // - errSecItemNotFound
        // - errSecAuthFailed
        // - errSecUserCancel

        // For now, we just test the error enum
        let error = KeychainError.storeFailed(errSecDuplicateItem)
        XCTAssertNotNil(error.errorDescription, "Error should have description")
        XCTAssertTrue(error.errorDescription!.contains("store"), "Error should mention store failure")
    }

    // MARK: - Performance Tests

    /// Encryption performance test'i.
    func testEncryptionPerformance() throws {
        // Given: Test data
        let testData = Data(repeating: 0x42, count: 1024) // 1KB data

        // Measure encryption performance
        measure {
            for _ in 0..<100 {
                do {
                    _ = try keychainManager.encrypt(testData)
                } catch {
                    XCTFail("Encryption should not fail: \(error)")
                }
            }
        }
    }

    /// Keychain storage performance test'i.
    func testKeychainStoragePerformance() throws {
        // Given: Test data
        let testData = "Performance test data".data(using: .utf8)!

        // Measure keychain storage performance
        measure {
            for i in 0..<50 {
                do {
                    try keychainManager.storeData(testData, tag: "perf_test_\(i)")
                } catch {
                    XCTFail("Storage should not fail: \(error)")
                }
            }
        }

        // Cleanup
        for i in 0..<50 {
            try? keychainManager.deleteData(tag: "perf_test_\(i)")
        }
    }

    // MARK: - Edge Cases

    /// Very large data encryption test'i.
    func testVeryLargeDataEncryption() throws {
        // Given: Very large data (10MB)
        let veryLargeData = Data(repeating: 0x55, count: 10 * 1024 * 1024)

        // When: Very large data encrypted and decrypted
        let startTime = CFAbsoluteTimeGetCurrent()
        let encryptedData = try keychainManager.encrypt(veryLargeData)
        let decryptedData = try keychainManager.decrypt(encryptedData)
        let endTime = CFAbsoluteTimeGetCurrent()

        // Then: Should handle very large data correctly
        XCTAssertEqual(decryptedData, veryLargeData, "Very large data should be handled correctly")

        let duration = endTime - startTime
        print("10MB encryption/decryption took \(duration) seconds")

        // Should complete within reasonable time (10 seconds)
        XCTAssertLessThan(duration, 10.0, "Very large data encryption should complete within 10 seconds")
    }

    /// Unicode data test'i.
    func testUnicodeDataEncryption() throws {
        // Given: Unicode data
        let unicodeData = "Hello 世界! 🌍🔐 Güvenlik тест".data(using: .utf8)!

        // When: Unicode data encrypted and decrypted
        let encryptedData = try keychainManager.encrypt(unicodeData)
        let decryptedData = try keychainManager.decrypt(encryptedData)

        // Then: Should handle Unicode correctly
        XCTAssertEqual(decryptedData, unicodeData, "Unicode data should be handled correctly")

        // Verify round-trip string conversion
        let decryptedString = String(data: decryptedData, encoding: .utf8)
        XCTAssertEqual(decryptedString, "Hello 世界! 🌍🔐 Güvenlik тест", "Unicode string should be preserved")
    }
}

// MARK: - Test Helpers

extension KeychainManagerTests {

    /// Test için random data üretir.
    private func randomData(length: Int) -> Data {
        var data = Data(count: length)
        data.withUnsafeMutableBytes { bytes in
            arc4random_buf(bytes.baseAddress!, length)
        }
        return data
    }
}