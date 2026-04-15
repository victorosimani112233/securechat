import Foundation

/// Signal Protocol Session Store implementasyonu.
/// Core Data ile session'ları yönetir.
/// Session format: "userId:deviceId"
public class CryptoSessionStoreImpl {

    // MARK: - Properties

    private let sessionDAO: SessionDAO

    // MARK: - Initialization

    public init(sessionDAO: SessionDAO = SessionDAO()) {
        self.sessionDAO = sessionDAO
    }

    // MARK: - Public Methods

    /// Session kaydet
    public func storeSession(for address: SignalAddress, sessionRecord: Data) async throws {
        let sessionId = address.sessionId
        try await sessionDAO.insert(sessionId: sessionId, record: sessionRecord)
    }

    /// Session yükle
    public func loadSession(for address: SignalAddress) async throws -> Data? {
        let sessionId = address.sessionId
        return try await sessionDAO.get(sessionId: sessionId)
    }

    /// Session var mı kontrol et
    public func containsSession(for address: SignalAddress) async throws -> Bool {
        let sessionId = address.sessionId
        return try await sessionDAO.exists(sessionId: sessionId)
    }

    /// Session sil
    public func deleteSession(for address: SignalAddress) async throws {
        let sessionId = address.sessionId
        try await sessionDAO.delete(sessionId: sessionId)
    }

    /// Belirli kullanıcının tüm session'larını getir
    public func getSubDeviceSessions(for userId: String) async throws -> [UInt32] {
        let devices = try await sessionDAO.getDevicesForUser(userId: userId)
        return devices.compactMap { deviceIdString in
            UInt32(deviceIdString)
        }
    }

    /// Kullanıcının tüm session'larını sil
    public func deleteAllSessions(for userId: String) async throws {
        try await sessionDAO.deleteSessionsForUser(userId: userId)
    }

    /// Belirli cihaz session'ını sil
    public func deleteSession(for userId: String, deviceId: UInt32) async throws {
        try await sessionDAO.deleteDevice(userId: userId, deviceId: String(deviceId))
    }

    /// Tüm session'ları getir
    public func getAllSessions() async throws -> [SignalAddress: Data] {
        let sessionsDict = try await sessionDAO.getAll()
        var result: [SignalAddress: Data] = [:]

        for (sessionId, record) in sessionsDict {
            if let address = SignalAddress.from(sessionId: sessionId) {
                result[address] = record
            }
        }

        return result
    }

    /// Session sayısı
    public func getSessionCount() async throws -> Int {
        return try await sessionDAO.count()
    }

    /// Kullanıcının session'ları var mı
    public func hasSessions(for userId: String) async throws -> Bool {
        return try await sessionDAO.hasSessionsForUser(userId: userId)
    }

    /// Tüm session'ları sil (factory reset)
    public func clearAllSessions() async throws {
        try await sessionDAO.deleteAll()
    }
}

// MARK: - Session Management Extensions

extension CryptoSessionStoreImpl {

    /// Session cleanup (aktif olmayan session'ları temizle)
    public func cleanupInactiveSessions(activeUserIds: [String]) async throws -> Int {
        let beforeCount = try await getSessionCount()
        try await sessionDAO.deleteAllExcept(userIds: activeUserIds)
        let afterCount = try await getSessionCount()
        return beforeCount - afterCount
    }

    /// Session istatistikleri
    public func getSessionStatistics() async throws -> SessionStatistics {
        let allSessions = try await getAllSessions()
        var userSessions: [String: Int] = [:]

        for address in allSessions.keys {
            let count = userSessions[address.userId] ?? 0
            userSessions[address.userId] = count + 1
        }

        return SessionStatistics(
            totalSessionCount: allSessions.count,
            userCount: userSessions.count,
            averageSessionsPerUser: userSessions.count > 0 ? allSessions.count / userSessions.count : 0,
            userSessions: userSessions
        )
    }

    /// Session backup için export
    public func exportSessionsForBackup() async throws -> [SessionBackup] {
        let sessions = try await sessionDAO.getAllForBackup()
        return sessions.map { (sessionId, record) in
            SessionBackup(sessionId: sessionId, record: record)
        }
    }

    /// Session backup'tan import
    public func importSessionsFromBackup(_ backups: [SessionBackup]) async throws {
        let sessions = backups.map { ($0.sessionId, $0.record) }
        try await sessionDAO.restoreFromBackup(sessions)
    }

    /// Session validation (corrupt session'ları tespit et)
    public func validateSessions() async throws -> SessionValidationResult {
        let allSessions = try await getAllSessions()
        var validCount = 0
        var invalidSessions: [String] = []

        for (address, record) in allSessions {
            if isValidSessionRecord(record) {
                validCount += 1
            } else {
                invalidSessions.append(address.sessionId)
            }
        }

        return SessionValidationResult(
            totalSessions: allSessions.count,
            validSessions: validCount,
            invalidSessions: invalidSessions
        )
    }

    /// Session record validasyonu (temel kontrol)
    private func isValidSessionRecord(_ record: Data) -> Bool {
        // Basit validasyon - gerçek implementasyonda Signal Protocol validation olacak
        return !record.isEmpty && record.count > 10
    }

    /// Corrupt session'ları temizle
    public func removeCorruptSessions() async throws -> Int {
        let validation = try await validateSessions()
        var removedCount = 0

        for sessionId in validation.invalidSessions {
            try await sessionDAO.delete(sessionId: sessionId)
            removedCount += 1
        }

        return removedCount
    }
}

// MARK: - SignalAddress Helper

/// Signal Protocol Address model
public struct SignalAddress: Hashable {
    public let userId: String
    public let deviceId: UInt32

    public init(userId: String, deviceId: UInt32) {
        self.userId = userId
        self.deviceId = deviceId
    }

    /// Session ID formatı: "userId:deviceId"
    public var sessionId: String {
        return "\(userId):\(deviceId)"
    }

    /// Session ID'den SignalAddress oluştur
    public static func from(sessionId: String) -> SignalAddress? {
        let components = sessionId.components(separatedBy: ":")
        guard components.count >= 2,
              let deviceId = UInt32(components.dropFirst().joined(separator: ":")) else {
            return nil
        }

        let userId = components.first!
        return SignalAddress(userId: userId, deviceId: deviceId)
    }
}

// MARK: - Session Statistics

public struct SessionStatistics {
    public let totalSessionCount: Int
    public let userCount: Int
    public let averageSessionsPerUser: Int
    public let userSessions: [String: Int]

    public var description: String {
        return """
        Session Statistics:
        - Total Sessions: \(totalSessionCount)
        - Users with Sessions: \(userCount)
        - Average Sessions per User: \(averageSessionsPerUser)
        """
    }
}

// MARK: - Session Validation Result

public struct SessionValidationResult {
    public let totalSessions: Int
    public let validSessions: Int
    public let invalidSessions: [String]

    public var hasCorruptSessions: Bool {
        return !invalidSessions.isEmpty
    }

    public var description: String {
        return """
        Session Validation:
        - Total: \(totalSessions)
        - Valid: \(validSessions)
        - Invalid: \(invalidSessions.count)
        """
    }
}

// MARK: - Session Backup

public struct SessionBackup: Codable {
    public let sessionId: String
    public let record: Data

    public init(sessionId: String, record: Data) {
        self.sessionId = sessionId
        self.record = record
    }

    /// SignalAddress çıkar
    public var signalAddress: SignalAddress? {
        return SignalAddress.from(sessionId: sessionId)
    }
}