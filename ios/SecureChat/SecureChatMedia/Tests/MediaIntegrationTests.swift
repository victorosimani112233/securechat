import XCTest
import Combine
@testable import SecureChatMedia
@testable import SecureChatNetwork
@testable import SecureChatCommon

/**
 * SecureChatMedia modülünün diğer modüllerle entegrasyonu testleri.
 *
 * Test kapsamı:
 * - Network modülü ile signaling entegrasyonu
 * - Common modülü ile data model uyumluluğu
 * - Tam arama yaşam döngüsü simülasyonu
 * - Cross-platform message compatibility
 */
@MainActor
class MediaIntegrationTests: XCTestCase {

    private var callManager: CallManager!
    private var mockNetworkService: MockNetworkService!
    private var mockSignalingClient: MockSignalingClient!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        mockSignalingClient = MockSignalingClient()
        mockNetworkService = MockNetworkService(signalingClient: mockSignalingClient)
        callManager = CallManager(networkService: mockNetworkService)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        await callManager.endCall()
        callManager = nil
        mockNetworkService = nil
        mockSignalingClient = nil

        try await super.tearDown()
    }

    // MARK: - Network Integration Tests

    func testSignalingMessageCompatibility() async throws {
        // Given - Android ile uyumlu signaling mesajları
        let peerId = "android-peer-123"
        let userId = "ios-user-456"

        // When - Giden arama başlat
        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // Then - Doğru signaling mesajları gönderildi mi
        XCTAssertTrue(mockSignalingClient.sentMessages.contains { message in
            guard let offer = message as? SdpOfferMessage else { return false }
            return offer.senderId == userId &&
                   offer.recipientId == peerId &&
                   offer.callType == .voice &&
                   offer.messageType == "sdp_offer"
        })
    }

    func testIncomingCallSignalingFlow() async {
        // Given - Android'den gelen SDP Offer mesajı
        let androidPeerId = "android-caller-789"
        let iosUserId = "ios-receiver-123"

        let incomingOffer = SdpOfferMessage(
            senderId: androidPeerId,
            recipientId: iosUserId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: """
                v=0
                o=- 123456789 2 IN IP4 127.0.0.1
                s=-
                t=0 0
                a=ice-ufrag:abcd
                a=ice-pwd:1234567890123456789012
                m=audio 9 UDP/TLS/RTP/SAVPF 111 103 104
                c=IN IP4 0.0.0.0
                a=rtcp:9 IN IP4 0.0.0.0
                a=ice-ufrag:abcd
                a=ice-pwd:1234567890123456789012
                a=setup:actpass
                a=rtcp-mux
                """,
            callType: .voice
        )

        // When - Gelen aramayı işle
        await callManager.handleIncomingCall(incomingOffer, currentUserId: iosUserId)

        // Then - CallSession doğru oluşturuldu
        XCTAssertNotNil(callManager.currentSession)
        XCTAssertEqual(callManager.currentSession?.peerId, androidPeerId)
        XCTAssertEqual(callManager.currentSession?.callType, .voice)
        XCTAssertEqual(callManager.currentSession?.direction, .incoming)
        XCTAssertEqual(callManager.callState, .ringing)

        // When - Aramayı kabul et
        try await callManager.acceptCall()

        // Then - SDP Answer gönderildi
        XCTAssertTrue(mockSignalingClient.sentMessages.contains { message in
            guard let answer = message as? SdpAnswerMessage else { return false }
            return answer.senderId == iosUserId &&
                   answer.recipientId == androidPeerId &&
                   answer.messageType == "sdp_answer"
        })
    }

    func testCallControlMessageHandling() async throws {
        // Given - Aktif giden arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)
        XCTAssertEqual(callManager.callState, .ringing)

        // When - Karşı taraf kabul etti
        let acceptMessage = CallControlMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .accept
        )

        await callManager.handleCallControl(acceptMessage)

        // Then - Arama aktif duruma geçmeli (WebRTC bağlantı kurulduktan sonra)
        // Not: Gerçek WebRTC bağlantısı olmadığı için connecting'te kalacak

        // When - Karşı taraf kapat
        let hangupMessage = CallControlMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .hangup
        )

        await callManager.handleCallControl(hangupMessage)

        // Then - Arama sonlandı
        XCTAssertEqual(callManager.callState, .ended)
    }

    func testICECandidateExchange() async throws {
        // Given - Aktif arama
        let peerId = "peer-with-ice"
        let userId = "user-with-ice"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // When - ICE candidate geldi
        let iceCandidate = IceCandidateMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            candidate: "candidate:1 1 UDP 2130706431 192.168.1.100 54400 typ host",
            sdpMid: "audio",
            sdpMLineIndex: 0
        )

        // Then - Exception fırlatmamalı
        await XCTAssertNoThrowAsync {
            await callManager.handleIceCandidate(iceCandidate)
        }
    }

    // MARK: - Cross-Platform Compatibility Tests

    func testAndroidCallTypeCompatibility() {
        // Test CallType enum values match Android
        XCTAssertEqual(CallType.voice.rawValue, "VOICE")
        XCTAssertEqual(CallType.video.rawValue, "VIDEO")
    }

    func testAndroidCallActionCompatibility() {
        // Test CallAction enum values match Android
        XCTAssertEqual(CallAction.ringing.rawValue, "RINGING")
        XCTAssertEqual(CallAction.accept.rawValue, "ACCEPT")
        XCTAssertEqual(CallAction.reject.rawValue, "REJECT")
        XCTAssertEqual(CallAction.hangup.rawValue, "HANGUP")
        XCTAssertEqual(CallAction.busy.rawValue, "BUSY")
    }

    func testMessageTypeCompatibility() {
        // Test message types match Android SignalMessage
        let sdpOffer = SdpOfferMessage(
            senderId: "test",
            recipientId: "test",
            timestamp: 0,
            sdp: "test",
            callType: .voice
        )
        XCTAssertEqual(sdpOffer.messageType, "sdp_offer")

        let sdpAnswer = SdpAnswerMessage(
            senderId: "test",
            recipientId: "test",
            timestamp: 0,
            sdp: "test"
        )
        XCTAssertEqual(sdpAnswer.messageType, "sdp_answer")

        let iceCandidate = IceCandidateMessage(
            senderId: "test",
            recipientId: "test",
            timestamp: 0,
            candidate: "test",
            sdpMid: "audio",
            sdpMLineIndex: 0
        )
        XCTAssertEqual(iceCandidate.messageType, "ice_candidate")
    }

    // MARK: - Full Call Lifecycle Tests

    func testCompleteIncomingCallAcceptFlow() async throws {
        let expectation = XCTestExpectation(description: "Complete incoming call flow")
        var stateChanges: [CallState] = []

        // Track state changes
        callManager.$callState
            .sink { state in
                stateChanges.append(state)
                if state == .connecting {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Simulate incoming call from Android
        let androidPeer = "android-caller"
        let iosUser = "ios-receiver"

        let incomingOffer = SdpOfferMessage(
            senderId: androidPeer,
            recipientId: iosUser,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: "v=0\no=- 123 2 IN IP4 127.0.0.1\ns=-\nt=0 0\nm=audio 9 UDP/TLS/RTP/SAVPF 111",
            callType: .voice
        )

        // Handle incoming call
        await callManager.handleIncomingCall(incomingOffer, currentUserId: iosUser)

        // Accept the call
        try await callManager.acceptCall()

        // Wait for flow to complete
        await fulfillment(of: [expectation], timeout: 5.0)

        // Verify state progression
        XCTAssertTrue(stateChanges.contains(.idle))
        XCTAssertTrue(stateChanges.contains(.ringing))
        XCTAssertTrue(stateChanges.contains(.connecting))

        // Verify SDP Answer was sent
        XCTAssertTrue(mockSignalingClient.sentMessages.contains { message in
            message.messageType == "sdp_answer"
        })
    }

    func testCompleteOutgoingCallRejectFlow() async throws {
        let expectation = XCTestExpectation(description: "Complete outgoing call reject flow")

        // Start outgoing call
        try await callManager.initiateCall(
            to: "test-peer",
            callType: .voice,
            userId: "test-user"
        )

        // Simulate rejection from peer
        let rejectMessage = CallControlMessage(
            senderId: "test-peer",
            recipientId: "test-user",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .reject
        )

        // Track state change
        callManager.$callState
            .filter { $0 == .rejected }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Handle rejection
        await callManager.handleCallControl(rejectMessage)

        // Wait for completion
        await fulfillment(of: [expectation], timeout: 3.0)

        // Verify final state
        XCTAssertEqual(callManager.callState, .rejected)
    }

    // MARK: - Network Failure Tests

    func testNetworkFailureHandling() async throws {
        // Given - Network bağlantısı var
        try await callManager.initiateCall(
            to: "test-peer",
            callType: .voice,
            userId: "test-user"
        )

        // When - Network failure simülasyonu
        mockSignalingClient.simulateDisconnection()

        // Then - Uygulamanın crash olmaması gerekli
        // CallManager resilient olmalı
        await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Cleanup should still work
        await callManager.endCall()
        XCTAssertEqual(callManager.callState, .ended)
    }

    func testConcurrentCallAttempts() async throws {
        // Given - Birden fazla eşzamanlı arama denemesi
        let firstPeer = "peer-1"
        let secondPeer = "peer-2"
        let userId = "test-user"

        // When - İlk arama
        try await callManager.initiateCall(to: firstPeer, callType: .voice, userId: userId)

        // Then - İkinci arama başarısız olmalı
        do {
            try await callManager.initiateCall(to: secondPeer, callType: .voice, userId: userId)
            XCTFail("Concurrent call should not be allowed")
        } catch CallError.callAlreadyActive {
            // Expected error
        }

        // Verify first call is still active
        XCTAssertEqual(callManager.currentSession?.peerId, firstPeer)
    }

    // MARK: - Performance Tests

    func testCallInitiationPerformance() {
        measure {
            Task {
                do {
                    try await callManager.initiateCall(
                        to: "performance-test-peer",
                        callType: .voice,
                        userId: "performance-test-user"
                    )
                    await callManager.endCall()
                } catch {
                    XCTFail("Performance test failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Enhanced Mock Classes

class MockSignalingClient: NSObject {
    var sentMessages: [SignalMessageProtocol] = []
    var isConnected: Bool = true
    private var messageHandler: ((String) -> Void)?

    func sendSignal(_ message: SignalMessageProtocol) {
        sentMessages.append(message)
    }

    func simulateDisconnection() {
        isConnected = false
    }

    func simulateIncomingMessage(_ message: SignalMessageProtocol) {
        // Convert to JSON and simulate receiving
        do {
            let jsonString = try SignalMessageFactory.encodeMessage(message)
            messageHandler?(jsonString)
        } catch {
            print("Mock signaling error: \(error)")
        }
    }
}

class MockNetworkService: NetworkService {
    private let mockSignalingClient: MockSignalingClient

    init(signalingClient: MockSignalingClient) {
        self.mockSignalingClient = signalingClient
        super.init(
            signalingUrl: "ws://mock-test-server",
            enableCertificatePinning: false,
            cryptoService: nil
        )
    }

    override var signalingClient: SignalingClient {
        // Return mock implementation
        return mockSignalingClient as! SignalingClient
    }
}

// XCTest async helper
extension XCTestCase {
    func XCTAssertNoThrowAsync<T>(
        _ expression: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}