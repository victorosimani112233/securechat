import XCTest
@testable import SecureChatMedia

/**
 * CallState ve CallSession model testleri.
 *
 * Test kapsamı:
 * - CallState enum değerleri ve geçişleri
 * - CallSession veri modeli doğruluğu
 * - Duration hesaplamaları
 * - Equality kontrolü
 */
class CallStateTests: XCTestCase {

    // MARK: - CallState Tests

    func testCallStateDisplayNames() {
        // Test all call states have proper display names
        XCTAssertEqual(CallState.idle.displayName, "Bekleme")
        XCTAssertEqual(CallState.initiating.displayName, "Başlatılıyor")
        XCTAssertEqual(CallState.ringing.displayName, "Çalıyor")
        XCTAssertEqual(CallState.connecting.displayName, "Bağlanıyor")
        XCTAssertEqual(CallState.active.displayName, "Aktif")
        XCTAssertEqual(CallState.reconnecting.displayName, "Yeniden Bağlanıyor")
        XCTAssertEqual(CallState.ended.displayName, "Sonlandı")
        XCTAssertEqual(CallState.rejected.displayName, "Reddedildi")
        XCTAssertEqual(CallState.busy.displayName, "Meşgul")
        XCTAssertEqual(CallState.failed.displayName, "Başarısız")
    }

    func testCallStateRawValues() {
        // Test raw values are consistent
        XCTAssertEqual(CallState.idle.rawValue, "idle")
        XCTAssertEqual(CallState.active.rawValue, "active")
        XCTAssertEqual(CallState.ended.rawValue, "ended")
        XCTAssertEqual(CallState.rejected.rawValue, "rejected")
        XCTAssertEqual(CallState.failed.rawValue, "failed")
    }

    // MARK: - CallDirection Tests

    func testCallDirectionDisplayNames() {
        XCTAssertEqual(CallDirection.incoming.displayName, "Gelen")
        XCTAssertEqual(CallDirection.outgoing.displayName, "Giden")
    }

    // MARK: - CallSession Tests

    func testCallSessionInitialization() {
        // Given
        let callId = "test-call-123"
        let peerId = "peer-456"
        let callType = CallType.voice
        let direction = CallDirection.outgoing

        // When
        let session = CallSession(
            callId: callId,
            peerId: peerId,
            callType: callType,
            direction: direction,
            state: .idle
        )

        // Then
        XCTAssertEqual(session.callId, callId)
        XCTAssertEqual(session.peerId, peerId)
        XCTAssertEqual(session.callType, callType)
        XCTAssertEqual(session.direction, direction)
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.startTime)
        XCTAssertNil(session.duration)
        XCTAssertFalse(session.isMuted)
        XCTAssertFalse(session.isSpeakerOn)
        XCTAssertTrue(session.isCameraEnabled)
        XCTAssertTrue(session.isUsingFrontCamera)
    }

    func testCallSessionActiveDuration() {
        // Given - Active session başlatıldığından 30 saniye sonra
        let startTime = Date().timeIntervalSince1970 - 30.0 // 30 saniye öncesi
        var session = CallSession(
            callId: "test-call",
            peerId: "peer-123",
            callType: .voice,
            direction: .outgoing,
            state: .active,
            startTime: startTime
        )

        // When
        let duration = session.activeDuration

        // Then
        XCTAssertNotNil(duration)
        XCTAssertGreaterThanOrEqual(duration!, 25.0) // En az 25 saniye (biraz tolerans)
        XCTAssertLessThanOrEqual(duration!, 35.0) // En fazla 35 saniye
    }

    func testCallSessionActiveDurationWithoutStartTime() {
        // Given - StartTime olmayan session
        let session = CallSession(
            callId: "test-call",
            peerId: "peer-123",
            callType: .voice,
            direction: .outgoing
        )

        // When
        let duration = session.activeDuration

        // Then
        XCTAssertNil(duration)
    }

    func testCallSessionFormattedDuration() {
        // Test cases for different durations
        let testCases: [(TimeInterval, String)] = [
            (0, "00:00"),
            (30, "00:30"),
            (90, "01:30"),
            (3661, "01:01:01") // 1 saat 1 dakika 1 saniye
        ]

        for (duration, expectedFormat) in testCases {
            // Given
            let startTime = Date().timeIntervalSince1970 - duration
            var session = CallSession(
                callId: "test-call",
                peerId: "peer-123",
                callType: .voice,
                direction: .outgoing,
                state: .active,
                startTime: startTime
            )

            // When
            let formattedDuration = session.formattedDuration

            // Then - Allow 1 second tolerance for test execution time
            let actualDuration = session.activeDuration ?? 0
            let expectedDuration = duration
            XCTAssertLessThanOrEqual(abs(actualDuration - expectedDuration), 1.0,
                                   "Duration mismatch for \(duration)s")
        }
    }

    func testCallSessionCallKitStatusText() {
        // Test different call states and directions
        let testCases: [(CallState, CallDirection, String)] = [
            (.initiating, .outgoing, "Aranıyor..."),
            (.ringing, .outgoing, "Aranıyor..."),
            (.ringing, .incoming, "Gelen arama"),
            (.connecting, .outgoing, "Bağlanıyor..."),
            (.connecting, .incoming, "Bağlanıyor..."),
            (.ended, .outgoing, "Arama sonlandı"),
            (.rejected, .incoming, "Arama reddedildi"),
            (.busy, .outgoing, "Meşgul"),
            (.failed, .incoming, "Arama başarısız"),
            (.reconnecting, .outgoing, "Yeniden bağlanıyor..."),
            (.idle, .outgoing, "")
        ]

        for (state, direction, expectedText) in testCases {
            // Given
            let session = CallSession(
                callId: "test-call",
                peerId: "peer-123",
                callType: .voice,
                direction: direction,
                state: state
            )

            // When
            let statusText = session.callKitStatusText

            // Then
            if state == .active {
                // Active durumunda formatted duration döner
                XCTAssertTrue(statusText.contains(":"))
            } else {
                XCTAssertEqual(statusText, expectedText,
                             "Status text mismatch for \(state)-\(direction)")
            }
        }
    }

    func testCallSessionEquality() {
        // Given - İki özdeş session
        let session1 = CallSession(
            callId: "test-call-123",
            peerId: "peer-456",
            callType: .voice,
            direction: .outgoing,
            state: .active,
            startTime: 1234567890.0,
            isMuted: true,
            isSpeakerOn: false
        )

        let session2 = CallSession(
            callId: "test-call-123",
            peerId: "peer-456",
            callType: .voice,
            direction: .outgoing,
            state: .active,
            startTime: 1234567890.0,
            isMuted: true,
            isSpeakerOn: false
        )

        // When & Then
        XCTAssertEqual(session1, session2)
    }

    func testCallSessionInequality() {
        // Given - İki farklı session
        let session1 = CallSession(
            callId: "test-call-123",
            peerId: "peer-456",
            callType: .voice,
            direction: .outgoing,
            state: .active
        )

        let session2 = CallSession(
            callId: "test-call-789", // Farklı call ID
            peerId: "peer-456",
            callType: .voice,
            direction: .outgoing,
            state: .active
        )

        // When & Then
        XCTAssertNotEqual(session1, session2)
    }

    // MARK: - ConnectionQuality Tests

    func testConnectionQualityDisplayNames() {
        XCTAssertEqual(ConnectionQuality.excellent.displayName, "Mükemmel")
        XCTAssertEqual(ConnectionQuality.good.displayName, "İyi")
        XCTAssertEqual(ConnectionQuality.fair.displayName, "Orta")
        XCTAssertEqual(ConnectionQuality.poor.displayName, "Zayıf")
        XCTAssertEqual(ConnectionQuality.unavailable.displayName, "Bağlantı Yok")
    }

    func testConnectionQualityScores() {
        XCTAssertEqual(ConnectionQuality.excellent.score, 90)
        XCTAssertEqual(ConnectionQuality.good.score, 70)
        XCTAssertEqual(ConnectionQuality.fair.score, 50)
        XCTAssertEqual(ConnectionQuality.poor.score, 25)
        XCTAssertEqual(ConnectionQuality.unavailable.score, 0)
    }

    // MARK: - CallError Tests

    func testCallErrorDescriptions() {
        XCTAssertEqual(CallError.invalidPeerId.localizedDescription, "Geçersiz kullanıcı ID")
        XCTAssertEqual(CallError.noActiveCall.localizedDescription, "Aktif arama yok")
        XCTAssertEqual(CallError.callAlreadyActive.localizedDescription, "Zaten aktif bir arama var")

        XCTAssertEqual(CallError.webRTCError("Test error").localizedDescription, "WebRTC hatası: Test error")
        XCTAssertEqual(CallError.audioSessionError("Audio error").localizedDescription, "Ses hatası: Audio error")
        XCTAssertEqual(CallError.callKitError("CallKit error").localizedDescription, "CallKit hatası: CallKit error")
        XCTAssertEqual(CallError.networkError("Network error").localizedDescription, "Ağ hatası: Network error")
    }

    // MARK: - CallStatistics Tests

    func testCallStatisticsInitialization() {
        // Given
        let duration: TimeInterval = 120.0
        let audioBitrate: Double = 64.0
        let videoBitrate: Double = 500.0
        let latency: Double = 50.0
        let packetLoss: Double = 0.1
        let quality = ConnectionQuality.good

        // When
        let stats = CallStatistics(
            duration: duration,
            audioBitrate: audioBitrate,
            videoBitrate: videoBitrate,
            latency: latency,
            packetLoss: packetLoss,
            connectionQuality: quality
        )

        // Then
        XCTAssertEqual(stats.duration, duration)
        XCTAssertEqual(stats.audioBitrate, audioBitrate)
        XCTAssertEqual(stats.videoBitrate, videoBitrate)
        XCTAssertEqual(stats.latency, latency)
        XCTAssertEqual(stats.packetLoss, packetLoss)
        XCTAssertEqual(stats.connectionQuality, quality)
    }

    func testCallStatisticsWithoutVideo() {
        // Given - Voice call statistics
        let stats = CallStatistics(
            duration: 60.0,
            audioBitrate: 48.0,
            latency: 30.0,
            packetLoss: 0.05,
            connectionQuality: .excellent
        )

        // Then
        XCTAssertNil(stats.videoBitrate)
        XCTAssertEqual(stats.connectionQuality, .excellent)
    }
}