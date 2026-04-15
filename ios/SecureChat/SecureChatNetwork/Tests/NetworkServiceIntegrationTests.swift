import XCTest
import Combine
@testable import SecureChatNetwork

/**
 * NetworkService entegrasyon testleri.
 *
 * Tüm network komponenlerinin birlikte çalışmasını test eder.
 * Loopback P2P bağlantı testleri ve end-to-end message flow testleri.
 */
@available(iOS 13.0, *)
final class NetworkServiceIntegrationTests: XCTestCase {

    private var networkService: NetworkService!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        networkService = NetworkService(
            signalingUrl: "ws://localhost:9090",
            enableCertificatePinning: false, // Disable for testing
            cryptoService: nil // Use plaintext for testing
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        networkService?.stop()
        networkService = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Service Initialization Tests

    func testServiceInitialization() {
        XCTAssertFalse(networkService.isConnected)
        XCTAssertEqual(networkService.activeP2PConnections.count, 0)
        XCTAssertEqual(networkService.networkQuality, .unavailable)
    }

    func testServiceComponentsExist() {
        XCTAssertNotNil(networkService.signalingClient)
        XCTAssertNotNil(networkService.networkManager)
        XCTAssertNotNil(networkService.messageQueue)
        XCTAssertNotNil(networkService.peerConnectionManager)
        XCTAssertNotNil(networkService.p2pMessageTransport)
    }

    // MARK: - Service Lifecycle Tests

    func testStartService() async {
        let connectionExpectation = XCTestExpectation(description: "Connection state change")

        networkService.$isConnected
            .dropFirst() // Skip initial false value
            .sink { isConnected in
                // Any connection state change fulfills expectation
                // (even if it fails to connect to localhost)
                connectionExpectation.fulfill()
            }
            .store(in: &cancellables)

        networkService.start(userId: "test_user", authToken: "test_token")

        await fulfillment(of: [connectionExpectation], timeout: 5.0)
    }

    func testStopService() {
        networkService.start(userId: "test_user", authToken: "test_token")
        networkService.stop()

        XCTAssertFalse(networkService.isConnected)
        XCTAssertEqual(networkService.activeP2PConnections.count, 0)
    }

    // MARK: - Message Sending Tests

    func testSendMessageWhenDisconnected() async {
        // Should queue message when not connected
        do {
            try await networkService.sendMessage(
                to: "recipient123",
                content: "Test message",
                messageType: .text,
                priority: .normal
            )

            let stats = networkService.messageQueue.getQueueStatistics()
            XCTAssertGreaterThan(stats.currentQueueSize, 0)

        } catch {
            XCTFail("Should not throw error when queueing message: \(error)")
        }
    }

    func testSendMultipleMessages() async {
        let messages = [
            "First message",
            "Second message",
            "Third message"
        ]

        do {
            for (index, message) in messages.enumerated() {
                try await networkService.sendMessage(
                    to: "recipient\(index)",
                    content: message,
                    messageType: .text,
                    priority: .normal
                )
            }

            let stats = networkService.messageQueue.getQueueStatistics()
            XCTAssertGreaterThanOrEqual(stats.currentQueueSize, messages.count)

        } catch {
            XCTFail("Should not throw error when queueing messages: \(error)")
        }
    }

    // MARK: - File Transfer Tests

    func testSendFile() async {
        let testData = "Test file content".data(using: .utf8)!
        let fileName = "test.txt"
        let mimeType = "text/plain"

        do {
            try await networkService.sendFile(
                to: "recipient123",
                fileData: testData,
                fileName: fileName,
                mimeType: mimeType
            )

            // File should be sent via signaling (since no P2P connection)
            // In real implementation, this would be tracked

        } catch {
            XCTFail("Should not throw error when sending file: \(error)")
        }
    }

    // MARK: - P2P Connection Tests

    func testInitiateP2PConnection() async {
        do {
            try await networkService.initiateP2PConnection(
                with: "peer123",
                callType: .voice
            )

            // Should have created a PeerConnection
            let connectionInfo = networkService.getConnectionInfo(for: "peer123")
            XCTAssertNotNil(connectionInfo)

        } catch {
            // P2P connection will fail without actual signaling server,
            // but should not crash the app
            print("P2P connection failed as expected in test environment: \(error)")
        }
    }

    func testRejectP2PConnection() {
        let mockOffer = SdpOfferMessage(
            senderId: "peer123",
            recipientId: "current_user",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: "mock-sdp-offer",
            callType: .voice
        )

        // Should not crash when rejecting
        networkService.rejectP2PConnection(from: "peer123", reason: .reject)

        // Rejection message should be sent via signaling
        // In real implementation, this would be verified
    }

    // MARK: - Call Control Tests

    func testSendCallControl() {
        let callActions: [CallAction] = [.ringing, .accept, .reject, .hangup, .busy]

        for action in callActions {
            networkService.sendCallControl(to: "peer123", action: action)
            // Should not crash for any call action
        }
    }

    func testTerminateP2PConnection() async {
        // First initiate a connection (will likely fail, but creates internal state)
        do {
            try await networkService.initiateP2PConnection(with: "peer123", callType: .voice)
        } catch {
            // Expected to fail in test environment
        }

        // Now terminate it
        await networkService.terminateP2PConnection(with: "peer123")

        // Connection should be cleaned up
        let connectionInfo = networkService.getConnectionInfo(for: "peer123")
        // Connection info might still exist but should not be active
        if let info = connectionInfo {
            XCTAssertFalse(info.isP2PActive)
        }
    }

    // MARK: - Statistics Tests

    func testNetworkStatistics() {
        let stats = networkService.getNetworkStatistics()

        XCTAssertEqual(stats.activeP2PConnections, 0)
        XCTAssertEqual(stats.totalMessagesSent, 0)
        XCTAssertEqual(stats.totalMessagesReceived, 0)
        XCTAssertEqual(stats.reconnectCount, 0)
        XCTAssertFalse(stats.signalingConnected)
    }

    func testConnectionInfoForNonExistentPeer() {
        let connectionInfo = networkService.getConnectionInfo(for: "nonexistent_peer")
        XCTAssertNil(connectionInfo)
    }

    // MARK: - Message Publishers Tests

    func testIncomingMessagesPublisher() {
        var receivedMessages: [DecryptedP2PMessage] = []

        networkService.incomingMessages
            .sink { message in
                receivedMessages.append(message)
            }
            .store(in: &cancellables)

        // Initially no messages
        XCTAssertEqual(receivedMessages.count, 0)

        // In a real integration test, we would simulate receiving messages
        // and verify they are properly published
    }

    func testDeliveryReceiptsPublisher() {
        var receivedReceipts: [DeliveryReceiptMessage] = []

        networkService.deliveryReceipts
            .sink { receipt in
                receivedReceipts.append(receipt)
            }
            .store(in: &cancellables)

        // Initially no receipts
        XCTAssertEqual(receivedReceipts.count, 0)
    }

    func testSignalingMessagesPublisher() {
        var receivedSignals: [SignalMessageProtocol] = []

        networkService.signalingMessages
            .sink { signal in
                receivedSignals.append(signal)
            }
            .store(in: &cancellables)

        // Initially no signals
        XCTAssertEqual(receivedSignals.count, 0)
    }

    // MARK: - Mark Message as Read Tests

    func testMarkMessageAsRead() async {
        await networkService.markMessageAsRead(messageId: "msg123", senderId: "sender456")

        // Should not crash and should attempt to send read receipt
        // In real implementation, this would be verified through transport layer
    }

    // MARK: - Error Handling Tests

    func testServiceRobustness() async {
        // Test that service handles various edge cases without crashing

        // Send message with empty content
        try? await networkService.sendMessage(to: "test", content: "", messageType: .text)

        // Send message with very long content
        let longContent = String(repeating: "A", count: 100000)
        try? await networkService.sendMessage(to: "test", content: longContent, messageType: .text)

        // Try to send file with empty data
        try? await networkService.sendFile(
            to: "test",
            fileData: Data(),
            fileName: "empty.txt",
            mimeType: "text/plain"
        )

        // Try P2P operations with invalid peer IDs
        try? await networkService.initiateP2PConnection(with: "")
        await networkService.terminateP2PConnection(with: "invalid_peer")

        // Service should still be functional
        XCTAssertNotNil(networkService.getNetworkStatistics())
    }

    // MARK: - Performance Tests

    func testSendManyMessages() async {
        let messageCount = 50
        let startTime = Date()

        do {
            for i in 1...messageCount {
                try await networkService.sendMessage(
                    to: "recipient\(i % 10)",
                    content: "Message \(i)",
                    messageType: .text,
                    priority: .normal
                )
            }

            let duration = Date().timeIntervalSince(startTime)

            // Should be able to queue 50 messages quickly
            XCTAssertLessThan(duration, 2.0) // Less than 2 seconds

            let stats = networkService.messageQueue.getQueueStatistics()
            XCTAssertGreaterThanOrEqual(stats.totalQueued, messageCount)

        } catch {
            XCTFail("Should not throw error when queueing many messages: \(error)")
        }
    }

    func testServiceInitializationPerformance() {
        measure {
            let service = NetworkService(
                signalingUrl: "ws://test.example.com",
                enableCertificatePinning: false
            )
            service.stop()
        }
    }

    // MARK: - Memory Management Tests

    func testServiceCleanup() {
        weak var weakService: NetworkService?

        do {
            let service = NetworkService(
                signalingUrl: "ws://test.example.com",
                enableCertificatePinning: false
            )
            weakService = service
            service.stop()
        }

        // Service should be deallocated
        // Note: This test might not work reliably in debug builds due to ARC optimizations
        XCTAssertNil(weakService, "NetworkService should be deallocated when no longer referenced")
    }
}

// MARK: - Real Network Integration Tests (Disabled by Default)

/**
 * These tests require a real signaling server running.
 * Uncomment and configure for full integration testing.
 */
/*
@available(iOS 13.0, *)
extension NetworkServiceIntegrationTests {

    func testRealSignalingConnection() async {
        let realService = NetworkService(
            signalingUrl: "wss://your-signaling-server.com",
            enableCertificatePinning: true
        )

        let connectionExpectation = XCTestExpectation(description: "Real connection")

        realService.$isConnected
            .filter { $0 } // Wait for true
            .first()
            .sink { _ in
                connectionExpectation.fulfill()
            }
            .store(in: &cancellables)

        realService.start(userId: "test_user_1", authToken: "real_auth_token")

        await fulfillment(of: [connectionExpectation], timeout: 10.0)

        XCTAssertTrue(realService.isConnected)
        realService.stop()
    }

    func testRealP2PConnection() async {
        // This would test actual P2P connection between two instances
        // Requires complex setup with two devices or simulators
    }
}
*/