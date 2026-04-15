import Foundation
import CoreData
import Combine

/// Rehber kişisi veri erişim nesnesi.
/// Telefon numarası hash'i ile eşleştirme işlemleri.
public class ContactDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// Tüm kayıtlı kişileri getirir
    public func getAll() -> AnyPublisher<[Contact], Never> {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.displayName, ascending: true)]

        return createPublisher(for: request)
    }

    /// Kayıtlı kullanıcıları getirir (SecureChat'e kayıt olmuş)
    public func getRegisteredContacts() -> AnyPublisher<[Contact], Never> {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        request.predicate = NSPredicate(format: "isRegistered == YES")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.displayName, ascending: true)]

        return createPublisher(for: request)
    }

    /// Telefon numarası ile kişi bul
    public func getByPhoneNumber(_ phoneNumber: String) async throws -> ContactData? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Contact> = Contact.fetchRequest()
            request.predicate = NSPredicate(format: "phoneNumber == %@", phoneNumber)
            request.fetchLimit = 1

            let contacts = try context.fetch(request)
            return contacts.first?.toData()
        }
    }

    /// Telefon hash'i ile kişi bul
    public func getByPhoneHash(_ phoneHash: String) async throws -> ContactData? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Contact> = Contact.fetchRequest()
            request.predicate = NSPredicate(format: "phoneHash == %@", phoneHash)
            request.fetchLimit = 1

            let contacts = try context.fetch(request)
            return contacts.first?.toData()
        }
    }

    /// ID ile kişi bul
    public func getById(_ id: String) async throws -> ContactData? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Contact> = Contact.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            let contacts = try context.fetch(request)
            return contacts.first?.toData()
        }
    }

    /// Kişi ekle/güncelle
    public func insert(_ contactData: ContactData) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut kişiyi kontrol et
            let fetchRequest: NSFetchRequest<Contact> = Contact.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", contactData.id)

            let existingContacts = try context.fetch(fetchRequest)
            let contact = existingContacts.first ?? Contact(context: context)

            // Kişi verilerini ayarla
            contact.id = contactData.id
            contact.phoneNumber = contactData.phoneNumber
            contact.phoneHash = contactData.phoneHash
            contact.displayName = contactData.displayName
            contact.isRegistered = contactData.isRegistered
            contact.avatarURI = contactData.avatarUri
            contact.lastSeen = contactData.lastSeen ?? 0

            try context.save()
        }
    }

    /// Birden çok kişi ekle (batch insert)
    public func insertBatch(_ contacts: [ContactData]) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            for contactData in contacts {
                // Mevcut kişiyi kontrol et
                let fetchRequest: NSFetchRequest<Contact> = Contact.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", contactData.id)

                let existingContacts = try context.fetch(fetchRequest)
                let contact = existingContacts.first ?? Contact(context: context)

                // Kişi verilerini ayarla
                contact.id = contactData.id
                contact.phoneNumber = contactData.phoneNumber
                contact.phoneHash = contactData.phoneHash
                contact.displayName = contactData.displayName
                contact.isRegistered = contactData.isRegistered
                contact.avatarURI = contactData.avatarUri
                contact.lastSeen = contactData.lastSeen ?? 0
            }

            try context.save()
        }
    }

    /// Kişi kayıt durumunu güncelle
    public func updateRegistrationStatus(phoneHash: String, isRegistered: Bool) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Contact> = Contact.fetchRequest()
            request.predicate = NSPredicate(format: "phoneHash == %@", phoneHash)

            let contacts = try context.fetch(request)
            contacts.forEach { contact in
                contact.isRegistered = isRegistered
            }

            try context.save()
        }
    }

    /// Son görülme zamanını güncelle
    public func updateLastSeen(contactId: String, lastSeen: Int64) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Contact> = Contact.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", contactId)

            let contacts = try context.fetch(request)
            contacts.forEach { contact in
                contact.lastSeen = lastSeen
            }

            try context.save()
        }
    }

    /// Kişi sil
    public func delete(contactId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Contact> = Contact.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", contactId)

            let contacts = try context.fetch(request)
            contacts.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Tüm kişileri sil (rehber sync öncesi temizlik)
    public func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = Contact.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }

    /// Telefon hash'i listesine göre kayıtlı kullanıcıları bul
    public func findRegisteredUsers(phoneHashes: [String]) async throws -> [ContactData] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Contact> = Contact.fetchRequest()
            request.predicate = NSPredicate(format: "phoneHash IN %@ AND isRegistered == YES", phoneHashes)

            let contacts = try context.fetch(request)
            return contacts.map { $0.toData() }
        }
    }

    /// Arama sorgusu (isim veya telefon ile)
    public func search(query: String) -> AnyPublisher<[Contact], Never> {
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        request.predicate = NSPredicate(format: "displayName CONTAINS[c] %@ OR phoneNumber CONTAINS %@",
                                        query, query)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.displayName, ascending: true)]

        return createPublisher(for: request)
    }

    // MARK: - Private Methods

    /// NSFetchRequest için Publisher oluştur
    private func createPublisher(for request: NSFetchRequest<Contact>) -> AnyPublisher<[Contact], Never> {
        let context = coreDataManager.viewContext

        return NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .map { _ in }
            .prepend(())
            .map { _ in
                do {
                    return try context.fetch(request)
                } catch {
                    print("SecureChat: Contact fetch failed: \(error)")
                    return []
                }
            }
            .removeDuplicates { oldContacts, newContacts in
                return oldContacts.count == newContacts.count
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - ContactData Transfer Object

/// Kişi veri transfer nesnesi - Core Data'dan bağımsız
public struct ContactData {
    public let id: String
    public let phoneNumber: String
    public let phoneHash: String
    public let displayName: String
    public let isRegistered: Bool
    public let avatarUri: String?
    public let lastSeen: Int64?

    public init(
        id: String,
        phoneNumber: String,
        phoneHash: String,
        displayName: String,
        isRegistered: Bool,
        avatarUri: String? = nil,
        lastSeen: Int64? = nil
    ) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.phoneHash = phoneHash
        self.displayName = displayName
        self.isRegistered = isRegistered
        self.avatarUri = avatarUri
        self.lastSeen = lastSeen
    }
}

// MARK: - Core Data Extensions

extension Contact {
    /// Core Data nesnesini transfer nesnesine dönüştür
    func toData() -> ContactData {
        return ContactData(
            id: id ?? "",
            phoneNumber: phoneNumber ?? "",
            phoneHash: phoneHash ?? "",
            displayName: displayName ?? "",
            isRegistered: isRegistered,
            avatarUri: avatarURI,
            lastSeen: lastSeen != 0 ? lastSeen : nil
        )
    }
}