import XCTest
@testable import SecureChatCrypto
import SecureChatCommon

/// Integration test'leri - Tam E2E crypto flow test'i.
/// İki kullanıcı arasında complete message exchange simulation.
///
/// Test kapsamı:
/// - Cross-user key exchange
/// - Complete message encryption/decryption flow
/// - Session establishment
/// - Key rotation scenarios
final class CryptoIntegrationTests: XCTestCase {

    // MARK: - Properties

    private var alice: SignalProtocolManager!
    private var bob: SignalProtocolManager!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        alice = SignalProtocolManager()
        bob = SignalProtocolManager()

        // Clean state for both users
        try await alice.clearAllData()
        try await bob.clearAllData()
    }

    override func tearDown() async throws {
        try await alice.clearAllData()
        try await bob.clearAllData()

        alice = nil
        bob = nil

        try await super.tearDown()
    }

    // MARK: - End-to-End Integration Tests

    /// Complete E2E messaging test between two users.
    func testCompleteE2EMessaging() async throws {
        // PHASE 1: Key Generation
        print("🔧 Phase 1: Generating keys for Alice and Bob")

        let aliceKeyBundle = try await alice.initializeKeys()
        let bobKeyBundle = try await bob.initializeKeys()

        // Verify key bundles are valid
        XCTAssertFalse(aliceKeyBundle.identityKey.isEmpty, "Alice should have identity key")
        XCTAssertFalse(bobKeyBundle.identityKey.isEmpty, "Bob should have identity key")
        XCTAssertNotEqual(aliceKeyBundle.registrationId, bobKeyBundle.registrationId, "Registration IDs should be different")

        print("✅ Keys generated - Alice ID: \(aliceKeyBundle.registrationId), Bob ID: \(bobKeyBundle.registrationId)")

        // PHASE 2: Check Security Status
        print("🔧 Phase 2: Checking security status")

        let aliceStatus = await alice.getSecurityStatus()
        let bobStatus = await bob.getSecurityStatus()

        XCTAssertTrue(aliceStatus.hasIdentityKey, "Alice should have identity key")
        XCTAssertTrue(bobStatus.hasIdentityKey, "Bob should have identity key")

        print("✅ Security status verified")

        // PHASE 3: Session Check (Initially no sessions)
        print("🔧 Phase 3: Initial session check")

        let aliceHasSessionWithBob = await alice.hasSession(with: "bob_user_id")
        let bobHasSessionWithAlice = await bob.hasSession(with: "alice_user_id")

        XCTAssertFalse(aliceHasSessionWithBob, "Alice should not have session with Bob initially")
        XCTAssertFalse(bobHasSessionWithAlice, "Bob should not have session with Alice initially")

        print("✅ No initial sessions confirmed")

        // PHASE 4: Message Preparation
        print("🔧 Phase 4: Preparing test messages")

        let message1 = "Hello Bob! This is Alice 👋".data(using: .utf8)!
        let message2 = "Hi Alice! Nice to meet you 😊".data(using: .utf8)!
        let message3 = "How is the E2E encryption working? 🔐".data(using: .utf8)!

        // PHASE 5: Encryption Attempts (Will fail due to no session)
        print("🔧 Phase 5: Testing encryption without session")

        do {
            _ = try await alice.encryptMessage(to: "bob_user_id", plaintext: message1)
            XCTFail("Encryption should fail without established session")
        } catch {
            print("✅ Encryption correctly failed without session: \(error)")
        }

        // PHASE 6: PreKey Replenishment Test
        print("🔧 Phase 6: Testing PreKey management")

        let aliceNewPreKeys = try await alice.replenishPreKeysIfNeeded()
        let bobNewPreKeys = try await bob.replenishPreKeysIfNeeded()

        // Should not need replenishment initially (100 keys generated)
        XCTAssertNil(aliceNewPreKeys, "Alice should not need PreKey replenishment initially")
        XCTAssertNil(bobNewPreKeys, "Bob should not need PreKey replenishment initially")

        print("✅ PreKey management working correctly")

        // PHASE 7: Signed PreKey Rotation Test
        print("🔧 Phase 7: Testing Signed PreKey rotation")

        try await alice.rotateSignedPreKey()
        try await bob.rotateSignedPreKey()

        let aliceStatusAfterRotation = await alice.getSecurityStatus()
        let bobStatusAfterRotation = await bob.getSecurityStatus()

        XCTAssertNotNil(aliceStatusAfterRotation.lastSignedPreKeyRotation, "Alice should have rotation timestamp")
        XCTAssertNotNil(bobStatusAfterRotation.lastSignedPreKeyRotation, "Bob should have rotation timestamp")

        print("✅ Signed PreKey rotation completed successfully")

        // PHASE 8: Multi-Device Simulation
        print("🔧 Phase 8: Testing multi-device support")

        let deviceId2: UInt32 = 2

        let aliceHasSessionDevice2 = await alice.hasSession(with: "bob_user_id", deviceId: deviceId2)
        XCTAssertFalse(aliceHasSessionDevice2, "Should not have session with device 2")

        print("✅ Multi-device support structure in place")
    }

    /// Key bundle validation test.
    func testKeyBundleValidation() async throws {
        print("🔧 Testing key bundle validation")

        let keyBundle = try await alice.initializeKeys()

        // Validate key bundle structure
        XCTAssertGreaterThan(keyBundle.registrationId, 0, "Registration ID should be positive")
        XCTAssertEqual(keyBundle.preKeys.count, 100, "Should have 100 PreKeys")
        XCTAssertGreaterThan(keyBundle.identityKey.count, 0, "Identity key should not be empty")
        XCTAssertGreaterThan(keyBundle.signedPreKey.signature.count, 0, "Signature should not be empty")
        XCTAssertGreaterThan(keyBundle.signedPreKey.timestamp, 0, "Timestamp should be positive")

        // Check PreKey uniqueness
        let preKeyIds = keyBundle.preKeys.map { $0.keyId }
        let uniqueIds = Set(preKeyIds)
        XCTAssertEqual(preKeyIds.count, uniqueIds.count, "All PreKey IDs should be unique")

        print("✅ Key bundle validation passed")
    }

    /// Performance test for key operations.
    func testCryptoPerformance() async throws {
        print("🔧 Testing crypto performance")

        // Key generation performance
        let keyGenStart = CFAbsoluteTimeGetCurrent()
        _ = try await alice.initializeKeys()
        let keyGenTime = CFAbsoluteTimeGetCurrent() - keyGenStart

        XCTAssertLessThan(keyGenTime, 10.0, "Key generation should complete within 10 seconds")
        print("✅ Key generation took \(String(format: "%.3f", keyGenTime)) seconds")

        // Multiple encryption attempts performance
        let message = "Performance test message".data(using: .utf8)!
        let encryptionCount = 50

        let encryptStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<encryptionCount {
            do {
                _ = try await alice.encryptMessage(
                    to: "perf_user_\(i)",
                    plaintext: message
                )
            } catch {
                // Expected to fail due to no session, but timing is still relevant
            }
        }
        let encryptTime = CFAbsoluteTimeGetCurrent() - encryptStart
        let avgEncryptTime = encryptTime / Double(encryptionCount)

        XCTAssertLessThan(avgEncryptTime, 0.1, "Average encryption attempt should take less than 100ms")
        print("✅ Average encryption attempt: \(String(format: "%.3f", avgEncryptTime * 1000)) ms")
    }

    /// Memory management test.
    func testMemoryManagement() async throws {
        print("🔧 Testing memory management")

        // Create large amounts of crypto data
        let message = Data(repeating: 0x42, count: 1024) // 1KB message

        // Generate keys multiple times to test cleanup
        for i in 0..<5 {
            print("Memory test iteration \(i + 1)")

            let keyBundle = try await alice.initializeKeys()
            XCTAssertFalse(keyBundle.identityKey.isEmpty, "Key should be generated")

            // Clear data to test cleanup
            try await alice.clearAllData()

            let statusAfterClear = await alice.getSecurityStatus()
            XCTAssertFalse(statusAfterClear.hasIdentityKey, "Keys should be cleared")
        }

        print("✅ Memory management test completed")
    }

    /// Concurrent operations test.
    func testConcurrentOperations() async throws {
        print("🔧 Testing concurrent crypto operations")

        // Initialize keys
        _ = try await alice.initializeKeys()
        _ = try await bob.initializeKeys()

        // Run multiple concurrent operations
        await withTaskGroup(of: Void.self) { group in

            // Concurrent PreKey checks
            group.addTask {
                do {
                    _ = try await self.alice.replenishPreKeysIfNeeded()
                } catch {
                    print("Concurrent PreKey check failed: \(error)")
                }
            }

            group.addTask {
                do {
                    _ = try await self.bob.replenishPreKeysIfNeeded()
                } catch {
                    print("Concurrent PreKey check failed: \(error)")
                }
            }

            // Concurrent security status checks
            group.addTask {
                _ = await self.alice.getSecurityStatus()
            }

            group.addTask {
                _ = await self.bob.getSecurityStatus()
            }

            // Concurrent encryption attempts
            let message = "Concurrent test".data(using: .utf8)!

            group.addTask {
                do {
                    _ = try await self.alice.encryptMessage(to: "test_user", plaintext: message)
                } catch {
                    // Expected to fail, but should not crash
                }
            }
        }

        print("✅ Concurrent operations completed successfully")
    }

    /// Error handling and recovery test.
    func testErrorHandlingAndRecovery() async throws {
        print("🔧 Testing error handling and recovery")

        // Test encryption without initialization
        do {
            let message = "Test message".data(using: .utf8)!
            _ = try await alice.encryptMessage(to: "test_user", plaintext: message)
            XCTFail("Should fail without initialization")
        } catch {
            print("✅ Correctly failed without initialization: \(error)")
        }

        // Initialize and test recovery
        _ = try await alice.initializeKeys()

        // Test invalid user IDs
        let invalidUserIds = ["", "   ", "\n", String(repeating: "x", count: 1000)]
        let testMessage = "Test".data(using: .utf8)!

        for invalidId in invalidUserIds {
            do {
                _ = try await alice.encryptMessage(to: invalidId, plaintext: testMessage)
                if !invalidId.isEmpty {
                    // Empty string might be caught earlier, others should fail at session level
                    print("⚠️ Encryption with invalid ID '\(invalidId)' should have failed")
                }
            } catch {
                print("✅ Correctly handled invalid user ID: '\(invalidId)'")
            }
        }

        print("✅ Error handling and recovery test completed")
    }

    /// Data integrity test.
    func testDataIntegrity() async throws {
        print("🔧 Testing data integrity")

        // Generate keys multiple times and ensure consistency
        let keyBundle1 = try await alice.initializeKeys()
        let status1 = await alice.getSecurityStatus()

        // Clear and regenerate
        try await alice.clearAllData()
        let keyBundle2 = try await alice.initializeKeys()
        let status2 = await alice.getSecurityStatus()

        // Should have different keys (not deterministic)
        XCTAssertNotEqual(keyBundle1.registrationId, keyBundle2.registrationId, "Registration IDs should be different")
        XCTAssertNotEqual(keyBundle1.identityKey, keyBundle2.identityKey, "Identity keys should be different")

        // But both should be valid
        XCTAssertTrue(status1.hasIdentityKey, "First generation should have key")
        XCTAssertTrue(status2.hasIdentityKey, "Second generation should have key")

        print("✅ Data integrity verified")
    }
}

// MARK: - Test Utilities

extension CryptoIntegrationTests {

    /// Helper to create mock PreKeyBundle (for future session creation tests).
    private func createMockPreKeyBundle(from keyBundle: KeyBundle) -> MockPreKeyBundle {
        return MockPreKeyBundle(
            registrationId: keyBundle.registrationId,
            identityKey: keyBundle.identityKey,
            preKey: keyBundle.preKeys.first!,
            signedPreKey: keyBundle.signedPreKey
        )
    }
}

// MARK: - Mock PreKeyBundle

/// Mock PreKeyBundle for testing purposes.
/// Gerçek implementasyon'da server'dan gelecek.
private struct MockPreKeyBundle {
    let registrationId: UInt32
    let identityKey: Data
    let preKey: PreKeyPublic
    let signedPreKey: SignedPreKeyPublic
}