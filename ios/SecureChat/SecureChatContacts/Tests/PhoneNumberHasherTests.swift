import XCTest
@testable import SecureChatContacts

final class PhoneNumberHasherTests: XCTestCase {

    var hasher: PhoneNumberHasher!

    override func setUp() {
        super.setUp()
        hasher = PhoneNumberHasher()
    }

    override func tearDown() {
        hasher = nil
        super.tearDown()
    }

    // MARK: - Basic Hashing Tests

    func testHashPhoneNumber_ValidNumber() {
        let phoneNumber = "+905551234567"

        let hash = hasher.hashPhoneNumber(phoneNumber)

        XCTAssertNotNil(hash)
        XCTAssertEqual(hash?.count, 64) // SHA-256 produces 64-character hex string
        XCTAssertTrue(hasher.isValidHash(hash!))
    }

    func testHashPhoneNumber_EmptyString() {
        let phoneNumber = ""

        let hash = hasher.hashPhoneNumber(phoneNumber)

        XCTAssertNil(hash)
    }

    func testHashPhoneNumber_ConsistentHashing() {
        let phoneNumber = "+905551234567"

        let hash1 = hasher.hashPhoneNumber(phoneNumber)
        let hash2 = hasher.hashPhoneNumber(phoneNumber)

        XCTAssertNotNil(hash1)
        XCTAssertNotNil(hash2)
        XCTAssertEqual(hash1, hash2, "Same phone number should always produce the same hash")
    }

    func testHashPhoneNumber_DifferentNumbers() {
        let phoneNumber1 = "+905551234567"
        let phoneNumber2 = "+905551234568"

        let hash1 = hasher.hashPhoneNumber(phoneNumber1)
        let hash2 = hasher.hashPhoneNumber(phoneNumber2)

        XCTAssertNotNil(hash1)
        XCTAssertNotNil(hash2)
        XCTAssertNotEqual(hash1, hash2, "Different phone numbers should produce different hashes")
    }

    // MARK: - Batch Hashing Tests

    func testHashPhoneNumbers_MultipleCalls() {
        let phoneNumbers = [
            "+905551234567",
            "+905551234568",
            "+905551234569"
        ]

        let hashMap = hasher.hashPhoneNumbers(phoneNumbers)

        XCTAssertEqual(hashMap.count, 3)
        for (phoneNumber, hash) in hashMap {
            XCTAssertTrue(phoneNumbers.contains(phoneNumber))
            XCTAssertEqual(hash.count, 64)
            XCTAssertTrue(hasher.isValidHash(hash))
        }
    }

    func testHashPhoneNumbers_WithEmptyStrings() {
        let phoneNumbers = [
            "+905551234567",
            "",
            "+905551234568",
            ""
        ]

        let hashMap = hasher.hashPhoneNumbers(phoneNumbers)

        XCTAssertEqual(hashMap.count, 2) // Empty strings should be filtered out
        XCTAssertNotNil(hashMap["+905551234567"])
        XCTAssertNotNil(hashMap["+905551234568"])
    }

    func testCreateHashes_OnlyValidNumbers() {
        let phoneNumbers = [
            "+905551234567",
            "",
            "+905551234568"
        ]

        let hashes = hasher.createHashes(from: phoneNumbers)

        XCTAssertEqual(hashes.count, 2) // Empty string should be filtered out
        for hash in hashes {
            XCTAssertEqual(hash.count, 64)
            XCTAssertTrue(hasher.isValidHash(hash))
        }
    }

    // MARK: - Hash Validation Tests

    func testIsValidHash_ValidHash() {
        let phoneNumber = "+905551234567"
        let hash = hasher.hashPhoneNumber(phoneNumber)!

        let isValid = hasher.isValidHash(hash)

        XCTAssertTrue(isValid)
    }

    func testIsValidHash_InvalidLength() {
        let invalidHash = "abc123"

        let isValid = hasher.isValidHash(invalidHash)

        XCTAssertFalse(isValid)
    }

    func testIsValidHash_InvalidCharacters() {
        let invalidHash = "z".repeated(64) // 'z' is not a valid hex character

        let isValid = hasher.isValidHash(invalidHash)

        XCTAssertFalse(isValid)
    }

    func testIsValidHash_ValidHexCharacters() {
        let validHash = "1234567890abcdef".repeated(4) // 64 characters, all valid hex

        let isValid = hasher.isValidHash(validHash)

        XCTAssertTrue(isValid)
    }

    func testIsValidHash_MixedCaseHex() {
        let mixedCaseHash = "ABCDEF1234567890abcdef1234567890ABCDEF1234567890abcdef1234567890"

        let isValid = hasher.isValidHash(mixedCaseHash)

        XCTAssertTrue(isValid)
    }

    // MARK: - Hash Mapping Tests

    func testCreateHashMapping() {
        let contacts = [
            DeviceContact(id: "1", displayName: "John Doe", phoneNumber: "+905551234567"),
            DeviceContact(id: "2", displayName: "Jane Smith", phoneNumber: "+905551234568"),
            DeviceContact(id: "3", displayName: "Bob Wilson", phoneNumber: "+905551234569")
        ]

        let mapping = hasher.createHashMapping(from: contacts)

        XCTAssertEqual(mapping.count, 3)

        for (hash, contact) in mapping {
            XCTAssertEqual(hash.count, 64)
            XCTAssertTrue(hasher.isValidHash(hash))
            XCTAssertTrue(contacts.contains(contact))

            // Verify that the hash matches the contact's phone number
            let expectedHash = hasher.hashPhoneNumber(contact.phoneNumber)
            XCTAssertEqual(hash, expectedHash)
        }
    }

    func testCreateHashMapping_EmptyArray() {
        let contacts: [DeviceContact] = []

        let mapping = hasher.createHashMapping(from: contacts)

        XCTAssertTrue(mapping.isEmpty)
    }

    // MARK: - Security and Collision Tests

    func testHashCollision_Detection() {
        // This is extremely unlikely with SHA-256, but we test the detection mechanism
        let duplicateHashes = ["abc", "def", "abc", "ghi"]

        let hasCollisions = hasher.hasCollisions(in: duplicateHashes)

        XCTAssertTrue(hasCollisions)
    }

    func testHashCollision_NoCollisions() {
        let uniqueHashes = ["abc", "def", "ghi"]

        let hasCollisions = hasher.hasCollisions(in: uniqueHashes)

        XCTAssertFalse(hasCollisions)
    }

    func testAnalyzeHashDistribution() {
        let phoneNumbers = [
            "+905551234567",
            "+905551234568",
            "+905551234569",
            "+905551234567" // Duplicate
        ]

        let hashes = hasher.createHashes(from: phoneNumbers)
        let analysis = hasher.analyzeHashDistribution(hashes)

        XCTAssertEqual(analysis.totalHashes, 4)
        XCTAssertEqual(analysis.uniqueHashes, 3) // One duplicate
        XCTAssertEqual(analysis.collisions, 1)
        XCTAssertEqual(analysis.collisionRate, 0.25, accuracy: 0.01)
        XCTAssertEqual(analysis.uniquenessRate, 0.75, accuracy: 0.01)
    }

    // MARK: - Integration with Normalizer Tests

    func testHashNormalizedPhoneNumber() {
        let rawPhoneNumber = "0555 123 45 67"

        let hash = hasher.hashNormalizedPhoneNumber(rawPhoneNumber)

        XCTAssertNotNil(hash)
        XCTAssertEqual(hash?.count, 64)

        // Should be same as hashing the normalized number directly
        let normalizer = PhoneNumberNormalizer()
        let normalizedNumber = normalizer.normalizeToE164(rawPhoneNumber)!
        let expectedHash = hasher.hashPhoneNumber(normalizedNumber)

        XCTAssertEqual(hash, expectedHash)
    }

    func testHashNormalizedPhoneNumber_InvalidNumber() {
        let rawPhoneNumber = "invalid"

        let hash = hasher.hashNormalizedPhoneNumber(rawPhoneNumber)

        XCTAssertNil(hash)
    }

    func testHashNormalizedPhoneNumbers_Batch() {
        let rawPhoneNumbers = [
            "0555 123 45 67",
            "+90 555 123 45 68",
            "invalid",
            "555 123 45 69"
        ]

        let mapping = hasher.hashNormalizedPhoneNumbers(rawPhoneNumbers)

        XCTAssertEqual(mapping.count, 3) // 1 invalid should be filtered out
        XCTAssertNotNil(mapping["0555 123 45 67"])
        XCTAssertNotNil(mapping["+90 555 123 45 68"])
        XCTAssertNotNil(mapping["555 123 45 69"])
        XCTAssertNil(mapping["invalid"])

        // All hashes should be valid
        for (_, hash) in mapping {
            XCTAssertEqual(hash.count, 64)
            XCTAssertTrue(hasher.isValidHash(hash))
        }
    }

    // MARK: - Performance Tests

    func testPerformanceHashing() {
        let phoneNumbers = Array(repeating: "+905551234567", count: 1000)

        measure {
            _ = hasher.createHashes(from: phoneNumbers)
        }
    }

    func testPerformanceHashMapping() {
        let contacts = (1...1000).map { i in
            DeviceContact(id: "\(i)", displayName: "Contact \(i)", phoneNumber: "+90555123\(String(format: "%04d", i))")
        }

        measure {
            _ = hasher.createHashMapping(from: contacts)
        }
    }

    // MARK: - Privacy Tests

    func testHashingHidesPhoneNumber() {
        let phoneNumber = "+905551234567"
        let hash = hasher.hashPhoneNumber(phoneNumber)!

        // Hash should not contain the original phone number
        XCTAssertFalse(hash.contains("905551234567"))
        XCTAssertFalse(hash.contains("555"))
        XCTAssertFalse(hash.contains("1234567"))

        // Hash should be different from phone number
        XCTAssertNotEqual(hash, phoneNumber)
        XCTAssertNotEqual(hash, phoneNumber.replacingOccurrences(of: "+", with: ""))
    }

    func testHashUniqueness() {
        // Generate hashes for similar phone numbers
        let baseNumber = "+9055512345"
        let phoneNumbers = (10...99).map { "\(baseNumber)\($0)" }

        let hashes = hasher.createHashes(from: phoneNumbers)
        let uniqueHashes = Set(hashes)

        XCTAssertEqual(hashes.count, uniqueHashes.count, "All hashes should be unique")
    }
}

// MARK: - String Extension for Tests

private extension String {
    func repeated(_ count: Int) -> String {
        return String(repeating: self, count: count)
    }
}