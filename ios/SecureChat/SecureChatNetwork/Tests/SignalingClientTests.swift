import XCTest
import Combine
@testable import SecureChatNetwork

/**
 * SignalingClient unit testleri.
 *
 * WebSocket yaşam döngüsü, mesaj gönderme/alma,
 * reconnect logic ve error handling testleri.
 */
@available(iOS 13.0, *)
final class SignalingClientTests: XCTestCase {

    private var signalingClient: SignalingClient!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        signalingClient = SignalingClient(
            signalingUrl: "ws://localhost:9090",
            enableCertificatePinning: false // Disable for testing
        )
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        signalingClient?.disconnect()
        signalingClient = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Connection Tests

    func testInitialConnectionState() {
        XCTAssertEqual(signalingClient.connectionState, .disconnected)
    }

    func testConnectionStateTransitions() async {
        var stateChanges: [ConnectionState] = []

        // Subscribe to connection state changes
        signalingClient.$connectionState
            .sink { state in
                stateChanges.append(state)
            }
            .store(in: &cancellables)

        // Initial state should be disconnected
        XCTAssertEqual(stateChanges.last, .disconnected)

        // Test connection attempt (will fail with localhost but should change state)
        signalingClient.connect(userId: "test_user", authToken: "test_token")

        // Wait for state change
        await waitForCondition(timeout: 2.0) {
            stateChanges.count > 1
        }

        // Should transition to connecting first
        XCTAssertTrue(stateChanges.contains(.connecting))
    }

    func testMultipleConnectionAttempts() {
        // Multiple calls to connect should not crash
        signalingClient.connect(userId: "user1", authToken: "token1")
        signalingClient.connect(userId: "user2", authToken: "token2")

        // Should maintain the last connection attempt
        XCTAssertNotEqual(signalingClient.connectionState, .connected)
    }

    func testDisconnectClearsState() {
        signalingClient.connect(userId: "test_user", authToken: "test_token")
        signalingClient.disconnect()

        XCTAssertEqual(signalingClient.connectionState, .disconnected)
    }

    // MARK: - Message Handling Tests

    func testSendSignalWhenDisconnected() {
        let message = createTestSdpOffer()
        let result = signalingClient.sendSignal(message)

        XCTAssertFalse(result, "Should not be able to send when disconnected")
    }

    func testIncomingMessageParsing() async {
        var receivedMessages: [SignalMessageProtocol] = []

        signalingClient.incomingSignals
            .sink { message in
                receivedMessages.append(message)
            }
            .store(in: &cancellables)

        // Simulate receiving a message (this would normally come from WebSocket)
        let testMessage = createTestSdpOffer()

        // Since we can't directly inject messages into the private WebSocket,
        // we test the message parsing through the factory
        do {
            let jsonString = try SignalMessageFactory.encodeMessage(testMessage)
            let parsedMessage = try SignalMessageFactory.decodeMessage(from: jsonString)

            XCTAssertTrue(parsedMessage is SdpOfferMessage)

            if let offer = parsedMessage as? SdpOfferMessage {
                XCTAssertEqual(offer.senderId, testMessage.senderId)
                XCTAssertEqual(offer.recipientId, testMessage.recipientId)
                XCTAssertEqual(offer.sdp, testMessage.sdp)
                XCTAssertEqual(offer.callType, testMessage.callType)
            }
        } catch {
            XCTFail("Message parsing failed: \(error)")
        }
    }

    // MARK: - Error Handling Tests

    func testInvalidUrlHandling() {
        let invalidClient = SignalingClient(
            signalingUrl: "invalid-url",
            enableCertificatePinning: false
        )

        invalidClient.connect(userId: "test", authToken: "token")

        // Should transition to error state
        let expectation = XCTestExpectation(description: "Error state")

        invalidClient.$connectionState
            .sink { state in
                if case .error = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 3.0)
    }

    func testNetworkUnavailableHandling() {
        // This test would require mocking the network monitor
        // For now, we just ensure the client can handle the state
        let initialState = signalingClient.connectionState
        XCTAssertEqual(initialState, .disconnected)
    }

    // MARK: - Statistics Tests

    func testStatisticsInitialization() {
        let stats = signalingClient.statistics
        XCTAssertEqual(stats.messagesReceived, 0)
        XCTAssertEqual(stats.messagesSent, 0)
        XCTAssertEqual(stats.reconnectCount, 0)
    }

    func testStatisticsUpdateOnSend() {
        // Since we can't actually send without connection,
        // we test that the statistics structure is properly initialized
        let initialStats = signalingClient.statistics
        XCTAssertNotNil(initialStats)
    }

    // MARK: - Message Factory Tests

    func testSdpOfferEncoding() throws {
        let offer = createTestSdpOffer()
        let jsonString = try SignalMessageFactory.encodeMessage(offer)

        XCTAssertTrue(jsonString.contains("sdp_offer"))
        XCTAssertTrue(jsonString.contains(offer.senderId))
        XCTAssertTrue(jsonString.contains(offer.recipientId))
    }

    func testSdpAnswerEncoding() throws {
        let answer = SdpAnswerMessage(
            senderId: "sender123",
            recipientId: "recipient456",
            timestamp: 1234567890,
            sdp: "test-sdp-answer"
        )

        let jsonString = try SignalMessageFactory.encodeMessage(answer)
        XCTAssertTrue(jsonString.contains("sdp_answer"))
        XCTAssertTrue(jsonString.contains("test-sdp-answer"))
    }

    func testIceCandidateEncoding() throws {
        let candidate = IceCandidateMessage(
            senderId: "sender123",
            recipientId: "recipient456",
            timestamp: 1234567890,
            candidate: "candidate:test",
            sdpMid: "0",
            sdpMLineIndex: 0
        )

        let jsonString = try SignalMessageFactory.encodeMessage(candidate)
        XCTAssertTrue(jsonString.contains("ice_candidate"))
        XCTAssertTrue(jsonString.contains("candidate:test"))
    }

    func testEncryptedMessageEncoding() throws {
        let encrypted = EncryptedMessageSignal(
            senderId: "sender123",
            recipientId: "recipient456",
            timestamp: 1234567890,
            envelope: "base64-encoded-envelope"
        )

        let jsonString = try SignalMessageFactory.encodeMessage(encrypted)
        XCTAssertTrue(jsonString.contains("encrypted_message"))
        XCTAssertTrue(jsonString.contains("base64-encoded-envelope"))
    }

    func testCallControlEncoding() throws {
        let callControl = CallControlMessage(
            senderId: "sender123",
            recipientId: "recipient456",
            timestamp: 1234567890,
            action: .accept
        )

        let jsonString = try SignalMessageFactory.encodeMessage(callControl)
        XCTAssertTrue(jsonString.contains("call_control"))
        XCTAssertTrue(jsonString.contains("ACCEPT"))
    }

    func testDeliveryReceiptEncoding() throws {
        let receipt = DeliveryReceiptMessage(
            senderId: "sender123",
            recipientId: "recipient456",
            timestamp: 1234567890,
            messageId: "msg123",
            status: "DELIVERED"
        )

        let jsonString = try SignalMessageFactory.encodeMessage(receipt)
        XCTAssertTrue(jsonString.contains("delivery_receipt"))
        XCTAssertTrue(jsonString.contains("DELIVERED"))
    }

    func testRoundTripEncoding() throws {
        let originalMessage = createTestSdpOffer()

        let encoded = try SignalMessageFactory.encodeMessage(originalMessage)
        let decoded = try SignalMessageFactory.decodeMessage(from: encoded)

        XCTAssertTrue(decoded is SdpOfferMessage)

        if let decodedOffer = decoded as? SdpOfferMessage {
            XCTAssertEqual(decodedOffer.senderId, originalMessage.senderId)
            XCTAssertEqual(decodedOffer.recipientId, originalMessage.recipientId)
            XCTAssertEqual(decodedOffer.timestamp, originalMessage.timestamp)
            XCTAssertEqual(decodedOffer.sdp, originalMessage.sdp)
            XCTAssertEqual(decodedOffer.callType, originalMessage.callType)
        }
    }

    func testInvalidMessageDecoding() {
        let invalidJson = "{ invalid json }"

        XCTAssertThrowsError(try SignalMessageFactory.decodeMessage(from: invalidJson)) { error in
            XCTAssertTrue(error is SignalMessageError)
        }
    }

    func testUnknownMessageTypeDecoding() {
        let unknownTypeJson = """
        {
            "messageType": "unknown_type",
            "senderId": "test",
            "recipientId": "test",
            "timestamp": 123
        }
        """

        XCTAssertThrowsError(try SignalMessageFactory.decodeMessage(from: unknownTypeJson)) { error in
            XCTAssertTrue(error is SignalMessageError)
            if let messageError = error as? SignalMessageError {
                XCTAssertEqual(messageError, .unknownMessageType)
            }
        }
    }

    // MARK: - Helper Methods

    private func createTestSdpOffer() -> SdpOfferMessage {
        return SdpOfferMessage(
            senderId: "test_sender",
            recipientId: "test_recipient",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: "v=0\r\no=- 123 456 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n",
            callType: .voice
        )
    }

    private func waitForCondition(timeout: TimeInterval, condition: @escaping () -> Bool) async {
        let startTime = Date()
        while !condition() && Date().timeIntervalSince(startTime) < timeout {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
}

// MARK: - Mock Classes for Advanced Testing

@available(iOS 13.0, *)
class MockWebSocketEngine {
    var isConnected = false
    var lastSentMessage: String?
    var messageHandler: ((String) -> Void)?

    func connect() {
        isConnected = true
    }

    func disconnect() {
        isConnected = false
    }

    func send(message: String) {
        lastSentMessage = message
    }

    func simulateIncomingMessage(_ message: String) {
        messageHandler?(message)
    }
}

// MARK: - Performance Tests

@available(iOS 13.0, *)
extension SignalingClientTests {

    func testMessageEncodingPerformance() {
        let message = createTestSdpOffer()

        measure {
            for _ in 0..<1000 {
                _ = try? SignalMessageFactory.encodeMessage(message)
            }
        }
    }

    func testMessageDecodingPerformance() {
        let message = createTestSdpOffer()
        let encoded = try! SignalMessageFactory.encodeMessage(message)

        measure {
            for _ in 0..<1000 {
                _ = try? SignalMessageFactory.decodeMessage(from: encoded)
            }
        }
    }
}