import Foundation

/// Mesaj durumu. Gönderim yaşam döngüsünü takip eder.
public enum MessageStatus: String, CaseIterable, Codable {
    case sending = "SENDING"
    case sent = "SENT"
    case delivered = "DELIVERED"
    case read = "READ"
    case failed = "FAILED"
}