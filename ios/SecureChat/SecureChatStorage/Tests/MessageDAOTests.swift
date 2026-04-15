import XCTest
import CoreData
import Combine
@testable import SecureChatStorage

/// MessageDAO unit testleri.
/// CRUD operasyonları ve reactive flow testleri.
class MessageDAOTests: XCTestCase {

    var messageDAO: MessageDAO!
    var coreDataManager: CoreDataManager!
    var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        coreDataManager = createInMemoryCoreDataManager()
        messageDAO = MessageDAO(coreDataManager: coreDataManager)
    }

    override func tearDown() {
        cancellables.removeAll()
        messageDAO = nil
        coreDataManager = nil
        super.tearDown()
    }

    // MARK: - Test Methods

    func testInsertMessage() async throws {
        // Arrange
        let messageData = createTestMessageData()

        // Act
        try await messageDAO.insert(messageData)

        // Assert
        let context = coreDataManager.viewContext
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        let messages = try context.fetch(request)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.id, messageData.id)
        XCTAssertEqual(messages.first?.content, messageData.content)
        XCTAssertEqual(messages.first?.status, messageData.status.rawValue)
    }

    func testGetMessages() async throws {
        // Arrange
        let conversationId = "test-conversation"
        let messageData1 = createTestMessageData(id: "msg1", conversationId: conversationId, timestamp: 1000)
        let messageData2 = createTestMessageData(id: "msg2", conversationId: conversationId, timestamp: 2000)

        try await messageDAO.insert(messageData1)
        try await messageDAO.insert(messageData2)

        // Act & Assert
        let expectation = XCTestExpectation(description: "Messages received")
        var receivedMessages: [Message] = []

        messageDAO.getMessages(conversationId: conversationId)
            .sink(receiveValue: { messages in
                receivedMessages = messages
                expectation.fulfill()
            })
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(receivedMessages.count, 2)
        // Timestamp'e göre sıralı olmalı (ASC)
        XCTAssertEqual(receivedMessages[0].id, "msg1")
        XCTAssertEqual(receivedMessages[1].id, "msg2")
    }

    func testUpdateMessageStatus() async throws {
        // Arrange
        let messageData = createTestMessageData(status: .sending)
        try await messageDAO.insert(messageData)

        // Act
        try await messageDAO.updateStatus(messageId: messageData.id, status: .delivered)

        // Assert
        let context = coreDataManager.viewContext
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", messageData.id)

        let messages = try context.fetch(request)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.status, MessageStatus.delivered.rawValue)
    }

    func testDeleteMessage() async throws {
        // Arrange
        let messageData = createTestMessageData()
        try await messageDAO.insert(messageData)

        // Act
        try await messageDAO.delete(messageId: messageData.id)

        // Assert
        let context = coreDataManager.viewContext
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        let messages = try context.fetch(request)

        XCTAssertEqual(messages.count, 0)
    }

    func testDeleteByConversation() async throws {
        // Arrange
        let conversationId = "test-conversation"
        let messageData1 = createTestMessageData(id: "msg1", conversationId: conversationId)
        let messageData2 = createTestMessageData(id: "msg2", conversationId: conversationId)
        let messageData3 = createTestMessageData(id: "msg3", conversationId: "other-conversation")

        try await messageDAO.insert(messageData1)
        try await messageDAO.insert(messageData2)
        try await messageDAO.insert(messageData3)

        // Act
        try await messageDAO.deleteByConversation(conversationId: conversationId)

        // Assert
        let context = coreDataManager.viewContext
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        let remainingMessages = try context.fetch(request)

        XCTAssertEqual(remainingMessages.count, 1)
        XCTAssertEqual(remainingMessages.first?.id, "msg3")
    }

    func testGetUnreadCount() async throws {
        // Arrange
        let conversationId = "test-conversation"

        // 2 okunmamış incoming mesaj
        let unreadMsg1 = createTestMessageData(id: "unread1", conversationId: conversationId,
                                               status: .delivered, isOutgoing: false)
        let unreadMsg2 = createTestMessageData(id: "unread2", conversationId: conversationId,
                                               status: .sent, isOutgoing: false)

        // 1 okunmuş incoming mesaj
        let readMsg = createTestMessageData(id: "read", conversationId: conversationId,
                                            status: .read, isOutgoing: false)

        // 1 outgoing mesaj (sayılmamalı)
        let outgoingMsg = createTestMessageData(id: "outgoing", conversationId: conversationId,
                                                status: .delivered, isOutgoing: true)

        try await messageDAO.insert(unreadMsg1)
        try await messageDAO.insert(unreadMsg2)
        try await messageDAO.insert(readMsg)
        try await messageDAO.insert(outgoingMsg)

        // Act & Assert
        let expectation = XCTestExpectation(description: "Unread count received")
        var unreadCount = 0

        messageDAO.getUnreadCount(conversationId: conversationId)
            .sink(receiveValue: { count in
                unreadCount = count
                expectation.fulfill()
            })
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(unreadCount, 2) // Sadece okunmamış incoming mesajlar
    }

    func testGetRecentMessages() async throws {
        // Arrange
        let conversationId = "test-conversation"
        let limit = 2

        for i in 1...5 {
            let messageData = createTestMessageData(
                id: "msg\(i)",
                conversationId: conversationId,
                timestamp: Int64(i * 1000)
            )
            try await messageDAO.insert(messageData)
        }

        // Act & Assert
        let expectation = XCTestExpectation(description: "Recent messages received")
        var recentMessages: [Message] = []

        messageDAO.getRecentMessages(conversationId: conversationId, limit: limit)
            .sink(receiveValue: { messages in
                recentMessages = messages
                expectation.fulfill()
            })
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(recentMessages.count, limit)
        // Son mesajlar (DESC order) - msg5, msg4
        XCTAssertEqual(recentMessages[0].id, "msg5")
        XCTAssertEqual(recentMessages[1].id, "msg4")
    }

    func testDeleteOlderThan() async throws {
        // Arrange
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let oneDayAgo = now - (24 * 60 * 60 * 1000)
        let twoDaysAgo = now - (2 * 24 * 60 * 60 * 1000)

        let oldMessage = createTestMessageData(id: "old", timestamp: twoDaysAgo)
        let recentMessage = createTestMessageData(id: "recent", timestamp: now)

        try await messageDAO.insert(oldMessage)
        try await messageDAO.insert(recentMessage)

        // Act - 1 günden eski mesajları sil
        try await messageDAO.deleteOlderThan(cutoff: oneDayAgo)

        // Assert
        let context = coreDataManager.viewContext
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        let remainingMessages = try context.fetch(request)

        XCTAssertEqual(remainingMessages.count, 1)
        XCTAssertEqual(remainingMessages.first?.id, "recent")
    }

    // MARK: - Helper Methods

    private func createTestMessageData(
        id: String = "test-message-id",
        conversationId: String = "test-conversation-id",
        content: String = "Test message content",
        contentType: MessageContentType = .text,
        timestamp: Int64 = 0,
        status: MessageStatus = .sent,
        isOutgoing: Bool = true
    ) -> MessageData {
        let actualTimestamp = timestamp == 0 ? Int64(Date().timeIntervalSince1970 * 1000) : timestamp

        return MessageData(
            id: id,
            conversationId: conversationId,
            senderId: "test-sender-id",
            content: content,
            contentType: contentType,
            timestamp: actualTimestamp,
            status: status,
            replyToId: nil,
            isOutgoing: isOutgoing
        )
    }

    private func createInMemoryCoreDataManager() -> CoreDataManager {
        return TestCoreDataManager()
    }
}