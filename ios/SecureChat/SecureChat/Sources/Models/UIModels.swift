import Foundation
import SecureChatStorage
import SecureChatNetwork
import SecureChatContacts

// MARK: - UI State Models

/// Konuşma listesi ekranı için UI durumu
public struct ConversationsUIState {
    public var conversations: [Conversation] = []
    public var connectionState: ConnectionState = .disconnected
    public var isSearchVisible: Bool = false
    public var searchQuery: String = ""

    public init() {}
}

/// Sohbet ekranı için UI durumu
public struct ChatUIState {
    public var messages: [LocalMessage] = []
    public var conversationInfo: ConversationInfo?
    public var isTyping: Bool = false
    public var messageText: String = ""
    public var isLoading: Bool = false

    public init() {}
}

/// Arama ekranı için UI durumu
public struct CallUIState {
    public var callSession: CallSession?
    public var callDuration: TimeInterval = 0
    public var isMuted: Bool = false
    public var isSpeakerOn: Bool = false
    public var isCameraEnabled: Bool = true
    public var isVideoCall: Bool = false

    public init() {}
}

/// Kişiler ekranı için UI durumu
public struct ContactsUIState {
    public var contacts: [ContactInfo] = []
    public var isLoading: Bool = false
    public var hasPermission: Bool = false
    public var searchQuery: String = ""

    public init() {}
}

/// Ayarlar ekranı için UI durumu
public struct SettingsUIState {
    public var userProfile: UserProfile?
    public var isDarkMode: Bool = false
    public var isNotificationsEnabled: Bool = true
    public var isBiometricsEnabled: Bool = false

    public init() {}
}

// MARK: - Domain Models for UI

/// Konuşma bilgisi
public struct ConversationInfo {
    public let id: String
    public let peerName: String
    public let peerId: String
    public let isGroup: Bool
    public let isOnline: Bool
    public let lastSeen: Date?

    public init(id: String, peerName: String, peerId: String, isGroup: Bool, isOnline: Bool, lastSeen: Date?) {
        self.id = id
        self.peerName = peerName
        self.peerId = peerId
        self.isGroup = isGroup
        self.isOnline = isOnline
        self.lastSeen = lastSeen
    }
}

/// Arama oturumu
public struct CallSession {
    public let id: String
    public let peerId: String
    public let peerName: String
    public let type: CallType
    public let state: CallState
    public let startTime: Date
    public let isMuted: Bool
    public let isSpeakerOn: Bool
    public let isCameraEnabled: Bool

    public init(id: String, peerId: String, peerName: String, type: CallType,
               state: CallState, startTime: Date, isMuted: Bool,
               isSpeakerOn: Bool, isCameraEnabled: Bool) {
        self.id = id
        self.peerId = peerId
        self.peerName = peerName
        self.type = type
        self.state = state
        self.startTime = startTime
        self.isMuted = isMuted
        self.isSpeakerOn = isSpeakerOn
        self.isCameraEnabled = isCameraEnabled
    }
}

/// Arama türü
public enum CallType: String, CaseIterable {
    case voice = "VOICE"
    case video = "VIDEO"
}

/// Arama durumu
public enum CallState: String, CaseIterable {
    case ringing = "RINGING"
    case connecting = "CONNECTING"
    case active = "ACTIVE"
    case reconnecting = "RECONNECTING"
    case ended = "ENDED"
}

/// Kullanıcı profili
public struct UserProfile {
    public let id: String
    public let name: String
    public let phoneNumber: String
    public let profileImageUrl: String?

    public init(id: String, name: String, phoneNumber: String, profileImageUrl: String?) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
        self.profileImageUrl = profileImageUrl
    }
}

// MARK: - Extensions

extension LocalMessage {
    /// Mesaj zamanı formatı
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp / 1000)))
    }

    /// Mesaj zamanı (bugün/dün formatı)
    public var formattedDateTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        let formatter = DateFormatter()

        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if Calendar.current.isDateInYesterday(date) {
            return "Dün"
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

extension Conversation {
    /// Son mesaj zamanı formatı
    public var formattedLastMessageTime: String {
        guard let timestamp = lastMessageTimestamp else { return "" }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
        let formatter = DateFormatter()

        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if Calendar.current.isDateInYesterday(date) {
            return "Dün"
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }

    /// Avatar için renk hex değeri
    public var avatarColorHex: String {
        let colors = [
            "#00897B", "#00ACC1", "#5C6BC0", "#7E57C2",
            "#EF5350", "#FF7043", "#26A69A", "#42A5F5",
            "#EC407A", "#66BB6A"
        ]
        let index = abs(peerName.hashValue) % colors.count
        return colors[index]
    }
}