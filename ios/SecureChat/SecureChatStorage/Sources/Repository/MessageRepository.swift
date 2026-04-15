import Foundation
import Combine

/// Mesaj repository protokolü.
/// Domain layer ile storage layer arasında interface sağlar.
public protocol MessageRepository {
    func saveMessage(_ message: LocalMessage) async throws
    func getMessages(conversationId: String) -> AnyPublisher<[LocalMessage], Never>
    func getRecentMessages(conversationId: String, limit: Int) -> AnyPublisher<[LocalMessage], Never>
    func updateMessageStatus(messageId: String, status: MessageStatus) async throws
    func deleteMessage(messageId: String) async throws
    func deleteConversation(conversationId: String) async throws
    func getUnreadCount(conversationId: String) -> AnyPublisher<Int, Never>
    func markConversationAsRead(conversationId: String) async throws
    func deleteOldMessages(retentionDays: Int) async throws
}

/// Mesaj repository implementasyonu.
/// MessageDAO ve ConversationDAO'yu kullanarak mesaj işlemlerini yönetir.
public class MessageRepositoryImpl: MessageRepository {

    // MARK: - Properties

    private let messageDAO: MessageDAO
    private let conversationDAO: ConversationDAO

    // MARK: - Initialization

    public init(
        messageDAO: MessageDAO = MessageDAO(),
        conversationDAO: ConversationDAO = ConversationDAO()
    ) {
        self.messageDAO = messageDAO
        self.conversationDAO = conversationDAO
    }

    // MARK: - MessageRepository Implementation

    /// Mesaj kaydet ve konuşmayı güncelle
    public func saveMessage(_ message: LocalMessage) async throws {
        // Mesajı kaydet
        let messageData = message.toMessageData()
        try await messageDAO.insert(messageData)

        // Konuşmanın son mesajını güncelle
        if let conversation = try await conversationDAO.getByPeerId(message.peerId) {
            let updatedConversation = ConversationData(
                id: conversation.id,
                peerId: conversation.peerId,
                peerName: conversation.peerName,
                peerPhone: conversation.peerPhone,
                lastMessage: message.content,
                lastMessageTimestamp: message.timestamp,
                unreadCount: message.isOutgoing ? conversation.unreadCount : conversation.unreadCount + 1,
                isMuted: conversation.isMuted,
                isPinned: conversation.isPinned,
                isGroup: conversation.isGroup,
                groupMembers: conversation.groupMembers
            )

            try await conversationDAO.insert(updatedConversation)
        } else {
            // Yeni konuşma oluştur
            let newConversation = ConversationData(
                id: message.conversationId,
                peerId: message.peerId,
                peerName: message.peerName ?? message.peerId,
                peerPhone: message.peerPhone ?? "",
                lastMessage: message.content,
                lastMessageTimestamp: message.timestamp,
                unreadCount: message.isOutgoing ? 0 : 1
            )

            try await conversationDAO.insert(newConversation)
        }
    }

    /// Konuşmadaki mesajları getirir
    public func getMessages(conversationId: String) -> AnyPublisher<[LocalMessage], Never> {
        return messageDAO.getMessages(conversationId: conversationId)
            .map { entities in
                entities.map { $0.toLocalMessage() }
            }
            .eraseToAnyPublisher()
    }

    /// Son N mesajı getirir
    public func getRecentMessages(conversationId: String, limit: Int) -> AnyPublisher<[LocalMessage], Never> {
        return messageDAO.getRecentMessages(conversationId: conversationId, limit: limit)
            .map { entities in
                entities.map { $0.toLocalMessage() }
            }
            .eraseToAnyPublisher()
    }

    /// Mesaj durumunu güncelle
    public func updateMessageStatus(messageId: String, status: MessageStatus) async throws {
        try await messageDAO.updateStatus(messageId: messageId, status: status)
    }

    /// Mesaj sil
    public func deleteMessage(messageId: String) async throws {
        try await messageDAO.delete(messageId: messageId)
    }

    /// Konuşmayı ve mesajlarını sil
    public func deleteConversation(conversationId: String) async throws {
        try await messageDAO.deleteByConversation(conversationId: conversationId)
        try await conversationDAO.delete(conversationId: conversationId)
    }

    /// Okunmamış mesaj sayısı
    public func getUnreadCount(conversationId: String) -> AnyPublisher<Int, Never> {
        return messageDAO.getUnreadCount(conversationId: conversationId)
    }

    /// Konuşmayı okundu olarak işaretle
    public func markConversationAsRead(conversationId: String) async throws {
        try await conversationDAO.markAsRead(conversationId: conversationId)
    }

    /// Eski mesajları sil (retention policy)
    public func deleteOldMessages(retentionDays: Int) async throws {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(retentionDays * 24 * 60 * 60 * 1000)
        try await messageDAO.deleteOlderThan(cutoff: cutoff)
    }
}

// MARK: - Domain Models

/// Local mesaj domain modeli
public struct LocalMessage {
    public let id: String
    public let conversationId: String
    public let peerId: String
    public let peerName: String?
    public let peerPhone: String?
    public let senderId: String
    public let content: String
    public let contentType: MessageContentType
    public let timestamp: Int64
    public let status: MessageStatus
    public let replyToId: String?
    public let isOutgoing: Bool

    public init(
        id: String,
        conversationId: String,
        peerId: String,
        peerName: String? = nil,
        peerPhone: String? = nil,
        senderId: String,
        content: String,
        contentType: MessageContentType,
        timestamp: Int64,
        status: MessageStatus,
        replyToId: String? = nil,
        isOutgoing: Bool
    ) {
        self.id = id
        self.conversationId = conversationId
        self.peerId = peerId
        self.peerName = peerName
        self.peerPhone = peerPhone
        self.senderId = senderId
        self.content = content
        self.contentType = contentType
        self.timestamp = timestamp
        self.status = status
        self.replyToId = replyToId
        self.isOutgoing = isOutgoing
    }

    /// Domain modeli MessageData'ya dönüştür
    func toMessageData() -> MessageData {
        return MessageData(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            contentType: contentType,
            timestamp: timestamp,
            status: status,
            replyToId: replyToId,
            isOutgoing: isOutgoing
        )
    }
}

// MARK: - Core Data Extensions

extension Message {
    /// Core Data nesnesini domain modeline dönüştür
    func toLocalMessage() -> LocalMessage {
        return LocalMessage(
            id: id ?? "",
            conversationId: conversationID ?? "",
            peerId: "", // Conversation'dan alınmalı
            senderId: senderID ?? "",
            content: content ?? "",
            contentType: MessageContentType(rawValue: contentType ?? "") ?? .text,
            timestamp: timestamp,
            status: MessageStatus(rawValue: status ?? "") ?? .sending,
            replyToId: replyToID,
            isOutgoing: isOutgoing
        )
    }
}