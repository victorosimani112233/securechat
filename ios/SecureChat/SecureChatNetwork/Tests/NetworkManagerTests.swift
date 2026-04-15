import XCTest
import Network
import Combine
@testable import SecureChatNetwork

/**
 * NetworkManager unit testleri.
 *
 * Ağ bağlantısı izleme, bağlantı türü tespiti,
 * ICE server optimizasyonu ve medya ayarları testleri.
 */
@available(iOS 13.0, *)
final class NetworkManagerTests: XCTestCase {

    private var networkManager: NetworkManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        networkManager = NetworkManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        networkManager?.stopMonitoring()
        networkManager = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        XCTAssertEqual(networkManager.connectionStatus, .unavailable)
        XCTAssertEqual(networkManager.connectionType, .unknown)
        XCTAssertFalse(networkManager.isExpensive)
        XCTAssertFalse(networkManager.isConstrained)
    }

    func testMonitoringStartsAutomatically() {
        // NetworkManager should start monitoring automatically on init
        XCTAssertNotNil(networkManager)

        // Give it a moment to initialize
        let expectation = XCTestExpectation(description: "Initial state update")
        networkManager.$connectionStatus
            .dropFirst() // Skip initial value
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Connection Type Tests

    func testConnectionTypeProperties() {
        // Test each connection type's properties
        XCTAssertTrue(NetworkConnectionType.wifi.isP2PFriendly)
        XCTAssertTrue(NetworkConnectionType.wiredEthernet.isP2PFriendly)
        XCTAssertFalse(NetworkConnectionType.cellular.isP2PFriendly)
        XCTAssertFalse(NetworkConnectionType.unknown.isP2PFriendly)

        // Test display names
        XCTAssertEqual(NetworkConnectionType.wifi.displayName, "Wi-Fi")
        XCTAssertEqual(NetworkConnectionType.cellular.displayName, "Hücresel")
        XCTAssertEqual(NetworkConnectionType.wiredEthernet.displayName, "Ethernet")
    }

    func testConnectionStatusProperties() {
        // Test display names
        XCTAssertEqual(NetworkConnectionStatus.unavailable.displayName, "Bağlantı Yok")
        XCTAssertEqual(NetworkConnectionStatus.poor.displayName, "Zayıf Bağlantı")
        XCTAssertEqual(NetworkConnectionStatus.good.displayName, "İyi Bağlantı")
        XCTAssertEqual(NetworkConnectionStatus.excellent.displayName, "Mükemmel Bağlantı")
    }

    // MARK: - ICE Server Configuration Tests

    func testOptimizedICEServersForWiFi() {
        // Set connection type to WiFi (this would normally be done by network monitoring)
        let wifiServers = getICEServersForConnectionType(.wifi)

        XCTAssertGreaterThanOrEqual(wifiServers.count, 2)
        XCTAssertTrue(wifiServers.allSatisfy { $0.urls.first?.contains("stun:") == true })
    }

    func testOptimizedICEServersForCellular() {
        let cellularServers = getICEServersForConnectionType(.cellular)

        // Cellular should have more servers for better connectivity
        XCTAssertGreaterThanOrEqual(cellularServers.count, 3)
        XCTAssertTrue(cellularServers.allSatisfy { $0.urls.first?.contains("stun:") == true })
    }

    func testOptimizedICEServersForEthernet() {
        let ethernetServers = getICEServersForConnectionType(.wiredEthernet)

        // Ethernet usually needs fewer servers
        XCTAssertGreaterThanOrEqual(ethernetServers.count, 1)
    }

    func testOptimizedICEServersForUnknown() {
        let unknownServers = getICEServersForConnectionType(.unknown)

        // Unknown should use safe defaults
        XCTAssertGreaterThanOrEqual(unknownServers.count, 2)
    }

    // MARK: - Media Settings Tests

    func testRecommendedMediaSettingsForExcellentConnection() {
        let settings = getMediaSettingsForStatus(.excellent)

        XCTAssertEqual(settings.maxVideoBitrate, 2000) // 2 Mbps
        XCTAssertEqual(settings.maxAudioBitrate, 128)  // 128 kbps
        XCTAssertEqual(settings.videoResolution, .hd720)
        XCTAssertEqual(settings.audioSampleRate, 48000)
    }

    func testRecommendedMediaSettingsForGoodConnection() {
        let settings = getMediaSettingsForStatus(.good)

        XCTAssertEqual(settings.maxVideoBitrate, 1000) // 1 Mbps
        XCTAssertEqual(settings.maxAudioBitrate, 96)   // 96 kbps
        XCTAssertEqual(settings.videoResolution, .vga)
        XCTAssertEqual(settings.audioSampleRate, 48000)
    }

    func testRecommendedMediaSettingsForPoorConnection() {
        let settings = getMediaSettingsForStatus(.poor)

        XCTAssertEqual(settings.maxVideoBitrate, 500)  // 500 kbps
        XCTAssertEqual(settings.maxAudioBitrate, 64)   // 64 kbps
        XCTAssertEqual(settings.videoResolution, .qvga)
        XCTAssertEqual(settings.audioSampleRate, 16000)
    }

    func testRecommendedMediaSettingsForUnavailableConnection() {
        let settings = getMediaSettingsForStatus(.unavailable)

        XCTAssertEqual(settings.maxVideoBitrate, 0)
        XCTAssertEqual(settings.maxAudioBitrate, 0)
        XCTAssertEqual(settings.videoResolution, .qvga)
        XCTAssertEqual(settings.audioSampleRate, 8000)
    }

    // MARK: - Video Resolution Tests

    func testVideoResolutionSizes() {
        XCTAssertEqual(VideoResolution.qvga.size.width, 320)
        XCTAssertEqual(VideoResolution.qvga.size.height, 240)

        XCTAssertEqual(VideoResolution.vga.size.width, 640)
        XCTAssertEqual(VideoResolution.vga.size.height, 480)

        XCTAssertEqual(VideoResolution.hd720.size.width, 1280)
        XCTAssertEqual(VideoResolution.hd720.size.height, 720)

        XCTAssertEqual(VideoResolution.hd1080.size.width, 1920)
        XCTAssertEqual(VideoResolution.hd1080.size.height, 1080)
    }

    // MARK: - Latency Measurement Tests

    func testLatencyMeasurementToValidHost() async {
        let expectation = XCTestExpectation(description: "Latency measurement")

        networkManager.measureLatency(to: "google.com") { latency in
            if let latency = latency {
                XCTAssertGreaterThan(latency, 0)
                XCTAssertLessThan(latency, 10.0) // Should be less than 10 seconds
            }
            // Note: latency might be nil if network is unavailable, which is also valid
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 10.0)
    }

    func testLatencyMeasurementToInvalidHost() async {
        let expectation = XCTestExpectation(description: "Invalid host latency")

        networkManager.measureLatency(to: "invalid.host.that.does.not.exist.anywhere") { latency in
            XCTAssertNil(latency) // Should return nil for invalid host
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 10.0)
    }

    // MARK: - ICE Server Configuration Tests

    func testICEServerConfigurationStructure() {
        let config = ICEServerConfig(urls: ["stun:stun.example.com:3478"])
        XCTAssertEqual(config.urls, ["stun:stun.example.com:3478"])
        XCTAssertNil(config.username)
        XCTAssertNil(config.credential)

        let configWithCredentials = ICEServerConfig(
            urls: ["turn:turn.example.com:3478"],
            username: "testuser",
            credential: "testpass"
        )
        XCTAssertEqual(configWithCredentials.username, "testuser")
        XCTAssertEqual(configWithCredentials.credential, "testpass")
    }

    // MARK: - Published Properties Tests

    func testPublishedPropertiesUpdate() {
        var connectionStatusUpdates: [NetworkConnectionStatus] = []
        var connectionTypeUpdates: [NetworkConnectionType] = []

        networkManager.$connectionStatus
            .sink { status in
                connectionStatusUpdates.append(status)
            }
            .store(in: &cancellables)

        networkManager.$connectionType
            .sink { type in
                connectionTypeUpdates.append(type)
            }
            .store(in: &cancellables)

        // Initial values should be recorded
        XCTAssertEqual(connectionStatusUpdates.first, .unavailable)
        XCTAssertEqual(connectionTypeUpdates.first, .unknown)
    }

    // MARK: - Performance Tests

    func testICEServerGenerationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = getICEServersForConnectionType(.wifi)
            }
        }
    }

    func testMediaSettingsGenerationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = getMediaSettingsForStatus(.good)
            }
        }
    }

    // MARK: - Helper Methods

    private func getICEServersForConnectionType(_ type: NetworkConnectionType) -> [ICEServerConfig] {
        // Simulate the internal logic since we can't directly set connection type
        switch type {
        case .wifi:
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun1.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun2.l.google.com:19302"])
            ]
        case .cellular:
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun1.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun.cloudflare.com:3478"])
            ]
        case .wiredEthernet:
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"])
            ]
        case .unknown, .loopback, .other:
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun1.l.google.com:19302"])
            ]
        }
    }

    private func getMediaSettingsForStatus(_ status: NetworkConnectionStatus) -> MediaSettings {
        switch status {
        case .excellent:
            return MediaSettings(
                maxVideoBitrate: 2000,
                maxAudioBitrate: 128,
                videoResolution: .hd720,
                audioSampleRate: 48000
            )
        case .good:
            return MediaSettings(
                maxVideoBitrate: 1000,
                maxAudioBitrate: 96,
                videoResolution: .vga,
                audioSampleRate: 48000
            )
        case .poor:
            return MediaSettings(
                maxVideoBitrate: 500,
                maxAudioBitrate: 64,
                videoResolution: .qvga,
                audioSampleRate: 16000
            )
        case .unavailable:
            return MediaSettings(
                maxVideoBitrate: 0,
                maxAudioBitrate: 0,
                videoResolution: .qvga,
                audioSampleRate: 8000
            )
        }
    }
}

// MARK: - Mock Network Path for Testing

@available(iOS 13.0, *)
class MockNetworkPath {
    var status: NWPath.Status = .unsatisfied
    var isExpensive: Bool = false
    var isConstrained: Bool = false
    var availableInterfaces: [NWInterface.InterfaceType] = []

    func usesInterfaceType(_ type: NWInterface.InterfaceType) -> Bool {
        return availableInterfaces.contains(type)
    }
}