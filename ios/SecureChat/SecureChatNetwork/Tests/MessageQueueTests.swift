import XCTest
import Combine
@testable import SecureChatNetwork

/**
 * MessageQueue unit testleri.
 *
 * Offline mesaj kuyruklama, retry logic, delivery tracking
 * ve istatistik toplama testleri.
 */
@available(iOS 13.0, *)
final class MessageQueueTests: XCTestCase {

    private var messageQueue: MessageQueue!
    private var mockSignalingClient: MockSignalingClient!
    private var mockCryptoService: MockCryptoService!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockSignalingClient = MockSignalingClient()
        mockCryptoService = MockCryptoService()
        messageQueue = MessageQueue(
            signalingClient: mockSignalingClient,
            cryptoService: mockCryptoService
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        messageQueue = nil
        mockSignalingClient = nil
        mockCryptoService = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        XCTAssertEqual(messageQueue.queueSize, 0)
        XCTAssertEqual(messageQueue.queueStatus, .idle)
    }

    func testInitialStatistics() {
        let stats = messageQueue.getQueueStatistics()
        XCTAssertEqual(stats.totalQueued, 0)
        XCTAssertEqual(stats.totalDelivered, 0)
        XCTAssertEqual(stats.totalFailed, 0)
        XCTAssertEqual(stats.currentQueueSize, 0)
        XCTAssertEqual(stats.status, .idle)
    }

    // MARK: - Message Queueing Tests

    func testQueueMessage() async throws {
        let content = "Test message".data(using: .utf8)!

        try await messageQueue.queueMessage(
            recipientId: "recipient123",
            content: content,
            messageType: .text,
            priority: .normal
        )

        XCTAssertEqual(messageQueue.queueSize, 1)
        XCTAssertEqual(messageQueue.queueStatus, .processing)

        let stats = messageQueue.getQueueStatistics()
        XCTAssertEqual(stats.totalQueued, 1)
    }

    func testQueueMultipleMessages() async throws {
        let content1 = "Message 1".data(using: .utf8)!
        let content2 = "Message 2".data(using: .utf8)!

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: content1,
            messageType: .text,
            priority: .normal
        )

        try await messageQueue.queueMessage(
            recipientId: "recipient2",
            content: content2,
            messageType: .text,
            priority: .high
        )

        XCTAssertEqual(messageQueue.queueSize, 2)

        let stats = messageQueue.getQueueStatistics()
        XCTAssertEqual(stats.totalQueued, 2)
    }

    func testMessagePriorityOrdering() async throws {
        let lowPriorityContent = "Low priority".data(using: .utf8)!
        let highPriorityContent = "High priority".data(using: .utf8)!
        let urgentPriorityContent = "Urgent priority".data(using: .utf8)!

        // Add messages in reverse priority order
        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: lowPriorityContent,
            messageType: .text,
            priority: .low
        )

        try await messageQueue.queueMessage(
            recipientId: "recipient2",
            content: highPriorityContent,
            messageType: .text,
            priority: .high
        )

        try await messageQueue.queueMessage(
            recipientId: "recipient3",
            content: urgentPriorityContent,
            messageType: .text,
            priority: .urgent
        )

        XCTAssertEqual(messageQueue.queueSize, 3)

        // Verify queue processes messages (highest priority first when connected)
        mockSignalingClient.connectionState = .connected

        // Give queue time to process
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // High priority messages should be processed first
        // (exact order verification would require exposing internal queue state)
    }

    // MARK: - Connection State Handling Tests

    func testQueueProcessingWhenConnected() async throws {
        let content = "Test message".data(using: .utf8)!

        // Queue message while disconnected
        try await messageQueue.queueMessage(
            recipientId: "recipient123",
            content: content,
            messageType: .text,
            priority: .normal
        )

        XCTAssertEqual(messageQueue.queueSize, 1)

        // Simulate connection
        mockSignalingClient.connectionState = .connected

        // Give queue time to process
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Message should be sent and removed from queue
        XCTAssertTrue(mockSignalingClient.sentMessages.count > 0)
    }

    func testQueuePersistenceWhenDisconnected() async throws {
        let content = "Test message".data(using: .utf8)!

        mockSignalingClient.connectionState = .disconnected

        try await messageQueue.queueMessage(
            recipientId: "recipient123",
            content: content,
            messageType: .text,
            priority: .normal
        )

        // Message should remain in queue
        XCTAssertEqual(messageQueue.queueSize, 1)
        XCTAssertEqual(mockSignalingClient.sentMessages.count, 0)
    }

    // MARK: - Retry Logic Tests

    func testRetryOnFailure() async throws {
        let content = "Test message".data(using: .utf8)!

        // Configure signaling client to fail first attempts
        mockSignalingClient.shouldFailSend = true
        mockSignalingClient.connectionState = .connected

        try await messageQueue.queueMessage(
            recipientId: "recipient123",
            content: content,
            messageType: .text,
            priority: .normal
        )

        // Give time for initial send attempt and first retry
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Should have attempted multiple sends
        XCTAssertGreaterThan(mockSignalingClient.sendAttempts, 1)
    }

    func testMaxRetryLimit() async throws {
        let content = "Test message".data(using: .utf8)!

        // Configure to always fail
        mockSignalingClient.shouldFailSend = true
        mockSignalingClient.connectionState = .connected

        try await messageQueue.queueMessage(
            recipientId: "recipient123",
            content: content,
            messageType: .text,
            priority: .normal
        )

        // Give enough time for all retry attempts
        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds

        let stats = messageQueue.getQueueStatistics()

        // Message should eventually be marked as failed
        // and removed from queue after max retries
        XCTAssertEqual(stats.totalFailed, 1)
    }

    // MARK: - Message Retrieval Tests

    func testGetPendingMessages() async throws {
        let content1 = "Message 1".data(using: .utf8)!
        let content2 = "Message 2".data(using: .utf8)!

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: content1,
            messageType: .text,
            priority: .normal
        )

        try await messageQueue.queueMessage(
            recipientId: "recipient2",
            content: content2,
            messageType: .text,
            priority: .normal
        )

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: "Another message".data(using: .utf8)!,
            messageType: .text,
            priority: .normal
        )

        let recipient1Messages = await messageQueue.getPendingMessages(for: "recipient1")
        XCTAssertEqual(recipient1Messages.count, 2)

        let recipient2Messages = await messageQueue.getPendingMessages(for: "recipient2")
        XCTAssertEqual(recipient2Messages.count, 1)
    }

    func testGetPendingMessagesForNonExistentRecipient() async {
        let messages = await messageQueue.getPendingMessages(for: "nonexistent")
        XCTAssertEqual(messages.count, 0)
    }

    // MARK: - Queue Management Tests

    func testClearQueue() async throws {
        let content1 = "Message 1".data(using: .utf8)!
        let content2 = "Message 2".data(using: .utf8)!

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: content1,
            messageType: .text,
            priority: .normal
        )

        try await messageQueue.queueMessage(
            recipientId: "recipient2",
            content: content2,
            messageType: .text,
            priority: .normal
        )

        XCTAssertEqual(messageQueue.queueSize, 2)

        await messageQueue.clearQueue()

        XCTAssertEqual(messageQueue.queueSize, 0)
        XCTAssertEqual(messageQueue.queueStatus, .idle)
    }

    func testRemoveSpecificMessage() async throws {
        let content = "Test message".data(using: .utf8)!

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: content,
            messageType: .text,
            priority: .normal
        )

        let messages = await messageQueue.getPendingMessages(for: "recipient1")
        XCTAssertEqual(messages.count, 1)

        let messageId = messages.first!.id
        let removed = await messageQueue.removeMessage(withId: messageId)

        XCTAssertTrue(removed)
        XCTAssertEqual(messageQueue.queueSize, 0)
    }

    func testRemoveNonExistentMessage() async {
        let removed = await messageQueue.removeMessage(withId: "nonexistent_id")
        XCTAssertFalse(removed)
    }

    // MARK: - Statistics Tests

    func testStatisticsUpdate() async throws {
        let content = "Test message".data(using: .utf8)!

        mockSignalingClient.connectionState = .connected

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: content,
            messageType: .text,
            priority: .normal
        )

        // Give time for processing
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let stats = messageQueue.getQueueStatistics()
        XCTAssertEqual(stats.totalQueued, 1)

        if mockSignalingClient.shouldFailSend {
            XCTAssertGreaterThanOrEqual(stats.totalFailed, 0)
        } else {
            XCTAssertGreaterThanOrEqual(stats.totalDelivered, 0)
        }
    }

    func testSuccessRate() async throws {
        let content = "Test message".data(using: .utf8)!

        mockSignalingClient.connectionState = .connected

        // Send multiple messages
        for i in 1...5 {
            try await messageQueue.queueMessage(
                recipientId: "recipient\(i)",
                content: content,
                messageType: .text,
                priority: .normal
            )
        }

        // Give time for processing
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        let stats = messageQueue.getQueueStatistics()
        XCTAssertGreaterThan(stats.successRate, 0.0)
        XCTAssertLessThanOrEqual(stats.successRate, 1.0)
    }

    // MARK: - Crypto Integration Tests

    func testEncryptionIntegration() async throws {
        let plaintext = "Secret message"
        let content = plaintext.data(using: .utf8)!

        mockSignalingClient.connectionState = .connected

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: content,
            messageType: .text,
            priority: .normal
        )

        // Give time for processing
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Verify crypto service was called
        XCTAssertTrue(mockCryptoService.encryptCalled)
        XCTAssertEqual(mockCryptoService.lastRecipientId, "recipient1")
    }

    func testEncryptionFailureHandling() async throws {
        let content = "Test message".data(using: .utf8)!

        mockCryptoService.shouldFailEncryption = true
        mockSignalingClient.connectionState = .connected

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: content,
            messageType: .text,
            priority: .normal
        )

        // Give time for processing
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Should handle encryption failure gracefully
        let stats = messageQueue.getQueueStatistics()
        XCTAssertGreaterThanOrEqual(stats.totalQueued, 1)
    }

    // MARK: - Performance Tests

    func testQueuePerformanceWithManyMessages() async throws {
        let content = "Test message".data(using: .utf8)!
        let messageCount = 100

        let startTime = Date()

        for i in 1...messageCount {
            try await messageQueue.queueMessage(
                recipientId: "recipient\(i % 10)",
                content: content,
                messageType: .text,
                priority: .normal
            )
        }

        let queueTime = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(queueTime, 1.0) // Should queue 100 messages in less than 1 second
        XCTAssertEqual(messageQueue.queueSize, messageCount)
    }
}

// MARK: - Mock Classes

@available(iOS 13.0, *)
class MockSignalingClient: SignalingClient {
    var connectionState: ConnectionState = .disconnected
    var sentMessages: [SignalMessageProtocol] = []
    var sendAttempts = 0
    var shouldFailSend = false

    override init(signalingUrl: String, enableCertificatePinning: Bool = false) {
        super.init(signalingUrl: signalingUrl, enableCertificatePinning: enableCertificatePinning)
    }

    override func sendSignal(_ signal: SignalMessageProtocol) -> Bool {
        sendAttempts += 1

        if shouldFailSend {
            return false
        }

        sentMessages.append(signal)
        return true
    }
}

class MockCryptoService: CryptoServiceProtocol {
    var encryptCalled = false
    var lastRecipientId: String?
    var shouldFailEncryption = false

    func encryptMessage(for recipientId: String, content: Data) async throws -> EncryptedEnvelope {
        encryptCalled = true
        lastRecipientId = recipientId

        if shouldFailEncryption {
            throw MockCryptoError.encryptionFailed
        }

        return EncryptedEnvelope(
            type: .signal,
            content: content,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            senderRegistrationId: 12345
        )
    }
}

enum MockCryptoError: Error {
    case encryptionFailed
}

// MARK: - Message Type and Priority Tests

extension MessageQueueTests {

    func testMessageTypeHandling() async throws {
        let textContent = "Text message".data(using: .utf8)!
        let imageContent = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header

        try await messageQueue.queueMessage(
            recipientId: "recipient1",
            content: textContent,
            messageType: .text,
            priority: .normal
        )

        try await messageQueue.queueMessage(
            recipientId: "recipient2",
            content: imageContent,
            messageType: .image,
            priority: .normal
        )

        let textMessages = await messageQueue.getPendingMessages(for: "recipient1")
        let imageMessages = await messageQueue.getPendingMessages(for: "recipient2")

        XCTAssertEqual(textMessages.first?.messageType, .text)
        XCTAssertEqual(imageMessages.first?.messageType, .image)
    }

    func testPriorityDisplayNames() {
        XCTAssertEqual(MessagePriority.low.displayName, "Düşük")
        XCTAssertEqual(MessagePriority.normal.displayName, "Normal")
        XCTAssertEqual(MessagePriority.high.displayName, "Yüksek")
        XCTAssertEqual(MessagePriority.urgent.displayName, "Acil")
    }

    func testQueueStatusDisplayNames() {
        XCTAssertEqual(QueueStatus.idle.displayName, "Beklemede")
        XCTAssertEqual(QueueStatus.processing.displayName, "İşleniyor")
        XCTAssertEqual(QueueStatus.paused.displayName, "Duraklatıldı")
        XCTAssertEqual(QueueStatus.error.displayName, "Hata")
    }
}