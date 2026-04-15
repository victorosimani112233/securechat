import Foundation
import SecureChatStorage

/// Helper class for setting up the contacts module in your app.
/// Provides factory methods and configuration for all contacts components.
public final class ContactsModuleSetup {

    // MARK: - Configuration

    public struct Configuration {
        public let serverBaseURL: URL
        public let apiKey: String?
        public let networkTimeout: TimeInterval
        public let enableAutoSync: Bool
        public let batchSize: Int

        public init(
            serverBaseURL: URL,
            apiKey: String? = nil,
            networkTimeout: TimeInterval = 30,
            enableAutoSync: Bool = true,
            batchSize: Int = 1000
        ) {
            self.serverBaseURL = serverBaseURL
            self.apiKey = apiKey
            self.networkTimeout = networkTimeout
            self.enableAutoSync = enableAutoSync
            self.batchSize = batchSize
        }

        public static let development = Configuration(
            serverBaseURL: URL(string: "https://dev.securechat.com")!,
            networkTimeout: 10,
            enableAutoSync: true,
            batchSize: 500
        )

        public static let production = Configuration(
            serverBaseURL: URL(string: "https://api.securechat.com")!,
            networkTimeout: 30,
            enableAutoSync: true,
            batchSize: 1000
        )
    }

    // MARK: - Factory Methods

    /// Creates a fully configured ContactsService instance.
    /// - Parameters:
    ///   - configuration: Module configuration
    ///   - contactDAO: Storage layer for contacts (from SecureChatStorage module)
    /// - Returns: Ready-to-use ContactsService
    public static func createContactsService(
        configuration: Configuration,
        contactDAO: ContactDAO
    ) -> ContactsService {
        // Create network service
        let networkService = ContactDiscoveryNetworkServiceFactory.create(
            baseURL: configuration.serverBaseURL,
            apiKey: configuration.apiKey
        )

        // Create core components
        let contactsManager = ContactsManager()
        let permissionManager = ContactPermissionManager()
        let discoveryService = ContactDiscoveryService(
            contactsManager: contactsManager,
            networkService: networkService
        )

        // Create main service
        let contactsService = ContactsService(
            contactsManager: contactsManager,
            permissionManager: permissionManager,
            discoveryService: discoveryService,
            contactDAO: contactDAO
        )

        // Enable auto sync if configured
        if configuration.enableAutoSync {
            contactsService.enableAutoSync()
        }

        return contactsService
    }

    /// Creates ContactsService with mock network service (for testing/development).
    /// - Parameter contactDAO: Storage layer for contacts
    /// - Returns: ContactsService with mocked network calls
    public static func createMockContactsService(
        contactDAO: ContactDAO,
        mockRegisteredUsers: [ServerUser] = []
    ) -> ContactsService {
        let mockNetworkService = ContactDiscoveryNetworkServiceFactory.createMock(
            registeredUsers: mockRegisteredUsers
        )

        let contactsManager = ContactsManager()
        let permissionManager = ContactPermissionManager()
        let discoveryService = ContactDiscoveryService(
            contactsManager: contactsManager,
            networkService: mockNetworkService
        )

        return ContactsService(
            contactsManager: contactsManager,
            permissionManager: permissionManager,
            discoveryService: discoveryService,
            contactDAO: contactDAO
        )
    }
}

// MARK: - App Integration Examples

/// Example integration patterns for different app architectures.
public final class ContactsIntegrationExamples {

    // MARK: - SwiftUI Integration

    /// SwiftUI view model for contact management screens.
    @MainActor
    public final class ContactsViewModel: ObservableObject {
        @Published public private(set) var registeredContacts: [RegisteredContact] = []
        @Published public private(set) var syncStatus: ContactSyncStatus = .idle
        @Published public private(set) var permissionStatus: ContactPermissionStatus = .notDetermined
        @Published public private(set) var isLoading = false

        private let contactsService: ContactsService
        private var cancellables = Set<AnyCancellable>()

        public init(contactsService: ContactsService) {
            self.contactsService = contactsService
            setupObservers()
        }

        // MARK: - Public Methods

        public func requestPermissionAndSync() async {
            isLoading = true
            defer { isLoading = false }

            let granted = await contactsService.requestContactPermission()
            if granted {
                await contactsService.syncContacts()
            }
        }

        public func syncContacts() async {
            isLoading = true
            defer { isLoading = false }

            await contactsService.syncContacts()
        }

        public func searchContacts(_ query: String) -> [RegisteredContact] {
            return contactsService.searchRegisteredContacts(query: query)
        }

        public func addManualContact(phoneNumber: String, displayName: String) async {
            isLoading = true
            defer { isLoading = false }

            do {
                _ = try await contactsService.addManualContact(
                    phoneNumber: phoneNumber,
                    displayName: displayName
                )
            } catch {
                print("Failed to add manual contact: \(error)")
            }
        }

        public func openContactSettings() {
            contactsService.openContactSettings()
        }

        // MARK: - Private Methods

        private func setupObservers() {
            contactsService.$registeredContacts
                .receive(on: DispatchQueue.main)
                .assign(to: &$registeredContacts)

            contactsService.$syncStatus
                .receive(on: DispatchQueue.main)
                .assign(to: &$syncStatus)

            contactsService.$permissionStatus
                .receive(on: DispatchQueue.main)
                .assign(to: &$permissionStatus)
        }
    }

    // MARK: - UIKit Integration

    /// UIKit view controller for contact management.
    public final class ContactsViewController: UIViewController {
        private let contactsService: ContactsService
        private var cancellables = Set<AnyCancellable>()

        public init(contactsService: ContactsService) {
            self.contactsService = contactsService
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func viewDidLoad() {
            super.viewDidLoad()
            setupUI()
            setupObservers()
            checkPermissionsAndSync()
        }

        private func setupUI() {
            title = "Contacts"
            view.backgroundColor = .systemBackground

            // Add your UI setup here
        }

        private func setupObservers() {
            contactsService.$syncStatus
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    self?.handleSyncStatusChange(status)
                }
                .store(in: &cancellables)

            contactsService.$registeredContacts
                .receive(on: DispatchQueue.main)
                .sink { [weak self] contacts in
                    self?.updateContactsList(contacts)
                }
                .store(in: &cancellables)
        }

        private func checkPermissionsAndSync() {
            Task {
                if contactsService.hasContactPermission {
                    await contactsService.syncContacts()
                } else {
                    await requestPermission()
                }
            }
        }

        @MainActor
        private func requestPermission() async {
            let granted = await contactsService.requestContactPermission()
            if granted {
                await contactsService.syncContacts()
            } else {
                showPermissionDeniedAlert()
            }
        }

        private func handleSyncStatusChange(_ status: ContactSyncStatus) {
            switch status {
            case .idle:
                hideLoadingIndicator()
            case .syncing:
                showLoadingIndicator()
            case .completed(let result):
                hideLoadingIndicator()
                showSyncCompletedMessage(result)
            case .failed(let error):
                hideLoadingIndicator()
                showErrorAlert(error)
            }
        }

        private func updateContactsList(_ contacts: [RegisteredContact]) {
            // Update your table view or collection view
        }

        private func showLoadingIndicator() {
            // Show loading UI
        }

        private func hideLoadingIndicator() {
            // Hide loading UI
        }

        private func showSyncCompletedMessage(_ result: ContactDiscoveryResult) {
            // Show success message
        }

        private func showErrorAlert(_ error: ContactError) {
            let alert = UIAlertController(
                title: "Sync Failed",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }

        private func showPermissionDeniedAlert() {
            let alert = UIAlertController(
                title: "Contacts Permission Required",
                message: "Please grant contacts permission to find your friends on SecureChat.",
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                self.contactsService.openContactSettings()
            })

            alert.addAction(UIAlertAction(title: "Skip", style: .cancel))

            present(alert, animated: true)
        }
    }
}

// MARK: - Testing Utilities

/// Utilities for testing contact functionality.
public final class ContactsTestingUtilities {

    /// Creates sample device contacts for testing.
    public static func createSampleDeviceContacts() -> [DeviceContact] {
        return [
            DeviceContact(
                id: "1",
                displayName: "Alice Johnson",
                phoneNumber: "+905551234567",
                avatarUri: nil
            ),
            DeviceContact(
                id: "2",
                displayName: "Bob Smith",
                phoneNumber: "+905551234568",
                avatarUri: "contact://avatar2"
            ),
            DeviceContact(
                id: "3",
                displayName: "Charlie Brown",
                phoneNumber: "+905551234569",
                avatarUri: nil
            ),
            DeviceContact(
                id: "4",
                displayName: "Diana Prince",
                phoneNumber: "+905551234570",
                avatarUri: "contact://avatar4"
            )
        ]
    }

    /// Creates sample registered contacts for testing.
    public static func createSampleRegisteredContacts() -> [RegisteredContact] {
        return [
            RegisteredContact(
                userId: "user1",
                displayName: "Alice Johnson",
                phoneNumber: "+905551234567",
                phoneHash: PhoneNumberHasher().hashPhoneNumber("+905551234567")!,
                avatarUri: nil
            ),
            RegisteredContact(
                userId: "user2",
                displayName: "Bob Smith",
                phoneNumber: "+905551234568",
                phoneHash: PhoneNumberHasher().hashPhoneNumber("+905551234568")!,
                avatarUri: "contact://avatar2"
            )
        ]
    }

    /// Creates sample server users for mocking network responses.
    public static func createSampleServerUsers() -> [ServerUser] {
        let hasher = PhoneNumberHasher()
        return [
            ServerUser(
                userId: "user1",
                phoneHash: hasher.hashPhoneNumber("+905551234567")!
            ),
            ServerUser(
                userId: "user2",
                phoneHash: hasher.hashPhoneNumber("+905551234568")!
            )
        ]
    }

    /// Validates phone number normalization and hashing consistency.
    public static func validateNormalizationAndHashing() -> Bool {
        let normalizer = PhoneNumberNormalizer()
        let hasher = PhoneNumberHasher()

        let testCases = [
            "0555 123 45 67",
            "+90 555 123 45 67",
            "(0555) 123-45-67",
            "555 123 45 67"
        ]

        let expectedE164 = "+905551234567"
        var allValid = true

        for testCase in testCases {
            guard let normalized = normalizer.normalizeToE164(testCase),
                  normalized == expectedE164,
                  let hash = hasher.hashPhoneNumber(normalized),
                  hash.count == 64,
                  hasher.isValidHash(hash) else {
                allValid = false
                print("Failed validation for: \(testCase)")
                continue
            }
        }

        return allValid
    }
}