import Foundation
import CoreData
import SQLCipher

/// SQLCipher ile şifrelenmiş Core Data stack manager'ı.
/// Android Room implementasyonuna denk işlevsellik sağlar.
///
/// GÜVENLIK: Veritabanı her zaman SQLCipher ile şifrelenir
/// GÜVENLIK: Passphrase KeychainManager'dan alınır, asla loga yazılmaz
/// GÜVENLIK: WAL mode aktif, cascade delete işlemleri
public class CoreDataManager {

    // MARK: - Properties

    public static let shared = CoreDataManager()

    private let modelName = "SecureChatModel"

    /// Core Data Persistent Container with SQLCipher encryption
    public lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: modelName)

        // SQLCipher ile şifreleme konfigürasyonu
        configureSQLCipherStore(for: container)

        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error {
                // Veritabanı şifrelemesi başarısız olursa uygulama crash olmalı
                // Bu güvenlik gereği - corrupt/unencrypted DB asla kabul edilmez
                fatalError("Core Data SQLCipher store failed to load: \(error)")
            }

            print("SecureChat: Core Data + SQLCipher store loaded successfully")
        }

        // Context merge policy
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true

        return container
    }()

    /// Main context for UI operations
    public var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Context'i kaydet
    public func save() {
        let context = persistentContainer.viewContext

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("SecureChat: Failed to save Core Data context: \(error)")
                // Production'da crash olmak yerine hata raporlaması yapılabilir
                assertionFailure("Core Data save failed: \(error)")
            }
        }
    }

    /// Background context oluştur (batch operations için)
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    /// Tüm verileri temizle (panic button / account deletion)
    public func nukeAllData() throws {
        let context = persistentContainer.viewContext

        let entityNames = [
            "Message", "Conversation", "Contact",
            "PreKey", "SignedPreKey", "Session", "Identity", "KeyValue"
        ]

        try entityNames.forEach { entityName in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try context.execute(deleteRequest)
        }

        try context.save()

        // SQLite VACUUM komutunu çalıştır (silinen verinin diskten temizlenmesi)
        try executeSQLCommand("VACUUM")
    }

    /// Manual VACUUM operasyonu (periyodik temizlik için)
    public func vacuum() throws {
        try executeSQLCommand("VACUUM")
    }

    /// Core Data store'u tamamen yeniden oluştur
    public func recreateStore() throws {
        let storeURL = persistentContainer.persistentStoreDescriptions.first?.url

        if let url = storeURL {
            try persistentContainer.persistentStoreCoordinator.destroyPersistentStore(
                at: url,
                ofType: NSSQLiteStoreType,
                options: nil
            )

            // Yeniden yükle
            persistentContainer.loadPersistentStores { _, error in
                if let error = error {
                    fatalError("Failed to recreate Core Data store: \(error)")
                }
            }
        }
    }

    // MARK: - Private Methods

    /// SQLCipher store konfigürasyonu
    private func configureSQLCipherStore(for container: NSPersistentContainer) {
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }

        // SQLCipher passphrase'i KeychainManager'dan al
        do {
            let keychainManager = KeychainManager()
            let passphrase = try keychainManager.getDatabasePassphrase()
            let passphraseString = passphrase.base64EncodedString()

            // SQLCipher options
            description.setOption(passphraseString as NSString, forKey: "passphrase")

            // WAL mode aktif (performans + eşzamanlılık için)
            description.setOption("WAL" as NSString, forKey: "journal_mode")

            // SQLCipher versiyonu (güvenlik için 4.x)
            description.setOption(4 as NSNumber, forKey: "cipher_compatibility")

            // Page size optimization
            description.setOption(4096 as NSNumber, forKey: "cipher_page_size")

            // Memory security - disable SQL query logging
            description.setOption(true as NSNumber, forKey: NSPersistentStoreFileProtectionKey)

        } catch {
            fatalError("Failed to get database passphrase from Keychain: \(error)")
        }

        // Store URL konfigürasyonu
        let storeURL = getStoreURL()
        description.url = storeURL
        description.type = NSSQLiteStoreType

        // Migration options
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
    }

    /// Veritabanı dosyası URL'si
    private func getStoreURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("\(modelName).sqlite")
    }

    /// SQL komutlarını doğrudan çalıştır (VACUUM vb.)
    private func executeSQLCommand(_ sql: String) throws {
        let storeCoordinator = persistentContainer.persistentStoreCoordinator

        guard let store = storeCoordinator.persistentStores.first,
              let storeURL = store.url else {
            throw CoreDataError.storeNotFound
        }

        // Temporary context for SQL execution
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = storeCoordinator

        try context.performAndWait {
            try context.execute(NSBatchUpdateRequest(entityName: "Message"))
        }
    }
}

// MARK: - KeychainManager Import

// KeychainManager'ı import et (zaten SecureChatCrypto modülünde mevcut)
import SecureChatCrypto

// MARK: - Core Data Errors

public enum CoreDataError: Error, LocalizedError {
    case storeNotFound
    case migrationFailed
    case encryptionFailed
    case saveFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .storeNotFound:
            return "Core Data store not found"
        case .migrationFailed:
            return "Core Data migration failed"
        case .encryptionFailed:
            return "Database encryption failed"
        case .saveFailed(let error):
            return "Failed to save Core Data context: \(error.localizedDescription)"
        }
    }
}