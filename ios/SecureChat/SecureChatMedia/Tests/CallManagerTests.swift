import XCTest
import Combine
import CallKit
import WebRTC
@testable import SecureChatMedia
@testable import SecureChatNetwork
@testable import SecureChatCommon

/**
 * CallManager unit testleri.
 *
 * Test kapsamı:
 * - Arama yaşam döngüsü geçişleri
 * - Gelen/giden arama handling
 * - Media kontrolleri (mute, speaker, camera)
 * - WebRTC entegrasyonu
 * - CallKit entegrasyonu
 * - Error handling
 */
@MainActor
class CallManagerTests: XCTestCase {

    private var callManager: CallManager!
    private var mockNetworkService: MockNetworkService!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        mockNetworkService = MockNetworkService()
        callManager = CallManager(networkService: mockNetworkService)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        await callManager.endCall()
        callManager = nil
        mockNetworkService = nil

        try await super.tearDown()
    }

    // MARK: - Giden Arama Testleri

    func testInitiateVoiceCall() async throws {
        // Given
        let peerId = "test-peer-123"
        let userId = "test-user-456"
        let expectation = XCTestExpectation(description: "Arama başlatıldı")

        // When
        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // Then
        XCTAssertNotNil(callManager.currentSession)
        XCTAssertEqual(callManager.currentSession?.peerId, peerId)
        XCTAssertEqual(callManager.currentSession?.callType, .voice)
        XCTAssertEqual(callManager.currentSession?.direction, .outgoing)
        XCTAssertEqual(callManager.callState, .ringing)

        // SDP Offer gönderildi mi kontrol et
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(mockNetworkService.sentSignals.contains { signal in
            signal.messageType == "sdp_offer"
        })
    }

    func testInitiateVideoCall() async throws {
        // Given
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        // When
        try await callManager.initiateCall(to: peerId, callType: .video, userId: userId)

        // Then
        XCTAssertNotNil(callManager.currentSession)
        XCTAssertEqual(callManager.currentSession?.callType, .video)
        XCTAssertEqual(callManager.currentSession?.isCameraEnabled, true)
        XCTAssertEqual(callManager.callState, .ringing)
    }

    func testInitiateCallWithActiveCall() async throws {
        // Given - Önceki arama
        let firstPeerId = "first-peer-123"
        let secondPeerId = "second-peer-456"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: firstPeerId, callType: .voice, userId: userId)

        // When & Then - İkinci arama başlatılınca hata almalıyız
        do {
            try await callManager.initiateCall(to: secondPeerId, callType: .voice, userId: userId)
            XCTFail("Aktif arama varken yeni arama başlatılabildi")
        } catch CallError.callAlreadyActive {
            // Beklenen hata
        } catch {
            XCTFail("Beklenmeyen hata: \(error)")
        }
    }

    // MARK: - Gelen Arama Testleri

    func testHandleIncomingVoiceCall() async {
        // Given
        let peerId = "caller-123"
        let userId = "receiver-456"
        let sdpOffer = SdpOfferMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: "mock-sdp-offer",
            callType: .voice
        )

        // When
        await callManager.handleIncomingCall(sdpOffer, currentUserId: userId)

        // Then
        XCTAssertNotNil(callManager.currentSession)
        XCTAssertEqual(callManager.currentSession?.peerId, peerId)
        XCTAssertEqual(callManager.currentSession?.callType, .voice)
        XCTAssertEqual(callManager.currentSession?.direction, .incoming)
        XCTAssertEqual(callManager.callState, .ringing)
    }

    func testAcceptIncomingCall() async throws {
        // Given - Gelen arama
        let peerId = "caller-123"
        let userId = "receiver-456"
        let sdpOffer = SdpOfferMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: "mock-sdp-offer",
            callType: .voice
        )

        await callManager.handleIncomingCall(sdpOffer, currentUserId: userId)

        // When
        try await callManager.acceptCall()

        // Then
        XCTAssertEqual(callManager.callState, .connecting)

        // SDP Answer gönderildi mi kontrol et
        XCTAssertTrue(mockNetworkService.sentSignals.contains { signal in
            signal.messageType == "sdp_answer"
        })
    }

    func testRejectIncomingCall() async {
        // Given - Gelen arama
        let peerId = "caller-123"
        let userId = "receiver-456"
        let sdpOffer = SdpOfferMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: "mock-sdp-offer",
            callType: .voice
        )

        await callManager.handleIncomingCall(sdpOffer, currentUserId: userId)

        // When
        await callManager.rejectCall()

        // Then
        XCTAssertEqual(callManager.callState, .rejected)

        // Reject mesajı gönderildi mi kontrol et
        XCTAssertTrue(mockNetworkService.sentSignals.contains { signal in
            signal.messageType == "call_control" &&
            (signal as? CallControlMessage)?.action == .reject
        })
    }

    // MARK: - Arama Sonlandırma Testleri

    func testEndCall() async throws {
        // Given - Aktif arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // When
        await callManager.endCall()

        // Then
        XCTAssertEqual(callManager.callState, .ended)

        // Hangup mesajı gönderildi mi kontrol et
        XCTAssertTrue(mockNetworkService.sentSignals.contains { signal in
            signal.messageType == "call_control" &&
            (signal as? CallControlMessage)?.action == .hangup
        })
    }

    // MARK: - Media Kontrol Testleri

    func testToggleMute() async throws {
        // Given - Aktif arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // When - Mute'u açalım
        callManager.toggleMute()

        // Then
        XCTAssertTrue(callManager.currentSession?.isMuted ?? false)

        // When - Mute'u kapatalım
        callManager.toggleMute()

        // Then
        XCTAssertFalse(callManager.currentSession?.isMuted ?? true)
    }

    func testToggleSpeaker() async throws {
        // Given - Aktif arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // When - Speaker'ı açalım
        callManager.toggleSpeaker()

        // Then
        XCTAssertTrue(callManager.currentSession?.isSpeakerOn ?? false)

        // When - Speaker'ı kapatalım
        callManager.toggleSpeaker()

        // Then
        XCTAssertFalse(callManager.currentSession?.isSpeakerOn ?? true)
    }

    func testToggleCameraOnVideoCall() async throws {
        // Given - Video arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .video, userId: userId)

        // When - Kamerayı kapatalım
        callManager.toggleCamera()

        // Then
        XCTAssertFalse(callManager.currentSession?.isCameraEnabled ?? true)

        // When - Kamerayı açalım
        callManager.toggleCamera()

        // Then
        XCTAssertTrue(callManager.currentSession?.isCameraEnabled ?? false)
    }

    func testSwitchCamera() async throws {
        // Given - Video arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .video, userId: userId)

        let initialCameraState = callManager.currentSession?.isUsingFrontCamera ?? true

        // When
        try callManager.switchCamera()

        // Then
        XCTAssertNotEqual(callManager.currentSession?.isUsingFrontCamera, initialCameraState)
    }

    // MARK: - Arama Durumu Geçiş Testleri

    func testCallStateTransitions() async throws {
        // Given
        let peerId = "test-peer-123"
        let userId = "test-user-456"
        var stateChanges: [CallState] = []

        callManager.$callState
            .sink { state in
                stateChanges.append(state)
            }
            .store(in: &cancellables)

        // When - Giden arama başlat
        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // Then - Durum geçişlerini kontrol et
        XCTAssertTrue(stateChanges.contains(.idle))
        XCTAssertTrue(stateChanges.contains(.initiating))
        XCTAssertTrue(stateChanges.contains(.ringing))
    }

    func testGetCallDuration() async throws {
        // Given - Aktif arama simülasyonu
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        // Session'ı manually active yap (test için)
        if var session = callManager.currentSession {
            session.state = .active
            session.startTime = Date().timeIntervalSince1970 - 30 // 30 saniye öncesi
            callManager.setValue(session, forKey: "currentSession")
        }

        // When
        let duration = callManager.getCallDuration()

        // Then
        XCTAssertNotNil(duration)
        XCTAssertGreaterThan(duration!, 25.0) // En az 25 saniye
    }

    // MARK: - Signaling Message Handler Testleri

    func testHandleSdpAnswer() async throws {
        // Given - Giden arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        let sdpAnswer = SdpAnswerMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            sdp: "mock-sdp-answer"
        )

        // When
        await callManager.handleSdpAnswer(sdpAnswer)

        // Then
        XCTAssertEqual(callManager.callState, .connecting)
    }

    func testHandleCallControlReject() async throws {
        // Given - Giden arama
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        let rejectMessage = CallControlMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .reject
        )

        // When
        await callManager.handleCallControl(rejectMessage)

        // Then
        XCTAssertEqual(callManager.callState, .rejected)
    }

    func testHandleCallControlHangup() async throws {
        // Given - Aktif arama simülasyonu
        let peerId = "test-peer-123"
        let userId = "test-user-456"

        try await callManager.initiateCall(to: peerId, callType: .voice, userId: userId)

        let hangupMessage = CallControlMessage(
            senderId: peerId,
            recipientId: userId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: .hangup
        )

        // When
        await callManager.handleCallControl(hangupMessage)

        // Then
        XCTAssertEqual(callManager.callState, .ended)
    }

    // MARK: - Error Handling Testleri

    func testNoActiveCallError() async {
        // Given - Aktif arama yok

        // When & Then - Kabul etmeye çalışınca hata almalıyız
        do {
            try await callManager.acceptCall()
            XCTFail("Aktif arama olmadan kabul edildi")
        } catch CallError.noActiveCall {
            // Beklenen hata
        } catch {
            XCTFail("Beklenmeyen hata: \(error)")
        }
    }
}

// MARK: - Mock Classes

class MockNetworkService: NetworkService {
    var sentSignals: [SignalMessageProtocol] = []

    override init() {
        // Mock implementation - gerçek network bağlantısı yok
        super.init(
            signalingUrl: "ws://mock-server.test",
            enableCertificatePinning: false,
            cryptoService: nil
        )
    }

    override func sendCallControl(to peerId: String, action: CallAction) {
        let controlMessage = CallControlMessage(
            senderId: "mock-user",
            recipientId: peerId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            action: action
        )
        sentSignals.append(controlMessage)
    }
}

// XCTest extension for async testing
extension XCTestCase {
    func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval) async {
        await fulfillment(of: expectations, timeout: timeout)
    }
}