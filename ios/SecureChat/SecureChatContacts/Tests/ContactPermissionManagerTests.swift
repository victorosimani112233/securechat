import XCTest
import Contacts
@testable import SecureChatContacts

final class ContactPermissionManagerTests: XCTestCase {

    var permissionManager: ContactPermissionManager!
    var mockContactStore: MockCNContactStore!

    override func setUp() {
        super.setUp()
        mockContactStore = MockCNContactStore()
        permissionManager = ContactPermissionManager(contactStore: mockContactStore)
    }

    override func tearDown() {
        permissionManager = nil
        mockContactStore = nil
        super.tearDown()
    }

    // MARK: - Permission Status Tests

    func testPermissionStatus_NotDetermined() {
        mockContactStore.authorizationStatus = .notDetermined

        let status = permissionManager.permissionStatus

        XCTAssertEqual(status, .notDetermined)
        XCTAssertFalse(status.isAuthorized)
    }

    func testPermissionStatus_Denied() {
        mockContactStore.authorizationStatus = .denied

        let status = permissionManager.permissionStatus

        XCTAssertEqual(status, .denied)
        XCTAssertFalse(status.isAuthorized)
    }

    func testPermissionStatus_Restricted() {
        mockContactStore.authorizationStatus = .restricted

        let status = permissionManager.permissionStatus

        XCTAssertEqual(status, .denied)
        XCTAssertFalse(status.isAuthorized)
    }

    func testPermissionStatus_Authorized() {
        mockContactStore.authorizationStatus = .authorized

        let status = permissionManager.permissionStatus

        XCTAssertEqual(status, .authorized)
        XCTAssertTrue(status.isAuthorized)
    }

    func testHasPermission_True() {
        mockContactStore.authorizationStatus = .authorized

        let hasPermission = permissionManager.hasPermission

        XCTAssertTrue(hasPermission)
    }

    func testHasPermission_False() {
        mockContactStore.authorizationStatus = .denied

        let hasPermission = permissionManager.hasPermission

        XCTAssertFalse(hasPermission)
    }

    // MARK: - Permission Request Tests

    @MainActor
    func testRequestPermission_AlreadyAuthorized() async {
        mockContactStore.authorizationStatus = .authorized

        let granted = await permissionManager.requestPermission()

        XCTAssertTrue(granted)
        XCTAssertFalse(mockContactStore.requestAccessCalled) // Should not call requestAccess if already authorized
    }

    @MainActor
    func testRequestPermission_GrantedByUser() async {
        mockContactStore.authorizationStatus = .notDetermined
        mockContactStore.requestAccessResult = .success(true)

        let granted = await permissionManager.requestPermission()

        XCTAssertTrue(granted)
        XCTAssertTrue(mockContactStore.requestAccessCalled)
    }

    @MainActor
    func testRequestPermission_DeniedByUser() async {
        mockContactStore.authorizationStatus = .notDetermined
        mockContactStore.requestAccessResult = .success(false)

        let granted = await permissionManager.requestPermission()

        XCTAssertFalse(granted)
        XCTAssertTrue(mockContactStore.requestAccessCalled)
    }

    @MainActor
    func testRequestPermission_RequestFailed() async {
        mockContactStore.authorizationStatus = .notDetermined
        mockContactStore.requestAccessResult = .failure(NSError(domain: "Test", code: -1))

        let granted = await permissionManager.requestPermission()

        XCTAssertFalse(granted)
        XCTAssertTrue(mockContactStore.requestAccessCalled)
    }

    // MARK: - Ensure Permission Tests

    @MainActor
    func testEnsurePermission_AlreadyAuthorized() async {
        mockContactStore.authorizationStatus = .authorized

        let hasPermission = await permissionManager.ensurePermission()

        XCTAssertTrue(hasPermission)
        XCTAssertFalse(mockContactStore.requestAccessCalled)
    }

    @MainActor
    func testEnsurePermission_Denied() async {
        mockContactStore.authorizationStatus = .denied

        let hasPermission = await permissionManager.ensurePermission()

        XCTAssertFalse(hasPermission)
        XCTAssertFalse(mockContactStore.requestAccessCalled) // Should not request if already denied
    }

    @MainActor
    func testEnsurePermission_NotDetermined_Granted() async {
        mockContactStore.authorizationStatus = .notDetermined
        mockContactStore.requestAccessResult = .success(true)

        let hasPermission = await permissionManager.ensurePermission()

        XCTAssertTrue(hasPermission)
        XCTAssertTrue(mockContactStore.requestAccessCalled)
    }

    @MainActor
    func testEnsurePermission_NotDetermined_Denied() async {
        mockContactStore.authorizationStatus = .notDetermined
        mockContactStore.requestAccessResult = .success(false)

        let hasPermission = await permissionManager.ensurePermission()

        XCTAssertFalse(hasPermission)
        XCTAssertTrue(mockContactStore.requestAccessCalled)
    }

    // MARK: - Permission Change Observation Tests

    func testObservePermissionChanges() {
        var receivedStatuses: [ContactPermissionStatus] = []
        let expectation = XCTestExpectation(description: "Permission change observed")

        permissionManager.observePermissionChanges { status in
            receivedStatuses.append(status)
            expectation.fulfill()
        }

        // Simulate app entering foreground
        mockContactStore.authorizationStatus = .authorized
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStatuses.count, 1)
        XCTAssertEqual(receivedStatuses.first, .authorized)
    }

    func testStopObservingPermissionChanges() {
        var receivedStatuses: [ContactPermissionStatus] = []

        permissionManager.observePermissionChanges { status in
            receivedStatuses.append(status)
        }

        // Stop observing
        permissionManager.stopObservingPermissionChanges()

        // Simulate app entering foreground
        mockContactStore.authorizationStatus = .denied
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)

        // Wait a bit to see if notification was received
        let expectation = XCTestExpectation(description: "Wait for potential notification")
        expectation.isInverted = true
        wait(for: [expectation], timeout: 0.5)

        XCTAssertTrue(receivedStatuses.isEmpty) // Should not receive any notifications after stopping
    }

    // MARK: - Settings Navigation Tests

    func testOpenSettings() {
        // This test verifies that the method doesn't crash
        // In a real test environment, we'd need to mock UIApplication.shared
        permissionManager.openSettings()
        // No assertion needed - just ensure it doesn't crash
    }

    // MARK: - Integration Tests

    @MainActor
    func testPermissionFlow_CompleteWorkflow() async {
        // Start with not determined
        mockContactStore.authorizationStatus = .notDetermined
        XCTAssertEqual(permissionManager.permissionStatus, .notDetermined)
        XCTAssertFalse(permissionManager.hasPermission)

        // User grants permission
        mockContactStore.requestAccessResult = .success(true)
        let granted = await permissionManager.requestPermission()
        XCTAssertTrue(granted)

        // Now it should be authorized (in real scenario, CNContactStore would update the status)
        mockContactStore.authorizationStatus = .authorized
        XCTAssertEqual(permissionManager.permissionStatus, .authorized)
        XCTAssertTrue(permissionManager.hasPermission)
    }
}

// MARK: - Mock CNContactStore

class MockCNContactStore: CNContactStore {
    var authorizationStatus: CNAuthorizationStatus = .notDetermined
    var requestAccessResult: Result<Bool, Error> = .success(false)
    var requestAccessCalled = false

    override class func authorizationStatus(for entityType: CNEntityType) -> CNAuthorizationStatus {
        // This is a static method, so we can't easily mock it in unit tests
        // In a real test setup, we'd need to use a protocol or dependency injection
        return .notDetermined
    }

    override func requestAccess(for entityType: CNEntityType) async throws -> Bool {
        requestAccessCalled = true
        switch requestAccessResult {
        case .success(let granted):
            return granted
        case .failure(let error):
            throw error
        }
    }
}

// Note: In a real-world scenario, we would need to use protocols and dependency injection
// to properly mock CNContactStore.authorizationStatus(for:) since it's a static method.
// For this example, we're focusing on the instance methods and the permission manager logic.