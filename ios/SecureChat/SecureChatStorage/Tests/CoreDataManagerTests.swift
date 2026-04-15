import XCTest
import CoreData
@testable import SecureChatStorage

/// CoreDataManager unit testleri.
/// In-memory Core Data stack kullanarak hızlı test.
class CoreDataManagerTests: XCTestCase {

    var coreDataManager: CoreDataManager!

    override func setUp() {
        super.setUp()
        coreDataManager = createInMemoryCoreDataManager()
    }

    override func tearDown() {
        coreDataManager = nil
        super.tearDown()
    }

    // MARK: - Test Methods

    func testInMemoryStoreCreation() {
        // Arrange & Act
        let context = coreDataManager.viewContext

        // Assert
        XCTAssertNotNil(context)
        XCTAssertEqual(context.persistentStoreCoordinator?.persistentStores.count, 1)
        XCTAssertTrue(context.persistentStoreCoordinator?.persistentStores.first?.url?.absoluteString.contains("memory") ?? false)
    }

    func testSaveContext() {
        // Arrange
        let context = coreDataManager.viewContext
        let message = Message(context: context)
        message.id = "test-message-id"
        message.content = "Test message"
        message.timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // Act & Assert
        XCTAssertNoThrow(coreDataManager.save())
    }

    func testBackgroundContext() {
        // Act
        let backgroundContext = coreDataManager.newBackgroundContext()

        // Assert
        XCTAssertNotNil(backgroundContext)
        XCTAssertNotEqual(backgroundContext, coreDataManager.viewContext)
        XCTAssertEqual(backgroundContext.concurrencyType, .privateQueueConcurrencyType)
    }

    func testNukeAllData() async throws {
        // Arrange
        let context = coreDataManager.viewContext

        // Test verisi ekle
        let message = Message(context: context)
        message.id = "test-message"
        message.content = "Test"
        message.timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        let conversation = Conversation(context: context)
        conversation.id = "test-conversation"
        conversation.peerName = "Test Peer"

        coreDataManager.save()

        // Act
        try await coreDataManager.nukeAllData()

        // Assert
        let messageCount = try context.count(for: Message.fetchRequest())
        let conversationCount = try context.count(for: Conversation.fetchRequest())

        XCTAssertEqual(messageCount, 0)
        XCTAssertEqual(conversationCount, 0)
    }

    // MARK: - Helper Methods

    /// Test için in-memory Core Data stack oluştur
    private func createInMemoryCoreDataManager() -> CoreDataManager {
        let testCoreDataManager = TestCoreDataManager()
        return testCoreDataManager
    }
}

/// Test için özel CoreDataManager implementasyonu
class TestCoreDataManager: CoreDataManager {

    override init() {
        super.init()
        setupInMemoryStore()
    }

    private func setupInMemoryStore() {
        let container = NSPersistentContainer(name: "SecureChatModel")

        // In-memory store konfigürasyonu
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load in-memory store: \(error)")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true

        // Private reflection kullanarak lazy property'yi override et
        // Production kodunda lazy property kullanıldığı için bu gerekli
        setValue(container, forKey: "_persistentContainer")
    }

    // Lazy property override için helper
    private var _persistentContainer: NSPersistentContainer?

    override var persistentContainer: NSPersistentContainer {
        get {
            return _persistentContainer ?? super.persistentContainer
        }
        set {
            _persistentContainer = newValue
        }
    }
}