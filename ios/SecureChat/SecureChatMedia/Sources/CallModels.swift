import Foundation
import SecureChatCommon

/**
 * Arama yaşam döngüsü durumları.
 *
 * Durum geçişleri:
 * idle → initiating → ringing → connecting → active → ended
 *                         ↓                      ↓
 *                     rejected                failed
 *                         ↓
 *                       busy
 */
public enum CallState: String, CaseIterable {
    /// Arama yok, bekleme durumunda
    case idle = "idle"

    /// Arama başlatılıyor (SDP offer hazırlanıyor)
    case initiating = "initiating"

    /// Karşı tarafa bildirim gönderildi, cevap bekleniyor
    case ringing = "ringing"

    /// SDP answer alındı, ICE negotiation devam ediyor
    case connecting = "connecting"

    /// Arama aktif, medya akışı var
    case active = "active"

    /// Bağlantı koptu, yeniden bağlanılıyor
    case reconnecting = "reconnecting"

    /// Normal sonlanma
    case ended = "ended"

    /// Karşı taraf aramayı reddetti
    case rejected = "rejected"

    /// Karşı taraf başka bir aramada meşgul
    case busy = "busy"

    /// Teknik hata nedeniyle sonlandı
    case failed = "failed"

    public var displayName: String {
        switch self {
        case .idle:
            return "Bekleme"
        case .initiating:
            return "Başlatılıyor"
        case .ringing:
            return "Çalıyor"
        case .connecting:
            return "Bağlanıyor"
        case .active:
            return "Aktif"
        case .reconnecting:
            return "Yeniden Bağlanıyor"
        case .ended:
            return "Sonlandı"
        case .rejected:
            return "Reddedildi"
        case .busy:
            return "Meşgul"
        case .failed:
            return "Başarısız"
        }
    }
}

/**
 * Arama yönü: gelen veya giden.
 */
public enum CallDirection: String, CaseIterable {
    /// Gelen arama
    case incoming = "incoming"

    /// Giden arama
    case outgoing = "outgoing"

    public var displayName: String {
        switch self {
        case .incoming:
            return "Gelen"
        case .outgoing:
            return "Giden"
        }
    }
}

/**
 * Aktif bir arama oturumunun tüm bilgilerini tutan veri sınıfı.
 */
public struct CallSession: Equatable, Identifiable {
    public let id = UUID()

    /// Benzersiz arama kimlik numarası (UUID)
    public let callId: String

    /// Karşı tarafın kullanıcı ID'si
    public let peerId: String

    /// Arama tipi: sesli veya görüntülü
    public let callType: CallType

    /// Arama yönü: gelen veya giden
    public let direction: CallDirection

    /// Aramanın mevcut durumu
    public var state: CallState

    /// Aramanın bağlantı kurulduğu zaman (epoch ms), nil ise henüz bağlanılmadı
    public var startTime: TimeInterval?

    /// Aramanın süresi (saniye), nil ise henüz sonlanmadı
    public var duration: TimeInterval?

    /// Mikrofon sessiz mi
    public var isMuted: Bool

    /// Hoparlör açık mı
    public var isSpeakerOn: Bool

    /// Kamera açık mı (sadece video aramalar için anlamlı)
    public var isCameraEnabled: Bool

    /// Ön kamera mı kullanılıyor
    public var isUsingFrontCamera: Bool

    public init(
        callId: String,
        peerId: String,
        callType: CallType,
        direction: CallDirection,
        state: CallState = .idle,
        startTime: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        isMuted: Bool = false,
        isSpeakerOn: Bool = false,
        isCameraEnabled: Bool = true,
        isUsingFrontCamera: Bool = true
    ) {
        self.callId = callId
        self.peerId = peerId
        self.callType = callType
        self.direction = direction
        self.state = state
        self.startTime = startTime
        self.duration = duration
        self.isMuted = isMuted
        self.isSpeakerOn = isSpeakerOn
        self.isCameraEnabled = isCameraEnabled
        self.isUsingFrontCamera = isUsingFrontCamera
    }

    /// Aramanın aktif süresini hesaplar
    public var activeDuration: TimeInterval? {
        guard let startTime = startTime else { return nil }
        return Date().timeIntervalSince1970 - startTime
    }

    /// Aramanın CallKit uyumlu formatlanmış süresini döndürür
    public var formattedDuration: String {
        guard let duration = activeDuration else { return "00:00" }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%02d:%02d:%02d", hours, remainingMinutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// CallKit için arama durumu metni
    public var callKitStatusText: String {
        switch state {
        case .initiating, .ringing:
            return direction == .outgoing ? "Aranıyor..." : "Gelen arama"
        case .connecting:
            return "Bağlanıyor..."
        case .active:
            return formattedDuration
        case .ended:
            return "Arama sonlandı"
        case .rejected:
            return "Arama reddedildi"
        case .busy:
            return "Meşgul"
        case .failed:
            return "Arama başarısız"
        case .reconnecting:
            return "Yeniden bağlanıyor..."
        case .idle:
            return ""
        }
    }

    public static func == (lhs: CallSession, rhs: CallSession) -> Bool {
        return lhs.callId == rhs.callId &&
               lhs.peerId == rhs.peerId &&
               lhs.state == rhs.state &&
               lhs.startTime == rhs.startTime &&
               lhs.isMuted == rhs.isMuted &&
               lhs.isSpeakerOn == rhs.isSpeakerOn &&
               lhs.isCameraEnabled == rhs.isCameraEnabled &&
               lhs.isUsingFrontCamera == rhs.isUsingFrontCamera
    }
}

/**
 * Arama hataları
 */
public enum CallError: Error, LocalizedError {
    case invalidPeerId
    case noActiveCall
    case callAlreadyActive
    case webRTCError(String)
    case audioSessionError(String)
    case callKitError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPeerId:
            return "Geçersiz kullanıcı ID"
        case .noActiveCall:
            return "Aktif arama yok"
        case .callAlreadyActive:
            return "Zaten aktif bir arama var"
        case .webRTCError(let message):
            return "WebRTC hatası: \(message)"
        case .audioSessionError(let message):
            return "Ses hatası: \(message)"
        case .callKitError(let message):
            return "CallKit hatası: \(message)"
        case .networkError(let message):
            return "Ağ hatası: \(message)"
        }
    }
}

/**
 * Arama istatistikleri
 */
public struct CallStatistics {
    /// Toplam arama süresi (saniye)
    public let duration: TimeInterval

    /// Audio bitrate (kbps)
    public let audioBitrate: Double

    /// Video bitrate (kbps) - sadece video aramalar için
    public let videoBitrate: Double?

    /// Ağ gecikmesi (ms)
    public let latency: Double

    /// Paket kaybı yüzdesi
    public let packetLoss: Double

    /// Bağlantı kalitesi
    public let connectionQuality: ConnectionQuality

    public init(
        duration: TimeInterval,
        audioBitrate: Double,
        videoBitrate: Double? = nil,
        latency: Double,
        packetLoss: Double,
        connectionQuality: ConnectionQuality
    ) {
        self.duration = duration
        self.audioBitrate = audioBitrate
        self.videoBitrate = videoBitrate
        self.latency = latency
        self.packetLoss = packetLoss
        self.connectionQuality = connectionQuality
    }
}

/**
 * Bağlantı kalitesi göstergesi
 */
public enum ConnectionQuality: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    case unavailable = "unavailable"

    public var displayName: String {
        switch self {
        case .excellent:
            return "Mükemmel"
        case .good:
            return "İyi"
        case .fair:
            return "Orta"
        case .poor:
            return "Zayıf"
        case .unavailable:
            return "Bağlantı Yok"
        }
    }

    /// Kalite seviyesini 0-100 arası puanla döndürür
    public var score: Int {
        switch self {
        case .excellent:
            return 90
        case .good:
            return 70
        case .fair:
            return 50
        case .poor:
            return 25
        case .unavailable:
            return 0
        }
    }
}