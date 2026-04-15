import Foundation
import CoreData

/// Session veri erişim nesnesi.
/// Her kullanıcı-cihaz çifti için ayrı bir session tutulur.
/// Session ID formatı: "$userId:$deviceId"
public class SessionDAO {

    // MARK: - Properties

    private let coreDataManager: CoreDataManager

    // MARK: - Initialization

    public init(coreDataManager: CoreDataManager = .shared) {
        self.coreDataManager = coreDataManager
    }

    // MARK: - Public Methods

    /// Session ID ile session getir
    public func get(sessionId: String) async throws -> Data? {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sessionId)
            request.fetchLimit = 1

            let sessions = try context.fetch(request)
            return sessions.first?.record
        }
    }

    /// Session ekle/güncelle
    public func insert(sessionId: String, record: Data) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Mevcut Session'ı kontrol et
            let fetchRequest: NSFetchRequest<Session> = Session.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", sessionId)

            let existingSessions = try context.fetch(fetchRequest)
            let session = existingSessions.first ?? Session(context: context)

            // Session verilerini ayarla
            session.id = sessionId
            session.record = record

            try context.save()
        }
    }

    /// Session sil
    public func delete(sessionId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sessionId)

            let sessions = try context.fetch(request)
            sessions.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Kullanıcı ID'si ile tüm session'ları getir
    public func getSessionsForUser(userId: String) async throws -> [String: Data] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id BEGINSWITH %@", "\(userId):")

            let sessions = try context.fetch(request)
            var result: [String: Data] = [:]

            for session in sessions {
                if let sessionId = session.id, let record = session.record {
                    result[sessionId] = record
                }
            }

            return result
        }
    }

    /// Belirli kullanıcıya ait tüm session'ları sil
    public func deleteSessionsForUser(userId: String) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id BEGINSWITH %@", "\(userId):")

            let sessions = try context.fetch(request)
            sessions.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Tüm session'ları getir
    public func getAll() async throws -> [String: Data] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            let sessions = try context.fetch(request)
            var result: [String: Data] = [:]

            for session in sessions {
                if let sessionId = session.id, let record = session.record {
                    result[sessionId] = record
                }
            }

            return result
        }
    }

    /// Toplam session sayısı
    public func count() async throws -> Int {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            return try context.count(for: request)
        }
    }

    /// Session var mı kontrol et
    public func exists(sessionId: String) async throws -> Bool {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", sessionId)
            request.fetchLimit = 1

            let count = try context.count(for: request)
            return count > 0
        }
    }

    /// Kullanıcının session'ları var mı kontrol et
    public func hasSessionsForUser(userId: String) async throws -> Bool {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: "id BEGINSWITH %@", "\(userId):")
            request.fetchLimit = 1

            let count = try context.count(for: request)
            return count > 0
        }
    }

    /// Kullanıcının cihazlarını getir (session ID'lerinden parse et)
    public func getDevicesForUser(userId: String) async throws -> [String] {
        let sessions = try await getSessionsForUser(userId: userId)
        var devices: [String] = []

        for sessionId in sessions.keys {
            // SessionID formatı: "userId:deviceId"
            let components = sessionId.components(separatedBy: ":")
            if components.count >= 2 {
                let deviceId = components.dropFirst().joined(separator: ":")
                devices.append(deviceId)
            }
        }

        return devices.sorted()
    }

    /// Belirli cihaz için session sil
    public func deleteDevice(userId: String, deviceId: String) async throws {
        let sessionId = "\(userId):\(deviceId)"
        try await delete(sessionId: sessionId)
    }

    /// Tüm session'ları sil (factory reset / logout)
    public func deleteAll() async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = Session.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
            try context.save()
        }
    }

    /// Session'ları temizle (belirli kullanıcılar hariç)
    public func deleteAllExcept(userIds: [String]) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            // Hariç tutulacak session ID pattern'leri oluştur
            var predicateStrings: [String] = []
            for userId in userIds {
                predicateStrings.append("NOT (id BEGINSWITH '\(userId):')")
            }

            if predicateStrings.isEmpty {
                // Hiç hariç tutulacak yoksa tümünü sil
                try await self.deleteAll()
                return
            }

            let predicateString = predicateStrings.joined(separator: " AND ")
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.predicate = NSPredicate(format: predicateString)

            let sessions = try context.fetch(request)
            sessions.forEach { context.delete($0) }

            try context.save()
        }
    }

    /// Session backup (export) için tüm verileri getir
    public func getAllForBackup() async throws -> [(sessionId: String, record: Data)] {
        let context = coreDataManager.viewContext

        return try await context.perform {
            let request: NSFetchRequest<Session> = Session.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Session.id, ascending: true)]

            let sessions = try context.fetch(request)
            return sessions.compactMap { session in
                guard let sessionId = session.id, let record = session.record else { return nil }
                return (sessionId: sessionId, record: record)
            }
        }
    }

    /// Session restore (import) için batch insert
    public func restoreFromBackup(_ sessions: [(sessionId: String, record: Data)]) async throws {
        let context = coreDataManager.newBackgroundContext()

        try await context.perform {
            for (sessionId, record) in sessions {
                // Mevcut session'ı kontrol et
                let fetchRequest: NSFetchRequest<Session> = Session.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", sessionId)

                let existingSessions = try context.fetch(fetchRequest)
                let session = existingSessions.first ?? Session(context: context)

                session.id = sessionId
                session.record = record
            }

            try context.save()
        }
    }
}