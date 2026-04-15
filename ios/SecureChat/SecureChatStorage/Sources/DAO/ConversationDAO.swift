import Foundation
import CoreData
import Combine

/// Konuşma veri erişim nesnesi. Konuşma listesi ve CRUD işlemleri.
public class ConversationDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// Tüm konuşmaları getirir (pinned → son mesaj tarihine göre sıralı)
    public func getAll() -> AnyPublisher<[Conversation], Never> {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Conversation.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \Conversation.lastMessageTimestamp, ascending: false)
        ]

        return createPublisher(for: request)
    }

    /// Peer ID ile konuşma bul
    public func getByPeerId(_ peerId: String) async throws -> ConversationData? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "peerID == %@", peerId)
            request.fetchLimit = 1

            let conversations = try context.fetch(request)
            return conversations.first?.toData()
        }
    }

    /// Konuşma ekle/güncelle
    public func insert(_ conversationData: ConversationData) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut konuşmayı kontrol et
            let fetchRequest: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", conversationData.id)

            let existingConversations = try context.fetch(fetchRequest)
            let conversation = existingConversations.first ?? Conversation(context: context)

            // Konuşma verilerini ayarla
            conversation.id = conversationData.id
            conversation.peerID = conversationData.peerId
            conversation.peerName = conversationData.peerName
            conversation.peerPhone = conversationData.peerPhone
            conversation.lastMessage = conversationData.lastMessage
            conversation.lastMessageTimestamp = conversationData.lastMessageTimestamp ?? 0
            conversation.unreadCount = Int32(conversationData.unreadCount)
            conversation.isMuted = conversationData.isMuted
            conversation.isPinned = conversationData.isPinned
            conversation.isGroup = conversationData.isGroup
            conversation.groupMembers = conversationData.groupMembers

            try context.save()
        }
    }

    /// Konuşmayı okundu olarak işaretle
    public func markAsRead(conversationId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", conversationId)

            let conversations = try context.fetch(request)
            conversations.forEach { conversation in
                conversation.unreadCount = 0
            }

            try context.save()
        }
    }

    /// Konuşma sil
    public func delete(conversationId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", conversationId)

            let conversations = try context.fetch(request)
            conversations.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Konuşmayı mesajları ile birlikte sil (cascade delete)
    public func deleteWithMessages(conversationId: String) async throws {
        // Konuşma silindiğinde Core Data cascade delete ile mesajları otomatik siler
        try await delete(conversationId: conversationId)
    }

    /// Konuşma pin durumunu değiştir
    public func setPinned(conversationId: String, isPinned: Bool) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", conversationId)

            let conversations = try context.fetch(request)
            conversations.forEach { conversation in
                conversation.isPinned = isPinned
            }

            try context.save()
        }
    }

    /// Konuşma mute durumunu değiştir
    public func setMuted(conversationId: String, isMuted: Bool) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", conversationId)

            let conversations = try context.fetch(request)
            conversations.forEach { conversation in
                conversation.isMuted = isMuted
            }

            try context.save()
        }
    }

    /// Son mesaj ve timestamp güncelle
    public func updateLastMessage(conversationId: String, message: String, timestamp: Int64) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", conversationId)

            let conversations = try context.fetch(request)
            conversations.forEach { conversation in
                conversation.lastMessage = message
                conversation.lastMessageTimestamp = timestamp
            }

            try context.save()
        }
    }

    /// Okunmamış mesaj sayısını artır
    public func incrementUnreadCount(conversationId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", conversationId)

            let conversations = try context.fetch(request)
            conversations.forEach { conversation in
                conversation.unreadCount += 1
            }

            try context.save()
        }
    }

    // MARK: - Private Methods

    /// NSFetchRequest için Publisher oluştur
    private func createPublisher(for request: NSFetchRequest<Conversation>) -> AnyPublisher<[Conversation], Never> {
        let context = coreDataManager.viewContext

        return NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .map { _ in }
            .prepend(())
            .map { _ in
                do {
                    return try context.fetch(request)
                } catch {
                    print("SecureChat: Conversation fetch failed: \(error)")
                    return []
                }
            }
            .removeDuplicates { oldConversations, newConversations in
                return oldConversations.count == newConversations.count
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - ConversationData Transfer Object

/// Konuşma veri transfer nesnesi - Core Data'dan bağımsız
public struct ConversationData {
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
    public let groupMembers: String?

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
        groupMembers: String? = nil
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
}

// MARK: - Core Data Extensions

extension Conversation {
    /// Core Data nesnesini transfer nesnesine dönüştür
    func toData() -> ConversationData {
        return ConversationData(
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
            groupMembers: groupMembers
        )
    }
}