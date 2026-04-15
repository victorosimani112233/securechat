import Foundation

/**
 * WebSocket bağlantı durumu yönetimi.
 *
 * Bağlantı durumu değişiklikleri gözlemlenebilir ve
 * UI'da uygun gösterimlerin yapılması sağlanır.
 */

// MARK: - Connection State

/// WebSocket bağlantı durumları
public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(NetworkError)

    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - P2P Connection State

/// Peer-to-peer bağlantı durumları
public enum PeerState: String, CaseIterable {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connectedSignaling = "CONNECTED_SIGNALING"  // Signaling üzerinden (relay mode)
    case connectedP2P = "CONNECTED_P2P"              // Doğrudan P2P bağlantı
    case reconnecting = "RECONNECTING"

    /// Kullanıcı dostu açıklama
    public var displayName: String {
        switch self {
        case .disconnected:
            return "Bağlantı Yok"
        case .connecting:
            return "Bağlanıyor"
        case .connectedSignaling:
            return "Relay Üzerinden"
        case .connectedP2P:
            return "Doğrudan Bağlı"
        case .reconnecting:
            return "Yeniden Bağlanıyor"
        }
    }

    /// Bağlantı kalitesi göstergesi
    public var qualityIndicator: ConnectionQuality {
        switch self {
        case .disconnected:
            return .none
        case .connecting, .reconnecting:
            return .poor
        case .connectedSignaling:
            return .medium
        case .connectedP2P:
            return .excellent
        }
    }
}

// MARK: - Connection Quality

/// Bağlantı kalite göstergesi
public enum ConnectionQuality: Int, CaseIterable {
    case none = 0
    case poor = 1
    case medium = 2
    case good = 3
    case excellent = 4

    /// UI'da gösterilecek renk
    public var color: String {
        switch self {
        case .none:
            return "gray"
        case .poor:
            return "red"
        case .medium:
            return "orange"
        case .good:
            return "yellow"
        case .excellent:
            return "green"
        }
    }

    /// Bağlantı kalitesi açıklaması
    public var description: String {
        switch self {
        case .none:
            return "Bağlantı Yok"
        case .poor:
            return "Zayıf"
        case .medium:
            return "Orta"
        case .good:
            return "İyi"
        case .excellent:
            return "Mükemmel"
        }
    }
}

// MARK: - Network Error

/// Network katmanı hataları
public enum NetworkError: Error, LocalizedError, Equatable {
    case connectionFailed(String)
    case authenticationFailed
    case messageDecodingFailed(String)
    case messageEncodingFailed(String)
    case webSocketError(String)
    case certificatePinningFailed
    case networkUnavailable
    case timeout
    case unknownError(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Bağlantı hatası: \(reason)"
        case .authenticationFailed:
            return "Kimlik doğrulama hatası"
        case .messageDecodingFailed(let reason):
            return "Mesaj çözme hatası: \(reason)"
        case .messageEncodingFailed(let reason):
            return "Mesaj kodlama hatası: \(reason)"
        case .webSocketError(let reason):
            return "WebSocket hatası: \(reason)"
        case .certificatePinningFailed:
            return "Sertifika doğrulama hatası"
        case .networkUnavailable:
            return "Ağ bağlantısı yok"
        case .timeout:
            return "Bağlantı zaman aşımı"
        case .unknownError(let reason):
            return "Bilinmeyen hata: \(reason)"
        }
    }

    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        return lhs.localizedDescription == rhs.localizedDescription
    }
}

// MARK: - Connection Statistics

/// Bağlantı istatistikleri
public struct ConnectionStatistics {
    public let connectedDuration: TimeInterval
    public let messagesReceived: Int
    public let messagesSent: Int
    public let bytesReceived: Int64
    public let bytesSent: Int64
    public let reconnectCount: Int
    public let lastReconnectTime: Date?
    public let averageLatency: TimeInterval?

    public init(
        connectedDuration: TimeInterval = 0,
        messagesReceived: Int = 0,
        messagesSent: Int = 0,
        bytesReceived: Int64 = 0,
        bytesSent: Int64 = 0,
        reconnectCount: Int = 0,
        lastReconnectTime: Date? = nil,
        averageLatency: TimeInterval? = nil
    ) {
        self.connectedDuration = connectedDuration
        self.messagesReceived = messagesReceived
        self.messagesSent = messagesSent
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.reconnectCount = reconnectCount
        self.lastReconnectTime = lastReconnectTime
        self.averageLatency = averageLatency
    }

    /// Ağ performans göstergesi
    public var networkPerformance: ConnectionQuality {
        guard let latency = averageLatency else { return .none }

        if latency < 0.05 {  // < 50ms
            return .excellent
        } else if latency < 0.1 {  // < 100ms
            return .good
        } else if latency < 0.2 {  // < 200ms
            return .medium
        } else {
            return .poor
        }
    }
}