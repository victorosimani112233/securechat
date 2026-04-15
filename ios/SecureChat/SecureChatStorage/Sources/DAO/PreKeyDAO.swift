import Foundation
import CoreData

/// PreKey veri erişim nesnesi.
/// One-time PreKey'ler için CRUD operasyonları.
/// Signal Protocol tarafından kullanılır.
public class PreKeyDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// ID ile PreKey getir
    public func get(id: Int32) async throws -> Data? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            request.predicate = NSPredicate(format: "id == %d", id)
            request.fetchLimit = 1

            let preKeys = try context.fetch(request)
            return preKeys.first?.record
        }
    }

    /// PreKey ekle/güncelle
    public func insert(id: Int32, record: Data) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut PreKey'i kontrol et
            let fetchRequest: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %d", id)

            let existingPreKeys = try context.fetch(fetchRequest)
            let preKey = existingPreKeys.first ?? PreKey(context: context)

            // PreKey verilerini ayarla
            preKey.id = id
            preKey.record = record

            try context.save()
        }
    }

    /// Birden çok PreKey ekle (batch insert)
    public func insertBatch(_ preKeys: [(id: Int32, record: Data)]) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            for (id, record) in preKeys {
                // Mevcut PreKey'i kontrol et
                let fetchRequest: NSFetchRequest<PreKey> = PreKey.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %d", id)

                let existingPreKeys = try context.fetch(fetchRequest)
                let preKey = existingPreKeys.first ?? PreKey(context: context)

                preKey.id = id
                preKey.record = record
            }

            try context.save()
        }
    }

    /// PreKey sil
    public func delete(id: Int32) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            request.predicate = NSPredicate(format: "id == %d", id)

            let preKeys = try context.fetch(request)
            preKeys.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Toplam PreKey sayısı
    public func count() async throws -> Int {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            return try context.count(for: request)
        }
    }

    /// En yüksek PreKey ID'si
    public func maxId() async throws -> Int32? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PreKey.id, ascending: false)]
            request.fetchLimit = 1

            let preKeys = try context.fetch(request)
            return preKeys.first?.id
        }
    }

    /// Mevcut tüm PreKey ID'leri
    public func getAllIds() async throws -> [Int32] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PreKey.id, ascending: true)]

            let preKeys = try context.fetch(request)
            return preKeys.map { $0.id }
        }
    }

    /// Belirli sayıda PreKey sil (en eski önce)
    public func deleteOldest(count: Int) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PreKey.id, ascending: true)]
            request.fetchLimit = count

            let preKeysToDelete = try context.fetch(request)
            preKeysToDelete.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Tüm PreKey'leri sil
    public func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = PreKey.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }

    /// Random PreKey al (Signal Protocol için)
    public func getRandomPreKey() async throws -> (id: Int32, record: Data)? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<PreKey> = PreKey.fetchRequest()
            let count = try context.count(for: request)

            guard count > 0 else { return nil }

            // Random offset ile PreKey seç
            let randomOffset = Int.random(in: 0..<count)
            request.fetchOffset = randomOffset
            request.fetchLimit = 1

            let preKeys = try context.fetch(request)
            guard let preKey = preKeys.first else { return nil }

            return (id: preKey.id, record: preKey.record ?? Data())
        }
    }

    /// Kullanılabilir PreKey olup olmadığını kontrol et
    public func hasAvailablePreKeys() async throws -> Bool {
        let count = try await count()
        return count > 0
    }

    /// PreKey stok durumu (minimum 10 olmalı)
    public func needsPreKeyGeneration(minimumCount: Int = 10) async throws -> Bool {
        let count = try await count()
        return count < minimumCount
    }
}