import XCTest
import AVFoundation
@testable import SecureChatMedia

/**
 * AudioSessionManager unit testleri.
 *
 * Test kapsamı:
 * - Audio session konfigürasyonu
 * - Audio routing (speaker, bluetooth, headphones)
 * - Audio interruption handling
 * - Proximity monitoring
 */
class AudioSessionManagerTests: XCTestCase {

    private var audioSessionManager: AudioSessionManager!

    override func setUp() {
        super.setUp()
        audioSessionManager = AudioSessionManager()
    }

    override func tearDown() {
        audioSessionManager.restoreDefaultConfiguration()
        audioSessionManager = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testConfigureForCall() throws {
        // Given
        XCTAssertFalse(audioSessionManager.isActive)

        // When
        try audioSessionManager.configureForCall()

        // Then
        XCTAssertTrue(audioSessionManager.isActive)

        // Audio session kategorisinin doğru ayarlandığını kontrol et
        let audioSession = AVAudioSession.sharedInstance()
        XCTAssertEqual(audioSession.category, .playAndRecord)
        XCTAssertEqual(audioSession.mode, .voiceChat)
    }

    func testRestoreDefaultConfiguration() throws {
        // Given - Arama için yapılandırılmış audio session
        try audioSessionManager.configureForCall()
        XCTAssertTrue(audioSessionManager.isActive)

        // When
        audioSessionManager.restoreDefaultConfiguration()

        // Then
        XCTAssertFalse(audioSessionManager.isActive)
        XCTAssertFalse(audioSessionManager.isSpeakerOn)
    }

    // MARK: - Speaker Control Tests

    func testSetSpeakerEnabled() throws {
        // Given - Arama için yapılandırılmış
        try audioSessionManager.configureForCall()

        // When - Speaker'ı açalım
        try audioSessionManager.setSpeaker(enabled: true)

        // Then
        XCTAssertTrue(audioSessionManager.isSpeakerOn)

        // When - Speaker'ı kapatalım
        try audioSessionManager.setSpeaker(enabled: false)

        // Then
        XCTAssertFalse(audioSessionManager.isSpeakerOn)
    }

    func testSetSpeakerWithoutConfiguration() {
        // Given - Yapılandırılmamış audio session
        XCTAssertFalse(audioSessionManager.isActive)

        // When & Then - Hata almalıyız
        XCTAssertThrowsError(try audioSessionManager.setSpeaker(enabled: true)) { error in
            // AVAudioSession hatası bekliyoruz
            XCTAssertTrue(error is NSError)
        }
    }

    // MARK: - Bluetooth Tests

    func testSetBluetoothEnabled() throws {
        // Given - Arama için yapılandırılmış
        try audioSessionManager.configureForCall()

        // When - Bluetooth'u etkinleştirelim
        try audioSessionManager.setBluetoothEnabled(true)

        // Then - Hata almamamız yeterli (Bluetooth device olmayabilir)
        XCTAssertNoThrow(try audioSessionManager.setBluetoothEnabled(true))

        // When - Bluetooth'u devre dışı bırakalım
        try audioSessionManager.setBluetoothEnabled(false)

        // Then
        XCTAssertNoThrow(try audioSessionManager.setBluetoothEnabled(false))
    }

    // MARK: - Audio Route Tests

    func testAudioRouteDisplayNames() {
        XCTAssertEqual(AudioRoute.receiver.displayName, "Kulaklık")
        XCTAssertEqual(AudioRoute.speaker.displayName, "Hoparlör")
        XCTAssertEqual(AudioRoute.headphones.displayName, "Kablolu Kulaklık")
        XCTAssertEqual(AudioRoute.bluetooth.displayName, "Bluetooth")
    }

    func testAudioRouteIconNames() {
        XCTAssertEqual(AudioRoute.receiver.iconName, "phone")
        XCTAssertEqual(AudioRoute.speaker.iconName, "speaker.wave.3.fill")
        XCTAssertEqual(AudioRoute.headphones.iconName, "headphones")
        XCTAssertEqual(AudioRoute.bluetooth.iconName, "dot.radiowaves.left.and.right")
    }

    func testCurrentRouteInitialization() {
        // Given - Yeni AudioSessionManager
        let manager = AudioSessionManager()

        // Then - Varsayılan route receiver olmalı
        XCTAssertEqual(manager.currentRoute, .receiver)
    }

    // MARK: - Audio Interruption Tests

    func testHandleAudioInterruptionBegan() {
        // Given
        let interruptionNotification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
            ]
        )

        // When & Then - Exception fırlatmamalı
        XCTAssertNoThrow(audioSessionManager.handleAudioInterruption(interruptionNotification))
    }

    func testHandleAudioInterruptionEnded() {
        // Given
        let interruptionNotification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )

        // When & Then - Exception fırlatmamalı
        XCTAssertNoThrow(audioSessionManager.handleAudioInterruption(interruptionNotification))
    }

    func testHandleInvalidInterruption() {
        // Given - Geçersiz notification
        let invalidNotification = Notification(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [:]
        )

        // When & Then - Exception fırlatmamalı
        XCTAssertNoThrow(audioSessionManager.handleAudioInterruption(invalidNotification))
    }

    // MARK: - Bluetooth Availability Tests

    func testBluetoothAvailabilityInitialization() {
        // Given - Yeni AudioSessionManager
        let manager = AudioSessionManager()

        // Then - Bluetooth availability false olmalı (test ortamında)
        XCTAssertFalse(manager.isBluetoothAvailable)
    }

    // MARK: - Integration Tests

    func testFullCallLifecycle() throws {
        // Given - Yeni audio session manager
        XCTAssertFalse(audioSessionManager.isActive)
        XCTAssertFalse(audioSessionManager.isSpeakerOn)

        // When - Arama başlat
        try audioSessionManager.configureForCall()

        // Then - Doğru durumda olmalı
        XCTAssertTrue(audioSessionManager.isActive)

        // When - Speaker'ı aç
        try audioSessionManager.setSpeaker(enabled: true)

        // Then
        XCTAssertTrue(audioSessionManager.isSpeakerOn)

        // When - Bluetooth'a geç (mevcut değilse hata almayacak)
        try audioSessionManager.setBluetoothEnabled(true)

        // Then - Hata almamalıyız
        XCTAssertNoThrow(try audioSessionManager.setBluetoothEnabled(true))

        // When - Arama sonlandır
        audioSessionManager.restoreDefaultConfiguration()

        // Then - Temizlenmiş olmalı
        XCTAssertFalse(audioSessionManager.isActive)
        XCTAssertFalse(audioSessionManager.isSpeakerOn)
    }

    func testMultipleConfigurationCalls() throws {
        // Given
        XCTAssertFalse(audioSessionManager.isActive)

        // When - Birden fazla konfigürasyon
        try audioSessionManager.configureForCall()
        XCTAssertTrue(audioSessionManager.isActive)

        try audioSessionManager.configureForCall() // İkinci çağrı
        XCTAssertTrue(audioSessionManager.isActive) // Hala aktif olmalı

        // Then - Temizlik doğru çalışmalı
        audioSessionManager.restoreDefaultConfiguration()
        XCTAssertFalse(audioSessionManager.isActive)
    }

    // MARK: - Error Handling Tests

    func testConfigurationWithInvalidState() {
        // Note: Bu test gerçek cihazlarda audio session durumuna bağlı
        // Simulator'de geçerli olmayabilir

        // Given - AudioSessionManager
        let manager = AudioSessionManager()

        // When & Then - Normal şartlar altında hata almamalıyız
        XCTAssertNoThrow(try manager.configureForCall())

        // Temizlik
        manager.restoreDefaultConfiguration()
    }

    // MARK: - Performance Tests

    func testConfigurationPerformance() {
        measure {
            do {
                try audioSessionManager.configureForCall()
                audioSessionManager.restoreDefaultConfiguration()
            } catch {
                XCTFail("Configuration failed: \(error)")
            }
        }
    }

    func testSpeakerTogglePerformance() throws {
        // Given
        try audioSessionManager.configureForCall()

        // When
        measure {
            do {
                try audioSessionManager.setSpeaker(enabled: true)
                try audioSessionManager.setSpeaker(enabled: false)
            } catch {
                XCTFail("Speaker toggle failed: \(error)")
            }
        }
    }
}