import Foundation
import Network
import Combine

/**
 * iOS Network Framework kullanarak ağ bağlantısı izleme yöneticisi.
 *
 * Bu sınıf:
 * - Ağ bağlantısının durumunu izler (Wi-Fi, Cellular, No Connection)
 * - Bağlantı kalitesini değerlendirir
 * - Ağ değişikliklerini gözlemlenebilir şekilde yayar
 * - WebRTC ICE server konfigürasyonunu ağ türüne göre optimize eder
 */
@available(iOS 12.0, *)
public class NetworkManager: ObservableObject {

    // MARK: - Published Properties

    @Published public private(set) var connectionStatus: NetworkConnectionStatus = .unavailable
    @Published public private(set) var connectionType: NetworkConnectionType = .unknown
    @Published public private(set) var isExpensive: Bool = false
    @Published public private(set) var isConstrained: Bool = false

    // MARK: - Private Properties

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "networkMonitor", qos: .utility)
    private var cancellables = Set<AnyCancellable>()

    // Network quality assessment
    private var latencyMeasurements: [TimeInterval] = []
    private var bandwidthEstimate: Double = 0.0

    // MARK: - Initialization

    public init() {
        startMonitoring()
    }

    deinit {
        pathMonitor.cancel()
    }

    // MARK: - Public Methods

    /**
     * Ağ izlemeyi başlatır.
     */
    public func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkPathUpdate(path)
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    /**
     * Ağ izlemeyi durdurur.
     */
    public func stopMonitoring() {
        pathMonitor.cancel()
    }

    /**
     * Belirli bir host'a gecikme (latency) ölçümü yapar.
     */
    public func measureLatency(to host: String, completion: @escaping (TimeInterval?) -> Void) {
        guard let url = URL(string: "https://\(host)") else {
            completion(nil)
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0

        URLSession.shared.dataTask(with: request) { _, response, error in
            let latency = CFAbsoluteTimeGetCurrent() - startTime

            DispatchQueue.main.async {
                if error == nil && response != nil {
                    self.recordLatencyMeasurement(latency)
                    completion(latency)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }

    /**
     * Bağlantı türüne göre optimize edilmiş ICE server konfigürasyonu sağlar.
     */
    public func getOptimizedICEServers() -> [ICEServerConfig] {
        switch connectionType {
        case .wifi:
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun1.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun2.l.google.com:19302"])
            ]

        case .cellular:
            // Cellular bağlantılarda daha fazla STUN/TURN server gerekebilir
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun1.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun.cloudflare.com:3478"]),
                // Production için kendi TURN server'ınızı ekleyin
                // ICEServerConfig(urls: ["turn:turn.securechat.app:3478"], username: "user", credential: "pass")
            ]

        case .wiredEthernet:
            // Ethernet bağlantılarda genellikle NAT sorunları daha az
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"])
            ]

        case .unknown, .loopback, .other:
            // Güvenli varsayılan konfigürasyon
            return [
                ICEServerConfig(urls: ["stun:stun.l.google.com:19302"]),
                ICEServerConfig(urls: ["stun:stun1.l.google.com:19302"])
            ]
        }
    }

    /**
     * Ağ kalitesine göre önerilen medya konfigürasyonunu döndürür.
     */
    public func getRecommendedMediaSettings() -> MediaSettings {
        let averageLatency = latencyMeasurements.isEmpty ? nil : latencyMeasurements.reduce(0, +) / Double(latencyMeasurements.count)

        switch connectionStatus {
        case .excellent:
            return MediaSettings(
                maxVideoBitrate: 2000, // 2 Mbps
                maxAudioBitrate: 128,  // 128 kbps
                videoResolution: .hd720,
                audioSampleRate: 48000
            )
        case .good:
            return MediaSettings(
                maxVideoBitrate: 1000, // 1 Mbps
                maxAudioBitrate: 96,   // 96 kbps
                videoResolution: .vga,
                audioSampleRate: 48000
            )
        case .poor:
            return MediaSettings(
                maxVideoBitrate: 500,  // 500 kbps
                maxAudioBitrate: 64,   // 64 kbps
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

    // MARK: - Private Methods

    private func handleNetworkPathUpdate(_ path: NWPath) {
        // Update connection type
        updateConnectionType(from: path)

        // Update connection status
        updateConnectionStatus(from: path)

        // Update connection properties
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained

        // Log network change for debugging
        print("Network changed: \(connectionType.rawValue) - \(connectionStatus.rawValue)")
        if isExpensive { print("Connection is expensive") }
        if isConstrained { print("Connection is constrained") }
    }

    private func updateConnectionType(from path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else if path.usesInterfaceType(.loopback) {
            connectionType = .loopback
        } else if path.usesInterfaceType(.other) {
            connectionType = .other
        } else {
            connectionType = .unknown
        }
    }

    private func updateConnectionStatus(from path: NWPath) {
        switch path.status {
        case .satisfied:
            // Further assess quality based on path properties
            if path.isExpensive || path.isConstrained {
                connectionStatus = .poor
            } else if !latencyMeasurements.isEmpty {
                let avgLatency = latencyMeasurements.reduce(0, +) / Double(latencyMeasurements.count)
                if avgLatency < 0.05 { // < 50ms
                    connectionStatus = .excellent
                } else if avgLatency < 0.1 { // < 100ms
                    connectionStatus = .good
                } else {
                    connectionStatus = .poor
                }
            } else {
                connectionStatus = .good // Default for satisfied connection
            }

        case .unsatisfied:
            connectionStatus = .unavailable

        case .requiresConnection:
            connectionStatus = .poor

        @unknown default:
            connectionStatus = .unavailable
        }
    }

    private func recordLatencyMeasurement(_ latency: TimeInterval) {
        latencyMeasurements.append(latency)

        // Keep only last 10 measurements
        if latencyMeasurements.count > 10 {
            latencyMeasurements.removeFirst()
        }
    }
}

// MARK: - Supporting Types

/// Ağ bağlantısı durumu
public enum NetworkConnectionStatus: String, CaseIterable {
    case unavailable = "unavailable"
    case poor = "poor"
    case good = "good"
    case excellent = "excellent"

    public var displayName: String {
        switch self {
        case .unavailable:
            return "Bağlantı Yok"
        case .poor:
            return "Zayıf Bağlantı"
        case .good:
            return "İyi Bağlantı"
        case .excellent:
            return "Mükemmel Bağlantı"
        }
    }
}

/// Ağ bağlantısı türü
public enum NetworkConnectionType: String, CaseIterable {
    case wifi = "wifi"
    case cellular = "cellular"
    case wiredEthernet = "ethernet"
    case loopback = "loopback"
    case other = "other"
    case unknown = "unknown"

    public var displayName: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Hücresel"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        case .other:
            return "Diğer"
        case .unknown:
            return "Bilinmeyen"
        }
    }

    /// Bu bağlantı türü P2P için uygun mu?
    public var isP2PFriendly: Bool {
        switch self {
        case .wifi, .wiredEthernet:
            return true
        case .cellular:
            return false // Cellular genellikle CGNAT arkasında
        case .loopback, .other, .unknown:
            return false
        }
    }
}

/// ICE Server konfigürasyonu
public struct ICEServerConfig {
    public let urls: [String]
    public let username: String?
    public let credential: String?

    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

/// Medya ayarları önerileri
public struct MediaSettings {
    public let maxVideoBitrate: Int // kbps
    public let maxAudioBitrate: Int // kbps
    public let videoResolution: VideoResolution
    public let audioSampleRate: Int // Hz

    public init(maxVideoBitrate: Int, maxAudioBitrate: Int, videoResolution: VideoResolution, audioSampleRate: Int) {
        self.maxVideoBitrate = maxVideoBitrate
        self.maxAudioBitrate = maxAudioBitrate
        self.videoResolution = videoResolution
        self.audioSampleRate = audioSampleRate
    }
}

/// Video çözünürlük seçenekleri
public enum VideoResolution: String, CaseIterable {
    case qvga = "320x240"
    case vga = "640x480"
    case hd720 = "1280x720"
    case hd1080 = "1920x1080"

    public var size: (width: Int, height: Int) {
        switch self {
        case .qvga:
            return (320, 240)
        case .vga:
            return (640, 480)
        case .hd720:
            return (1280, 720)
        case .hd1080:
            return (1920, 1080)
        }
    }
}