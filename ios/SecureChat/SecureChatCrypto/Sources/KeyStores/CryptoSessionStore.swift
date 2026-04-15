import Foundation

/// Signal Protocol session storage ve yönetimi.
/// Double Ratchet state'ini güvenli şekilde saklar.
/// Her kullanıcı-cihaz çifti için ayrı session tutar.
///
/// GÜVENLIK: Session data Keychain'de şifreli saklanır.
/// GÜVENLIK: Session key material ASLA loga yazılmaz.
public actor CryptoSessionStore {

    // MARK: - Constants

    private struct Constants {
        static let sessionPrefix = "session_"
        static let sessionListKey = "session_list"
        static let sessionSeparator = ":"
    }

    // MARK: - Properties

    private let keychainManager: KeychainManager
    private var activeSessions: Set<String> = [] // "username:deviceId" formatında

    // MARK: - Initialization

    public init(keychainManager: KeychainManager) {
        self.keychainManager = keychainManager
        Task {
            await loadSessionMetadata()
        }
    }

    // MARK: - Session Management

    /// Session'ı yükler.
    ///
    /// - Parameters:
    ///   - name: Kullanıcı adı
    ///   - deviceId: Cihaz ID
    /// - Returns: Session data veya nil
    public func loadSession(_ name: String, deviceId: UInt32) async -> Data? {
        let sessionKey = makeSessionKey(name: name, deviceId: deviceId)
        let tag = Constants.sessionPrefix + sessionKey

        do {
            return try keychainManager.loadData(tag: tag)
        } catch {
            print("❌ Failed to load session for \(sessionKey): \(error)")
            return nil
        }
    }

    /// Session'ı saklar.
    ///
    /// - Parameters:
    ///   - name: Kullanıcı adı
    ///   - deviceId: Cihaz ID
    ///   - sessionData: Session data
    /// - Returns: Başarı durumu
    public func storeSession(_ name: String, deviceId: UInt32, sessionData: Data) async -> Bool {
        let sessionKey = makeSessionKey(name: name, deviceId: deviceId)
        let tag = Constants.sessionPrefix + sessionKey

        do {
            try keychainManager.storeData(sessionData, tag: tag)
            activeSessions.insert(sessionKey)
            await saveSessionMetadata()
            return true
        } catch {
            print("❌ Failed to store session for \(sessionKey): \(error)")
            return false
        }
    }

    /// Session'ın mevcut olup olmadığını kontrol eder.
    ///
    /// - Parameters:
    ///   - name: Kullanıcı adı
    ///   - deviceId: Cihaz ID
    /// - Returns: true eğer session mevcutsa
    public func containsSession(_ name: String, deviceId: UInt32) async -> Bool {
        let sessionKey = makeSessionKey(name: name, deviceId: deviceId)
        return activeSessions.contains(sessionKey)
    }

    /// Belirli bir session'ı siler.
    ///
    /// - Parameters:
    ///   - name: Kullanıcı adı
    ///   - deviceId: Cihaz ID
    /// - Returns: Başarı durumu
    public func deleteSession(_ name: String, deviceId: UInt32) async -> Bool {
        let sessionKey = makeSessionKey(name: name, deviceId: deviceId)
        let tag = Constants.sessionPrefix + sessionKey

        do {
            try keychainManager.deleteData(tag: tag)
            activeSessions.remove(sessionKey)
            await saveSessionMetadata()
            return true
        } catch {
            print("❌ Failed to delete session for \(sessionKey): \(error)")
            return false
        }
    }

    /// Belirli bir kullanıcının tüm cihazları için session'ları siler.
    ///
    /// - Parameter name: Kullanıcı adı
    /// - Returns: Silinen session sayısı
    public func deleteAllSessions(_ name: String) async -> Int {
        let sessionsToDelete = activeSessions.filter { sessionKey in
            sessionKey.starts(with: name + Constants.sessionSeparator)
        }

        var deletedCount = 0

        for sessionKey in sessionsToDelete {
            let components = sessionKey.split(separator: Character(Constants.sessionSeparator))
            if components.count == 2,
               let deviceId = UInt32(components[1]) {
                if await deleteSession(name, deviceId: deviceId) {
                    deletedCount += 1
                }
            }
        }

        return deletedCount
    }

    /// Belirli bir kullanıcının sub-device session'larının device ID'lerini döndürür.
    ///
    /// - Parameter name: Kullanıcı adı
    /// - Returns: Device ID'leri array
    public func getSubDeviceSessions(_ name: String) async -> [UInt32] {
        let userSessions = activeSessions.filter { sessionKey in
            sessionKey.starts(with: name + Constants.sessionSeparator)
        }

        var deviceIds: [UInt32] = []

        for sessionKey in userSessions {
            let components = sessionKey.split(separator: Character(Constants.sessionSeparator))
            if components.count == 2,
               let deviceId = UInt32(components[1]) {
                deviceIds.append(deviceId)
            }
        }

        return deviceIds.sorted()
    }

    /// Tüm session'ları siler. Logout işlemi sırasında kullanılır.
    ///
    /// - Throws: Deletion hatası
    public func deleteAllSessions() async throws {
        for sessionKey in activeSessions {
            let tag = Constants.sessionPrefix + sessionKey
            try keychainManager.deleteData(tag: tag)
        }

        activeSessions.removeAll()
        await saveSessionMetadata()
    }

    // MARK: - Session Statistics

    /// Aktif session sayısını döndürür.
    ///
    /// - Returns: Aktif session sayısı
    public func getActiveSessionCount() async -> Int {
        return activeSessions.count
    }

    /// Belirli bir kullanıcının session sayısını döndürür.
    ///
    /// - Parameter name: Kullanıcı adı
    /// - Returns: Session sayısı
    public func getUserSessionCount(_ name: String) async -> Int {
        return activeSessions.filter { sessionKey in
            sessionKey.starts(with: name + Constants.sessionSeparator)
        }.count
    }

    /// Tüm aktif session'ların listesini döndürür.
    ///
    /// - Returns: Session key'leri (username:deviceId formatında)
    public func getAllActiveSessions() async -> [String] {
        return Array(activeSessions).sorted()
    }

    /// Session store'un sağlık durumunu kontrol eder.
    ///
    /// - Returns: Sağlık raporu
    public func getHealthStatus() async -> SessionHealthStatus {
        let totalSessions = activeSessions.count
        let userCounts = Dictionary(grouping: activeSessions) { sessionKey in
            sessionKey.split(separator: Character(Constants.sessionSeparator)).first?.description ?? "unknown"
        }.mapValues { $0.count }

        return SessionHealthStatus(
            totalSessionCount: totalSessions,
            uniqueUserCount: userCounts.count,
            userSessionCounts: userCounts
        )
    }

    // MARK: - Private Helpers

    /// Session key oluşturur (username:deviceId formatında).
    private func makeSessionKey(name: String, deviceId: UInt32) -> String {
        return "\(name)\(Constants.sessionSeparator)\(deviceId)"
    }

    /// Session metadata'sını Keychain'den yükler.
    private func loadSessionMetadata() async {
        do {
            if let sessionListData = try keychainManager.loadData(tag: Constants.sessionListKey) {
                activeSessions = try decodeSessionList(from: sessionListData)
            }
        } catch {
            print("❌ Failed to load session metadata: \(error)")
        }
    }

    /// Session metadata'sını Keychain'e kaydeder.
    private func saveSessionMetadata() async {
        do {
            let sessionListData = try encodeSessionList(activeSessions)
            try keychainManager.storeData(sessionListData, tag: Constants.sessionListKey)
        } catch {
            print("❌ Failed to save session metadata: \(error)")
        }
    }

    /// Session listesini Data'ya encode eder.
    private func encodeSessionList(_ sessions: Set<String>) throws -> Data {
        let encoder = JSONEncoder()
        let array = Array(sessions)
        return try encoder.encode(array)
    }

    /// Data'dan session listesini decode eder.
    private func decodeSessionList(from data: Data) throws -> Set<String> {
        let decoder = JSONDecoder()
        let array = try decoder.decode([String].self, from: data)
        return Set(array)
    }

    // MARK: - Session Cleanup

    /// Orphaned session'ları temizler.
    /// Keychain'de olmayan ama metadata'da olan session'ları kaldırır.
    ///
    /// - Returns: Temizlenen session sayısı
    public func cleanupOrphanedSessions() async -> Int {
        var cleanedCount = 0
        var validSessions = Set<String>()

        for sessionKey in activeSessions {
            let tag = Constants.sessionPrefix + sessionKey

            do {
                if let _ = try keychainManager.loadData(tag: tag) {
                    validSessions.insert(sessionKey)
                } else {
                    cleanedCount += 1
                }
            } catch {
                // Session data yüklenemedi, orphaned kabul et
                cleanedCount += 1
            }
        }

        if cleanedCount > 0 {
            activeSessions = validSessions
            await saveSessionMetadata()
        }

        return cleanedCount
    }

    /// Session data integrity kontrolü yapar.
    ///
    /// - Returns: Corrupt session sayısı
    public func verifySessionIntegrity() async -> Int {
        var corruptCount = 0

        for sessionKey in activeSessions {
            let tag = Constants.sessionPrefix + sessionKey

            do {
                if let sessionData = try keychainManager.loadData(tag: tag) {
                    // Basit data validation - gerçek uygulamada Signal Protocol parsing yapılmalı
                    if sessionData.isEmpty || sessionData.count < 32 {
                        print("⚠️ Potentially corrupt session: \(sessionKey)")
                        corruptCount += 1
                    }
                }
            } catch {
                print("❌ Failed to verify session \(sessionKey): \(error)")
                corruptCount += 1
            }
        }

        return corruptCount
    }
}

// MARK: - Session Health Status

public struct SessionHealthStatus {
    public let totalSessionCount: Int
    public let uniqueUserCount: Int
    public let userSessionCounts: [String: Int]

    public init(totalSessionCount: Int, uniqueUserCount: Int, userSessionCounts: [String: Int]) {
        self.totalSessionCount = totalSessionCount
        self.uniqueUserCount = uniqueUserCount
        self.userSessionCounts = userSessionCounts
    }

    /// En fazla session'a sahip kullanıcı
    public var topUser: (name: String, sessionCount: Int)? {
        guard let (name, count) = userSessionCounts.max(by: { $0.value < $1.value }) else {
            return nil
        }
        return (name: name, sessionCount: count)
    }
}