import Foundation
import CoreData

/// Identity key veri erişim nesnesi.
/// Uzak kullanıcıların kimlik anahtarlarını saklar ve güven seviyelerini yönetir.
public class IdentityDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// Address name ile identity key getir
    public func get(addressName: String) async throws -> (identityKey: Data, trustLevel: TrustLevel)? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "addressName == %@", addressName)
            request.fetchLimit = 1

            let identities = try context.fetch(request)
            guard let identity = identities.first else { return nil }

            let trustLevel = TrustLevel(rawValue: identity.trustLevel ?? "") ?? .untrusted
            return (
                identityKey: identity.identityKey ?? Data(),
                trustLevel: trustLevel
            )
        }
    }

    /// Identity key ekle/güncelle
    public func insert(addressName: String, identityKey: Data, trustLevel: TrustLevel) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut Identity'yi kontrol et
            let fetchRequest: NSFetchRequest<Identity> = Identity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "addressName == %@", addressName)

            let existingIdentities = try context.fetch(fetchRequest)
            let identity = existingIdentities.first ?? Identity(context: context)

            // Identity verilerini ayarla
            identity.addressName = addressName
            identity.identityKey = identityKey
            identity.trustLevel = trustLevel.rawValue

            try context.save()
        }
    }

    /// Güven seviyesini güncelle
    public func updateTrustLevel(addressName: String, trustLevel: TrustLevel) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "addressName == %@", addressName)

            let identities = try context.fetch(request)
            identities.forEach { identity in
                identity.trustLevel = trustLevel.rawValue
            }

            try context.save()
        }
    }

    /// Identity sil
    public func delete(addressName: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "addressName == %@", addressName)

            let identities = try context.fetch(request)
            identities.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Identity var mı kontrol et
    public func exists(addressName: String) async throws -> Bool {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "addressName == %@", addressName)
            request.fetchLimit = 1

            let count = try context.count(for: request)
            return count > 0
        }
    }

    /// Identity key'in güven durumunu kontrol et
    public func getTrustLevel(addressName: String) async throws -> TrustLevel? {
        if let (_, trustLevel) = try await get(addressName: addressName) {
            return trustLevel
        }
        return nil
    }

    /// Güvenilir identity'leri getir
    public func getTrustedIdentities() async throws -> [String: (identityKey: Data, trustLevel: TrustLevel)] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "trustLevel == %@ OR trustLevel == %@",
                                            TrustLevel.trustedUnverified.rawValue,
                                            TrustLevel.trustedVerified.rawValue)

            let identities = try context.fetch(request)
            var result: [String: (identityKey: Data, trustLevel: TrustLevel)] = [:]

            for identity in identities {
                guard let addressName = identity.addressName,
                      let identityKey = identity.identityKey,
                      let trustLevelString = identity.trustLevel,
                      let trustLevel = TrustLevel(rawValue: trustLevelString) else {
                    continue
                }

                result[addressName] = (identityKey: identityKey, trustLevel: trustLevel)
            }

            return result
        }
    }

    /// Güvenilmeyen identity'leri getir
    public func getUntrustedIdentities() async throws -> [String: Data] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "trustLevel == %@", TrustLevel.untrusted.rawValue)

            let identities = try context.fetch(request)
            var result: [String: Data] = [:]

            for identity in identities {
                guard let addressName = identity.addressName,
                      let identityKey = identity.identityKey else {
                    continue
                }

                result[addressName] = identityKey
            }

            return result
        }
    }

    /// Identity key değişikliğini kontrol et
    public func checkIdentityKeyChange(addressName: String, newIdentityKey: Data) async throws -> Bool {
        if let (existingKey, _) = try await get(addressName: addressName) {
            return existingKey != newIdentityKey
        }
        return false // Yeni identity key
    }

    /// Identity key'i doğrulama olarak işaretle
    public func markAsVerified(addressName: String) async throws {
        try await updateTrustLevel(addressName: addressName, trustLevel: .trustedVerified)
    }

    /// Identity key'i güvenilir unverified olarak işaretle
    public func markAsTrustedUnverified(addressName: String) async throws {
        try await updateTrustLevel(addressName: addressName, trustLevel: .trustedUnverified)
    }

    /// Identity key'i güvenilmez olarak işaretle
    public func markAsUntrusted(addressName: String) async throws {
        try await updateTrustLevel(addressName: addressName, trustLevel: .untrusted)
    }

    /// Tüm identity'leri getir
    public func getAll() async throws -> [String: (identityKey: Data, trustLevel: TrustLevel)] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Identity.addressName, ascending: true)]

            let identities = try context.fetch(request)
            var result: [String: (identityKey: Data, trustLevel: TrustLevel)] = [:]

            for identity in identities {
                guard let addressName = identity.addressName,
                      let identityKey = identity.identityKey,
                      let trustLevelString = identity.trustLevel,
                      let trustLevel = TrustLevel(rawValue: trustLevelString) else {
                    continue
                }

                result[addressName] = (identityKey: identityKey, trustLevel: trustLevel)
            }

            return result
        }
    }

    /// Toplam identity sayısı
    public func count() async throws -> Int {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            return try context.count(for: request)
        }
    }

    /// Güven seviyesine göre sayım
    public func count(trustLevel: TrustLevel) async throws -> Int {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "trustLevel == %@", trustLevel.rawValue)
            return try context.count(for: request)
        }
    }

    /// Tüm identity'leri sil (factory reset için)
    public func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = Identity.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }

    /// Kullanıcı ID'sine göre identity'leri sil
    public func deleteIdentitiesForUser(userId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.predicate = NSPredicate(format: "addressName BEGINSWITH %@", "\(userId):")

            let identities = try context.fetch(request)
            identities.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Identity backup (export) için tüm verileri getir
    public func getAllForBackup() async throws -> [(addressName: String, identityKey: Data, trustLevel: TrustLevel)] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Identity> = Identity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Identity.addressName, ascending: true)]

            let identities = try context.fetch(request)
            return identities.compactMap { identity in
                guard let addressName = identity.addressName,
                      let identityKey = identity.identityKey,
                      let trustLevelString = identity.trustLevel,
                      let trustLevel = TrustLevel(rawValue: trustLevelString) else {
                    return nil
                }

                return (addressName: addressName, identityKey: identityKey, trustLevel: trustLevel)
            }
        }
    }

    /// Identity restore (import) için batch insert
    public func restoreFromBackup(_ identities: [(addressName: String, identityKey: Data, trustLevel: TrustLevel)]) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            for (addressName, identityKey, trustLevel) in identities {
                // Mevcut identity'yi kontrol et
                let fetchRequest: NSFetchRequest<Identity> = Identity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "addressName == %@", addressName)

                let existingIdentities = try context.fetch(fetchRequest)
                let identity = existingIdentities.first ?? Identity(context: context)

                identity.addressName = addressName
                identity.identityKey = identityKey
                identity.trustLevel = trustLevel.rawValue
            }

            try context.save()
        }
    }
}