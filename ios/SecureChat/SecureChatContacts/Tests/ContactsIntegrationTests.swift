import XCTest
import Combine
@testable import SecureChatContacts
@testable import SecureChatStorage

final class ContactsIntegrationTests: XCTestCase {

    var contactsService: ContactsService!
    var mockNetworkService: MockContactDiscoveryNetworkService!
    var mockContactDAO: MockContactDAO!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        setupMockServices()
    }

    override func tearDown() {
        cancellables.removeAll()
        contactsService = nil
        mockNetworkService = nil
        mockContactDAO = nil
        super.tearDown()
    }

    // MARK: - Setup

    private func setupMockServices() {
        mockNetworkService = MockContactDiscoveryNetworkService()
        mockContactDAO = MockContactDAO()

        let contactsManager = ContactsManager()
        let permissionManager = ContactPermissionManager()
        let discoveryService = ContactDiscoveryService(
            contactsManager: contactsManager,
            networkService: mockNetworkService
        )

        contactsService = ContactsService(
            contactsManager: contactsManager,
            permissionManager: permissionManager,
            discoveryService: discoveryService,
            contactDAO: mockContactDAO
        )
    }

    // MARK: - Integration Tests

    func testCompleteContactDiscoveryFlow() async throws {
        // Setup mock data
        let deviceContacts = createMockDeviceContacts()
        let hasher = PhoneNumberHasher()

        // Create expected hashes
        let phoneHashes = deviceContacts.compactMap {
            hasher.hashPhoneNumber($0.phoneNumber)
        }

        // Setup mock network response (simulate 2 out of 3 contacts are registered)
        mockNetworkService.setMockRegisteredHashes([
            phoneHashes[0], // John Doe is registered
            phoneHashes[2]  // Bob Wilson is registered
        ])

        // Mock contact DAO responses
        mockContactDAO.shouldSucceed = true

        // Perform contact discovery
        await contactsService.syncContacts()

        // Verify network call was made
        XCTAssertEqual(mockNetworkService.checkRegisteredUsersCalls.count, 1)

        let networkRequest = mockNetworkService.checkRegisteredUsersCalls.first!
        XCTAssertEqual(Set(networkRequest.hashes), Set(phoneHashes))

        // Verify contacts were saved to storage
        XCTAssertEqual(mockContactDAO.insertBatchCalls.count, 1)
        let savedContacts = mockContactDAO.insertBatchCalls.first!
        XCTAssertEqual(savedContacts.count, 2) // Only registered users should be saved

        // Verify sync status
        if case .completed(let result) = contactsService.syncStatus {
            XCTAssertEqual(result.discoveredContacts.count, 2)
            XCTAssertEqual(result.registeredCount, 2)
            XCTAssertEqual(result.totalHashesChecked, 3)
        } else {
            XCTFail("Expected completed sync status")
        }
    }

    func testContactDiscoveryNetworkError() async {
        // Setup network to fail
        mockNetworkService.configureMockFailure(
            error: ContactError.networkError(underlying: NSError(domain: "Test", code: -1))
        )

        // Perform contact discovery
        await contactsService.syncContacts()

        // Verify error state
        if case .failed(let error) = contactsService.syncStatus {
            if case .networkError = error {
                // Expected error type
            } else {
                XCTFail("Expected network error")
            }
        } else {
            XCTFail("Expected failed sync status")
        }

        // Verify no contacts were saved
        XCTAssertTrue(mockContactDAO.insertBatchCalls.isEmpty)
    }

    func testPhoneNumberNormalizationAndHashing() {
        let normalizer = PhoneNumberNormalizer()
        let hasher = PhoneNumberHasher()

        let testCases = [
            ("0555 123 45 67", "+905551234567"),
            ("+90 555 123 45 67", "+905551234567"),
            ("(0555) 123-45-67", "+905551234567"),
            ("555 123 45 67", "+905551234567")
        ]

        for (input, expectedE164) in testCases {
            // Test normalization
            let normalizedNumber = normalizer.normalizeToE164(input)
            XCTAssertEqual(normalizedNumber, expectedE164, "Failed to normalize \(input)")

            // Test hashing consistency
            if let e164 = normalizedNumber {
                let hash1 = hasher.hashPhoneNumber(e164)
                let hash2 = hasher.hashPhoneNumber(e164)
                XCTAssertEqual(hash1, hash2, "Hash should be consistent for \(e164)")
                XCTAssertEqual(hash1?.count, 64, "Hash should be 64 characters for \(e164)")
            }
        }
    }

    func testContactSearchAndFiltering() async throws {
        // Setup registered contacts
        let registeredContacts = [
            RegisteredContact(
                userId: "user1",
                displayName: "John Doe",
                phoneNumber: "+905551234567",
                phoneHash: "hash1"
            ),
            RegisteredContact(
                userId: "user2",
                displayName: "Jane Smith",
                phoneNumber: "+905551234568",
                phoneHash: "hash2"
            ),
            RegisteredContact(
                userId: "user3",
                displayName: "Bob Wilson",
                phoneNumber: "+905551234569",
                phoneHash: "hash3"
            )
        ]

        // Mock the registered contacts in the service
        await mockContactDAO.insertBatch(registeredContacts.map { contact in
            ContactData(
                id: contact.userId,
                phoneNumber: contact.phoneNumber,
                phoneHash: contact.phoneHash,
                displayName: contact.displayName,
                isRegistered: true
            )
        })

        // Reload cached contacts
        contactsService = ContactsService(
            contactsManager: ContactsManager(),
            permissionManager: ContactPermissionManager(),
            discoveryService: ContactDiscoveryService(
                contactsManager: ContactsManager(),
                networkService: mockNetworkService
            ),
            contactDAO: mockContactDAO
        )

        // Test search functionality
        let johnResults = contactsService.searchRegisteredContacts(query: "John")
        XCTAssertEqual(johnResults.count, 1)
        XCTAssertEqual(johnResults.first?.displayName, "John Doe")

        let phoneResults = contactsService.searchRegisteredContacts(query: "555123456")
        XCTAssertEqual(phoneResults.count, 3) // All have this pattern

        let emptyResults = contactsService.searchRegisteredContacts(query: "")
        XCTAssertEqual(emptyResults.count, 3) // Empty query returns all

        // Test specific lookups
        let johnByPhone = contactsService.findRegisteredContact(by: "+905551234567")
        XCTAssertEqual(johnByPhone?.displayName, "John Doe")

        let janeByUserId = contactsService.findRegisteredContact(by: "user2")
        XCTAssertEqual(janeByUserId?.displayName, "Jane Smith")

        let bobByHash = contactsService.findRegisteredContact(by: "hash3")
        XCTAssertEqual(bobByHash?.displayName, "Bob Wilson")
    }

    func testManualContactAddition() async throws {
        // Setup mock to return registered user
        let phoneNumber = "+905551234567"
        let hash = PhoneNumberHasher().hashPhoneNumber(phoneNumber)!

        mockNetworkService.setMockRegisteredUsers([
            ServerUser(userId: "manual_user", phoneHash: hash)
        ])
        mockContactDAO.shouldSucceed = true

        // Add manual contact
        let addedContact = try await contactsService.addManualContact(
            phoneNumber: "0555 123 45 67", // Different format
            displayName: "Manual Contact"
        )

        XCTAssertNotNil(addedContact)
        XCTAssertEqual(addedContact?.displayName, "Manual Contact")
        XCTAssertEqual(addedContact?.phoneNumber, phoneNumber)
        XCTAssertEqual(addedContact?.userId, "manual_user")

        // Verify network call was made
        XCTAssertEqual(mockNetworkService.checkRegisteredUsersCalls.count, 1)

        // Verify contact was saved
        XCTAssertEqual(mockContactDAO.insertBatchCalls.count, 1)
    }

    func testContactStatistics() {
        let stats = contactsService.getContactStatistics()

        XCTAssertEqual(stats.totalRegisteredContacts, 0) // No contacts loaded yet
        XCTAssertNil(stats.lastSyncDate) // Never synced
        XCTAssertTrue(stats.hasNeverSynced)
        XCTAssertNil(stats.daysSinceLastSync)
    }

    func testPrivacyCompliance() {
        let hasher = PhoneNumberHasher()
        let phoneNumber = "+905551234567"

        // Verify phone number cannot be recovered from hash
        let hash = hasher.hashPhoneNumber(phoneNumber)!

        // Hash should not contain any part of the original number
        XCTAssertFalse(hash.contains("90"))
        XCTAssertFalse(hash.contains("555"))
        XCTAssertFalse(hash.contains("1234567"))
        XCTAssertFalse(hash.contains("+"))

        // Hash should be one-way (no reverse lookup possible)
        XCTAssertNotEqual(hash, phoneNumber)
        XCTAssertNotEqual(hash, phoneNumber.replacingOccurrences(of: "+", with: ""))

        // Multiple different numbers should produce unique hashes
        let numbers = [
            "+905551234567",
            "+905551234568",
            "+905551234569"
        ]

        let hashes = numbers.compactMap { hasher.hashPhoneNumber($0) }
        let uniqueHashes = Set(hashes)

        XCTAssertEqual(hashes.count, uniqueHashes.count, "All hashes should be unique")
    }

    // MARK: - Helper Methods

    private func createMockDeviceContacts() -> [DeviceContact] {
        return [
            DeviceContact(
                id: "1",
                displayName: "John Doe",
                phoneNumber: "+905551234567"
            ),
            DeviceContact(
                id: "2",
                displayName: "Jane Smith",
                phoneNumber: "+905551234568"
            ),
            DeviceContact(
                id: "3",
                displayName: "Bob Wilson",
                phoneNumber: "+905551234569"
            )
        ]
    }
}

// MARK: - Mock Contact DAO

class MockContactDAO: ContactDAO, @unchecked Sendable {

    var shouldSucceed = true
    var mockContacts: [ContactData] = []
    var insertBatchCalls: [[ContactData]] = []

    override func insertBatch(_ contacts: [ContactData]) async throws {
        guard shouldSucceed else {
            throw ContactError.storageError(underlying: NSError(domain: "Mock", code: -1))
        }

        insertBatchCalls.append(contacts)
        mockContacts.append(contentsOf: contacts)
    }

    override func getRegisteredContacts() -> AnyPublisher<[Contact], Never> {
        // Return mock data converted to Core Data objects
        // This is a simplified mock - in real tests you'd need proper Core Data mocking
        return Just([]).eraseToAnyPublisher()
    }

    override func getAll() -> AnyPublisher<[Contact], Never> {
        return Just([]).eraseToAnyPublisher()
    }
}