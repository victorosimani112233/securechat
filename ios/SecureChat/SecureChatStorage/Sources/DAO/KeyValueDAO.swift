import Foundation
import CoreData

/// Key-Value veri erişim nesnesi.
/// Uygulama ayarları ve genel anahtar-değer çiftleri için.
public class KeyValueDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// Key ile value getir
    public func get(key: String) async throws -> String? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1

            let keyValues = try context.fetch(request)
            return keyValues.first?.value
        }
    }

    /// Key-Value ekle/güncelle
    public func set(key: String, value: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut key-value'yu kontrol et
            let fetchRequest: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "key == %@", key)

            let existingKeyValues = try context.fetch(fetchRequest)
            let keyValue = existingKeyValues.first ?? KeyValue(context: context)

            // Key-Value verilerini ayarla
            keyValue.key = key
            keyValue.value = value

            try context.save()
        }
    }

    /// Key sil
    public func delete(key: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)

            let keyValues = try context.fetch(request)
            keyValues.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Key var mı kontrol et
    public func exists(key: String) async throws -> Bool {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@", key)
            request.fetchLimit = 1

            let count = try context.count(for: request)
            return count > 0
        }
    }

    /// Tüm key-value çiftlerini getir
    public func getAll() async throws -> [String: String] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            let keyValues = try context.fetch(request)

            var result: [String: String] = [:]
            for keyValue in keyValues {
                if let key = keyValue.key, let value = keyValue.value {
                    result[key] = value
                }
            }

            return result
        }
    }

    /// Prefix ile başlayan key'leri getir
    public func getByPrefix(_ prefix: String) async throws -> [String: String] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "key BEGINSWITH %@", prefix)

            let keyValues = try context.fetch(request)
            var result: [String: String] = [:]

            for keyValue in keyValues {
                if let key = keyValue.key, let value = keyValue.value {
                    result[key] = value
                }
            }

            return result
        }
    }

    /// Batch set (birden çok key-value)
    public func setBatch(_ keyValues: [String: String]) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            for (key, value) in keyValues {
                // Mevcut key-value'yu kontrol et
                let fetchRequest: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "key == %@", key)

                let existingKeyValues = try context.fetch(fetchRequest)
                let keyValue = existingKeyValues.first ?? KeyValue(context: context)

                keyValue.key = key
                keyValue.value = value
            }

            try context.save()
        }
    }

    /// Prefix ile başlayan key'leri sil
    public func deleteByPrefix(_ prefix: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "key BEGINSWITH %@", prefix)

            let keyValues = try context.fetch(request)
            keyValues.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Toplam key sayısı
    public func count() async throws -> Int {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<KeyValue> = KeyValue.fetchRequest()
            return try context.count(for: request)
        }
    }

    /// Tüm key-value'ları sil
    public func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = KeyValue.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }

    // MARK: - Convenience Methods (Common Settings)

    /// Bool değer set et
    public func setBool(key: String, value: Bool) async throws {
        try await set(key: key, value: value.description)
    }

    /// Bool değer getir
    public func getBool(key: String, defaultValue: Bool = false) async throws -> Bool {
        if let stringValue = try await get(key: key) {
            return Bool(stringValue) ?? defaultValue
        }
        return defaultValue
    }

    /// Int değer set et
    public func setInt(key: String, value: Int) async throws {
        try await set(key: key, value: value.description)
    }

    /// Int değer getir
    public func getInt(key: String, defaultValue: Int = 0) async throws -> Int {
        if let stringValue = try await get(key: key) {
            return Int(stringValue) ?? defaultValue
        }
        return defaultValue
    }

    /// Double değer set et
    public func setDouble(key: String, value: Double) async throws {
        try await set(key: key, value: value.description)
    }

    /// Double değer getir
    public func getDouble(key: String, defaultValue: Double = 0.0) async throws -> Double {
        if let stringValue = try await get(key: key) {
            return Double(stringValue) ?? defaultValue
        }
        return defaultValue
    }

    /// Date değer set et (timestamp olarak)
    public func setDate(key: String, value: Date) async throws {
        let timestamp = Int64(value.timeIntervalSince1970 * 1000)
        try await set(key: key, value: timestamp.description)
    }

    /// Date değer getir
    public func getDate(key: String) async throws -> Date? {
        if let stringValue = try await get(key: key),
           let timestamp = Int64(stringValue) {
            return Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        }
        return nil
    }
}

// MARK: - Common Settings Keys

public extension KeyValueDAO {
    /// Uygulama ayarları için standart key'ler
    enum SettingsKey {
        static let userId = "user_id"
        static let userPhone = "user_phone"
        static let registrationCompleted = "registration_completed"
        static let lastBackupDate = "last_backup_date"
        static let messageRetentionDays = "message_retention_days"
        static let autoDeleteMessages = "auto_delete_messages"
        static let notificationsEnabled = "notifications_enabled"
        static let darkModeEnabled = "dark_mode_enabled"
        static let lastSyncTimestamp = "last_sync_timestamp"
        static let preKeyLastGeneratedAt = "prekey_last_generated_at"
        static let signedPreKeyLastRotatedAt = "signed_prekey_last_rotated_at"
    }

    /// User ID getir
    func getUserId() async throws -> String? {
        return try await get(key: SettingsKey.userId)
    }

    /// User ID set et
    func setUserId(_ userId: String) async throws {
        try await set(key: SettingsKey.userId, value: userId)
    }

    /// Kayıt tamamlandı mı kontrol et
    func isRegistrationCompleted() async throws -> Bool {
        return try await getBool(key: SettingsKey.registrationCompleted)
    }

    /// Kayıt tamamlandı olarak işaretle
    func setRegistrationCompleted(_ completed: Bool) async throws {
        try await setBool(key: SettingsKey.registrationCompleted, value: completed)
    }
}