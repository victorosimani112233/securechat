import Foundation

/**
 * Signaling sunucusu üzerinden iletilen mesaj tipleri.
 * WebSocket bağlantısı üzerinden JSON olarak serialize/deserialize edilir.
 *
 * Her mesaj tipi farklı bir amaca hizmet eder:
 * - SdpOffer/SdpAnswer: WebRTC bağlantı kurulumu
 * - IceCandidate: NAT traversal için aday bilgisi
 * - EncryptedMessage: Signal Protocol ile şifrelenmiş mesaj
 * - PreKeyBundleMessage: İlk bağlantı için anahtar değişimi
 * - CallControl: Arama yaşam döngüsü kontrol mesajları
 */

// MARK: - Base Protocol

/// Tüm signaling mesajlarının ortak arayüzü
public protocol SignalMessageProtocol: Codable {
    var senderId: String { get }
    var recipientId: String { get }
    var timestamp: Int64 { get }
    var messageType: String { get }
}

// MARK: - Message Types

/// WebRTC SDP Offer — bağlantı başlatma isteği
public struct SdpOfferMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "sdp_offer"
    public let sdp: String
    public let callType: CallType

    public init(senderId: String, recipientId: String, timestamp: Int64, sdp: String, callType: CallType) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.sdp = sdp
        self.callType = callType
    }
}

/// WebRTC SDP Answer — bağlantı kabul yanıtı
public struct SdpAnswerMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "sdp_answer"
    public let sdp: String

    public init(senderId: String, recipientId: String, timestamp: Int64, sdp: String) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.sdp = sdp
    }
}

/// WebRTC ICE Candidate — NAT traversal için aday bilgisi
public struct IceCandidateMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "ice_candidate"
    public let candidate: String
    public let sdpMid: String?
    public let sdpMLineIndex: Int32

    public init(senderId: String, recipientId: String, timestamp: Int64, candidate: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

/// Signal Protocol ile şifrelenmiş mesaj zarfı
public struct EncryptedMessageSignal: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "encrypted_message"
    public let envelope: String // Base64 encoded EncryptedEnvelope

    public init(senderId: String, recipientId: String, timestamp: Int64, envelope: String) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.envelope = envelope
    }
}

/// X3DH key agreement için PreKey bundle mesajı
public struct PreKeyBundleMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "prekey_bundle"
    public let bundle: String // Serialized PreKey bundle

    public init(senderId: String, recipientId: String, timestamp: Int64, bundle: String) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.bundle = bundle
    }
}

/// Arama kontrol mesajı (çalma, kabul, red, kapatma, meşgul)
public struct CallControlMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "call_control"
    public let action: CallAction

    public init(senderId: String, recipientId: String, timestamp: Int64, action: CallAction) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.action = action
    }
}

/// WebSocket üzerinden iletilen ses verisi
public struct AudioDataMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "audio_data"
    public let data: String // Base64 encoded PCM ses verisi

    public init(senderId: String, recipientId: String, timestamp: Int64, data: String) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.data = data
    }
}

/// WebSocket üzerinden iletilen video frame verisi
public struct VideoDataMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "video_data"
    public let data: String // Base64 encoded JPEG frame
    public let width: Int32
    public let height: Int32

    public init(senderId: String, recipientId: String, timestamp: Int64, data: String, width: Int32, height: Int32) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.data = data
        self.width = width
        self.height = height
    }
}

/// WebSocket üzerinden dosya transferi
public struct FileTransferMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "file_transfer"
    public let fileName: String
    public let mimeType: String
    public let fileSize: Int64
    public let data: String // Base64 encoded dosya içeriği

    public init(senderId: String, recipientId: String, timestamp: Int64, fileName: String, mimeType: String, fileSize: Int64, data: String) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.data = data
    }
}

/// Grup yönetimi bildirimleri
public struct GroupNotificationMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "group_notification"
    public let groupId: String
    public let groupName: String
    public let action: GroupAction
    public let groupMembers: [String] // Grup üye listesi (tam liste)
    public let targetMemberId: String? // ADD_MEMBER/REMOVE_MEMBER için hedef üye

    public init(senderId: String, recipientId: String, timestamp: Int64, groupId: String, groupName: String, action: GroupAction, groupMembers: [String], targetMemberId: String? = nil) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.groupId = groupId
        self.groupName = groupName
        self.action = action
        self.groupMembers = groupMembers
        self.targetMemberId = targetMemberId
    }
}

/// Mesaj iletim/okundu bilgisi (delivery receipt)
public struct DeliveryReceiptMessage: SignalMessageProtocol {
    public let senderId: String
    public let recipientId: String
    public let timestamp: Int64
    public let messageType = "delivery_receipt"
    public let messageId: String
    public let status: String // "DELIVERED" veya "READ"

    public init(senderId: String, recipientId: String, timestamp: Int64, messageId: String, status: String) {
        self.senderId = senderId
        self.recipientId = recipientId
        self.timestamp = timestamp
        self.messageId = messageId
        self.status = status
    }
}

// MARK: - Supporting Enums

/// Arama türü — ses veya video
public enum CallType: String, Codable, CaseIterable {
    case voice = "VOICE"
    case video = "VIDEO"
}

/// Arama kontrol aksiyonları
public enum CallAction: String, Codable, CaseIterable {
    case ringing = "RINGING"
    case accept = "ACCEPT"
    case reject = "REJECT"
    case hangup = "HANGUP"
    case busy = "BUSY"
}

/// Grup yönetimi aksiyonları
public enum GroupAction: String, Codable, CaseIterable {
    case createGroup = "CREATE_GROUP"
    case addMember = "ADD_MEMBER"
    case removeMember = "REMOVE_MEMBER"
    case leaveGroup = "LEAVE_GROUP"
    case updateGroupName = "UPDATE_GROUP_NAME"
}

// MARK: - Message Factory

/// SignalMessage oluşturucu sınıfı
public struct SignalMessageFactory {

    /// JSON string'den SignalMessage decode eder
    public static func decodeMessage(from jsonString: String) throws -> SignalMessageProtocol {
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw SignalMessageError.invalidJSON
        }

        // İlk olarak type field'ını okuyan basit struct
        let typeContainer = try JSONDecoder().decode(MessageTypeContainer.self, from: jsonData)

        switch typeContainer.messageType {
        case "sdp_offer":
            return try JSONDecoder().decode(SdpOfferMessage.self, from: jsonData)
        case "sdp_answer":
            return try JSONDecoder().decode(SdpAnswerMessage.self, from: jsonData)
        case "ice_candidate":
            return try JSONDecoder().decode(IceCandidateMessage.self, from: jsonData)
        case "encrypted_message":
            return try JSONDecoder().decode(EncryptedMessageSignal.self, from: jsonData)
        case "prekey_bundle":
            return try JSONDecoder().decode(PreKeyBundleMessage.self, from: jsonData)
        case "call_control":
            return try JSONDecoder().decode(CallControlMessage.self, from: jsonData)
        case "audio_data":
            return try JSONDecoder().decode(AudioDataMessage.self, from: jsonData)
        case "video_data":
            return try JSONDecoder().decode(VideoDataMessage.self, from: jsonData)
        case "file_transfer":
            return try JSONDecoder().decode(FileTransferMessage.self, from: jsonData)
        case "group_notification":
            return try JSONDecoder().decode(GroupNotificationMessage.self, from: jsonData)
        case "delivery_receipt":
            return try JSONDecoder().decode(DeliveryReceiptMessage.self, from: jsonData)
        default:
            throw SignalMessageError.unknownMessageType
        }
    }

    /// SignalMessage'ı JSON string'e encode eder
    public static func encodeMessage(_ message: SignalMessageProtocol) throws -> String {
        let jsonData: Data

        switch message {
        case let msg as SdpOfferMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as SdpAnswerMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as IceCandidateMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as EncryptedMessageSignal:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as PreKeyBundleMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as CallControlMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as AudioDataMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as VideoDataMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as FileTransferMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as GroupNotificationMessage:
            jsonData = try JSONEncoder().encode(msg)
        case let msg as DeliveryReceiptMessage:
            jsonData = try JSONEncoder().encode(msg)
        default:
            throw SignalMessageError.unknownMessageType
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SignalMessageError.encodingFailed
        }

        return jsonString
    }
}

// MARK: - Supporting Types

/// MessageType field'ını okumak için kullanılan container
private struct MessageTypeContainer: Codable {
    let messageType: String
}

/// SignalMessage hataları
public enum SignalMessageError: Error {
    case invalidJSON
    case unknownMessageType
    case encodingFailed
}