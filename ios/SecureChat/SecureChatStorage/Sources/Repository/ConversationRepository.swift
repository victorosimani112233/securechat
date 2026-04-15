import Foundation
import Combine

/// Konuşma repository protokolü.
/// Domain layer ile storage layer arasında interface sağlar.
public protocol ConversationRepository {
    func getConversations() -> AnyPublisher<[ConversationModel], Never>
    func getConversation(peerId: String) async throws -> ConversationModel?
    func createConversation(_ conversation: ConversationModel) async throws
    func updateConversation(_ conversation: ConversationModel) async throws
    func deleteConversation(conversationId: String) async throws
    func markAsRead(conversationId: String) async throws
    func setPinned(conversationId: String, isPinned: Bool) async throws
    func setMuted(conversationId: String, isMuted: Bool) async throws
}

/// Konuşma repository implementasyonu.
public class ConversationRepositoryImpl: ConversationRepository {

    // MARK: - Properties

    private let conversationDAO: ConversationDAO

    // MARK: - Initialization

    public init(conversationDAO: ConversationDAO = ConversationDAO()) {
        self.conversationDAO = conversationDAO
    }

    // MARK: - ConversationRepository Implementation

    /// Tüm konuşmaları getirir
    public func getConversations() -> AnyPublisher<[ConversationModel], Never> {
        return conversationDAO.getAll()
            .map { entities in
                entities.map { $0.toConversationModel() }
            }
            .eraseToAnyPublisher()
    }

    /// Peer ID ile konuşma getirir
    public func getConversation(peerId: String) async throws -> ConversationModel? {
        if let conversationData = try await conversationDAO.getByPeerId(peerId) {
            return conversationData.toConversationModel()
        }
        return nil
    }

    /// Yeni konuşma oluştur
    public func createConversation(_ conversation: ConversationModel) async throws {
        let conversationData = conversation.toConversationData()
        try await conversationDAO.insert(conversationData)
    }

    /// Konuşma güncelle
    public func updateConversation(_ conversation: ConversationModel) async throws {
        let conversationData = conversation.toConversationData()
        try await conversationDAO.insert(conversationData)
    }

    /// Konuşma sil
    public func deleteConversation(conversationId: String) async throws {
        try await conversationDAO.deleteWithMessages(conversationId: conversationId)
    }

    /// Konuşmayı okundu olarak işaretle
    public func markAsRead(conversationId: String) async throws {
        try await conversationDAO.markAsRead(conversationId: conversationId)
    }

    /// Konuşma pin durumunu değiştir
    public func setPinned(conversationId: String, isPinned: Bool) async throws {
        try await conversationDAO.setPinned(conversationId: conversationId, isPinned: isPinned)
    }

    /// Konuşma mute durumunu değiştir
    public func setMuted(conversationId: String, isMuted: Bool) async throws {
        try await conversationDAO.setMuted(conversationId: conversationId, isMuted: isMuted)
    }
}

// MARK: - Domain Models

/// Konuşma domain modeli
public struct ConversationModel {
    public let id: String
    public let peerId: String
    public let peerName: String
    public let peerPhone: String
    public let lastMessage: String?
    public let lastMessageTimestamp: Int64?
    public let unreadCount: Int
    public let isMuted: Bool
    public let isPinned: Bool
    public let isGroup: Bool
    public let groupMembers: [String]

    public init(
        id: String,
        peerId: String,
        peerName: String,
        peerPhone: String,
        lastMessage: String? = nil,
        lastMessageTimestamp: Int64? = nil,
        unreadCount: Int = 0,
        isMuted: Bool = false,
        isPinned: Bool = false,
        isGroup: Bool = false,
        groupMembers: [String] = []
    ) {
        self.id = id
        self.peerId = peerId
        self.peerName = peerName
        self.peerPhone = peerPhone
        self.lastMessage = lastMessage
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCount = unreadCount
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.isGroup = isGroup
        self.groupMembers = groupMembers
    }

    /// Domain modeli ConversationData'ya dönüştür
    func toConversationData() -> ConversationData {
        return ConversationData(
            id: id,
            peerId: peerId,
            peerName: peerName,
            peerPhone: peerPhone,
            lastMessage: lastMessage,
            lastMessageTimestamp: lastMessageTimestamp,
            unreadCount: unreadCount,
            isMuted: isMuted,
            isPinned: isPinned,
            isGroup: isGroup,
            groupMembers: groupMembers.joined(separator: ",")
        )
    }

    /// Son mesaj zamanı Date olarak
    public var lastMessageDate: Date? {
        guard let timestamp = lastMessageTimestamp else { return nil }
        return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }

    /// Konuşma preview metni
    public var previewText: String {
        if let lastMessage = lastMessage, !lastMessage.isEmpty {
            return lastMessage
        }
        return isGroup ? "Grup konuşması" : "Henüz mesaj yok"
    }

    /// Okunmamış badge gösterilsin mi
    public var shouldShowBadge: Bool {
        return unreadCount > 0 && !isMuted
    }
}

// MARK: - Data Transfer Extensions

extension ConversationData {
    /// ConversationData'yı domain modeline dönüştür
    func toConversationModel() -> ConversationModel {
        let members: [String]
        if let groupMembersString = groupMembers, !groupMembersString.isEmpty {
            members = groupMembersString.components(separatedBy: ",")
        } else {
            members = []
        }

        return ConversationModel(
            id: id,
            peerId: peerId,
            peerName: peerName,
            peerPhone: peerPhone,
            lastMessage: lastMessage,
            lastMessageTimestamp: lastMessageTimestamp,
            unreadCount: unreadCount,
            isMuted: isMuted,
            isPinned: isPinned,
            isGroup: isGroup,
            groupMembers: members
        )
    }
}

extension Conversation {
    /// Core Data nesnesini domain modeline dönüştür
    func toConversationModel() -> ConversationModel {
        let members: [String]
        if let groupMembersString = groupMembers, !groupMembersString.isEmpty {
            members = groupMembersString.components(separatedBy: ",")
        } else {
            members = []
        }

        return ConversationModel(
            id: id ?? "",
            peerId: peerID ?? "",
            peerName: peerName ?? "",
            peerPhone: peerPhone ?? "",
            lastMessage: lastMessage,
            lastMessageTimestamp: lastMessageTimestamp != 0 ? lastMessageTimestamp : nil,
            unreadCount: Int(unreadCount),
            isMuted: isMuted,
            isPinned: isPinned,
            isGroup: isGroup,
            groupMembers: members
        )
    }
}