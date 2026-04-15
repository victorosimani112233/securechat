import Foundation
import CoreData
import Combine

/// Mesaj veri erişim nesnesi. Tüm mesaj CRUD işlemleri bu DAO üzerinden yapılır.
/// Publisher döndüren metodlar reaktif olarak değişiklikleri yayar.
public class MessageDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// Belirli konuşmadaki mesajları getirir (timestamp'e göre sıralı)
    public func getMessages(conversationId: String) -> AnyPublisher<[Message], Never> {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "conversationID == %@", conversationId)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)]

        return createPublisher(for: request)
    }

    /// Belirli konuşmadaki son N mesajı getirir
    public func getRecentMessages(conversationId: String, limit: Int) -> AnyPublisher<[Message], Never> {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "conversationID == %@", conversationId)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Message.timestamp, ascending: false)]
        request.fetchLimit = limit

        return createPublisher(for: request)
    }

    /// Mesaj ekle/güncelle
    public func insert(_ messageData: MessageData) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut mesajı kontrol et
            let fetchRequest: NSFetchRequest<Message> = Message.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", messageData.id)

            let existingMessages = try context.fetch(fetchRequest)
            let message = existingMessages.first ?? Message(context: context)

            // Mesaj verilerini ayarla
            message.id = messageData.id
            message.conversationID = messageData.conversationId
            message.senderID = messageData.senderId
            message.content = messageData.content
            message.contentType = messageData.contentType.rawValue
            message.timestamp = messageData.timestamp
            message.status = messageData.status.rawValue
            message.replyToID = messageData.replyToId
            message.isOutgoing = messageData.isOutgoing

            try context.save()
        }
    }

    /// Mesaj durumunu güncelle
    public func updateStatus(messageId: String, status: MessageStatus) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", messageId)

            let messages = try context.fetch(request)
            messages.forEach { message in
                message.status = status.rawValue
            }

            try context.save()
        }
    }

    /// Mesaj sil
    public func delete(messageId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Message> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", messageId)

            let messages = try context.fetch(request)
            messages.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Konuşmadaki tüm mesajları sil
    public func deleteByConversation(conversationId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "conversationID == %@", conversationId)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs

            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            let changes: [AnyHashable: Any] = [
                NSDeletedObjectsKey: result?.result ?? []
            ]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes,
                                                into: [self.coreDataManager.viewContext])
        }
    }

    /// Konuşmadaki okunmamış mesaj sayısı
    public func getUnreadCount(conversationId: String) -> AnyPublisher<Int, Never> {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "conversationID == %@ AND status != %@ AND isOutgoing == NO",
                                        conversationId, MessageStatus.read.rawValue)

        return createCountPublisher(for: request)
    }

    /// Belirli tarihten eski mesajları sil (temizlik operasyonu)
    public func deleteOlderThan(cutoff: Int64) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = Message.fetchRequest()
            request.predicate = NSPredicate(format: "timestamp < %lld", cutoff)

            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }

    // MARK: - Private Methods

    /// NSFetchRequest için Publisher oluştur
    private func createPublisher<T: NSManagedObject>(for request: NSFetchRequest<T>) -> AnyPublisher<[T], Never> {
        let context = coreDataManager.viewContext

        return NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .map { _ in }
            .prepend(()) // İlk fetch için
            .map { _ in
                do {
                    return try context.fetch(request)
                } catch {
                    print("SecureChat: Message fetch failed: \(error)")
                    return []
                }
            }
            .removeDuplicates { oldMessages, newMessages in
                // Basit karşılaştırma - gerçek implementasyonda daha akıllı olmalı
                return oldMessages.count == newMessages.count
            }
            .eraseToAnyPublisher()
    }

    /// Count query için Publisher oluştur
    private func createCountPublisher(for request: NSFetchRequest<Message>) -> AnyPublisher<Int, Never> {
        let context = coreDataManager.viewContext

        return NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .map { _ in }
            .prepend(())
            .map { _ in
                do {
                    return try context.count(for: request)
                } catch {
                    print("SecureChat: Message count failed: \(error)")
                    return 0
                }
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

// MARK: - MessageData Transfer Object

/// Mesaj veri transfer nesnesi - Core Data'dan bağımsız
public struct MessageData {
    public let id: String
    public let conversationId: String
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
        self.senderId = senderId
        self.content = content
        self.contentType = contentType
        self.timestamp = timestamp
        self.status = status
        self.replyToId = replyToId
        self.isOutgoing = isOutgoing
    }
}