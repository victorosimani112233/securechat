import Foundation

/// Mesaj içeriği türleri.
public enum MessageContentType: String, CaseIterable, Codable {
    case text = "TEXT"
    case image = "IMAGE"
    case file = "FILE"
    case voiceNote = "VOICE_NOTE"
    case system = "SYSTEM"
}