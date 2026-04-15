import Foundation
import CoreData

/// Signed PreKey veri erişim nesnesi.
/// İmzalanmış PreKey'ler için CRUD operasyonları.
/// Periyodik olarak rotate edilir (varsayılan 7 gün).
public class SignedPreKeyDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// ID ile Signed PreKey getir
    public func get(id: Int32) async throws -> (record: Data, createdAt: Int64)? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            request.predicate = NSPredicate(format: "id == %d", id)
            request.fetchLimit = 1

            let signedPreKeys = try context.fetch(request)
            guard let signedPreKey = signedPreKeys.first else { return nil }

            return (record: signedPreKey.record ?? Data(), createdAt: signedPreKey.createdAt)
        }
    }

    /// En güncel Signed PreKey getir
    public func getLatest() async throws -> (id: Int32, record: Data, createdAt: Int64)? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SignedPreKey.createdAt, ascending: false)]
            request.fetchLimit = 1

            let signedPreKeys = try context.fetch(request)
            guard let signedPreKey = signedPreKeys.first else { return nil }

            return (
                id: signedPreKey.id,
                record: signedPreKey.record ?? Data(),
                createdAt: signedPreKey.createdAt
            )
        }
    }

    /// Signed PreKey ekle/güncelle
    public func insert(id: Int32, record: Data, createdAt: Int64) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut Signed PreKey'i kontrol et
            let fetchRequest: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %d", id)

            let existingSignedPreKeys = try context.fetch(fetchRequest)
            let signedPreKey = existingSignedPreKeys.first ?? SignedPreKey(context: context)

            // Signed PreKey verilerini ayarla
            signedPreKey.id = id
            signedPreKey.record = record
            signedPreKey.createdAt = createdAt

            try context.save()
        }
    }

    /// Signed PreKey sil
    public func delete(id: Int32) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            request.predicate = NSPredicate(format: "id == %d", id)

            let signedPreKeys = try context.fetch(request)
            signedPreKeys.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Toplam Signed PreKey sayısı
    public func count() async throws -> Int {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            return try context.count(for: request)
        }
    }

    /// En yüksek Signed PreKey ID'si
    public func maxId() async throws -> Int32? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SignedPreKey.id, ascending: false)]
            request.fetchLimit = 1

            let signedPreKeys = try context.fetch(request)
            return signedPreKeys.first?.id
        }
    }

    /// Mevcut tüm Signed PreKey'leri getir
    public func getAll() async throws -> [(id: Int32, record: Data, createdAt: Int64)] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SignedPreKey.createdAt, ascending: false)]

            let signedPreKeys = try context.fetch(request)
            return signedPreKeys.map { signedPreKey in
                (
                    id: signedPreKey.id,
                    record: signedPreKey.record ?? Data(),
                    createdAt: signedPreKey.createdAt
                )
            }
        }
    }

    /// Eski Signed PreKey'leri sil (rotation için)
    public func deleteOlderThan(timestamp: Int64, keepLatest: Bool = true) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            var request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            request.predicate = NSPredicate(format: "createdAt < %lld", timestamp)

            if keepLatest {
                // En son oluşturulanı koru
                request.sortDescriptors = [NSSortDescriptor(keyPath: \SignedPreKey.createdAt, ascending: false)]

                let allOld = try context.fetch(request)
                // İlk (en güncel) olanı hariç tümünü sil
                let toDelete = Array(allOld.dropFirst())
                toDelete.forEach { context.delete($0) }
            } else {
                let signedPreKeys = try context.fetch(request)
                signedPreKeys.forEach { context.delete($0) }
            }

            try context.save()
        }
    }

    /// Signed PreKey rotation gerekli mi kontrol et
    public func needsRotation(rotationPeriodDays: Int = 7) async throws -> Bool {
        let rotationPeriodMs = Int64(rotationPeriodDays * 24 * 60 * 60 * 1000)
        let cutoffTime = Int64(Date().timeIntervalSince1970 * 1000) - rotationPeriodMs

        if let latest = try await getLatest() {
            return latest.createdAt < cutoffTime
        }

        // Hiç Signed PreKey yoksa rotation gerekli
        return true
    }

    /// Tüm Signed PreKey'leri sil
    public func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = SignedPreKey.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }

    /// Aktif (güncel) Signed PreKey var mı kontrol et
    public func hasValidSignedPreKey(maxAgeDays: Int = 30) async throws -> Bool {
        let maxAgeMs = Int64(maxAgeDays * 24 * 60 * 60 * 1000)
        let cutoffTime = Int64(Date().timeIntervalSince1970 * 1000) - maxAgeMs

        if let latest = try await getLatest() {
            return latest.createdAt > cutoffTime
        }

        return false
    }

    /// Signed PreKey'leri temizle (maximum N adet tut)
    public func cleanup(keepMaxCount: Int = 5) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<SignedPreKey> = SignedPreKey.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SignedPreKey.createdAt, ascending: false)]

            let allSignedPreKeys = try context.fetch(request)

            // Fazla olanları sil (en eski önce)
            if allSignedPreKeys.count > keepMaxCount {
                let toDelete = Array(allSignedPreKeys.dropFirst(keepMaxCount))
                toDelete.forEach { context.delete($0) }
                try context.save()
            }
        }
    }
}