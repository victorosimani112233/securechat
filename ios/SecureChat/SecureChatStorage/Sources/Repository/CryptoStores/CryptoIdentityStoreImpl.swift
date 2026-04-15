import Foundation

/// Signal Protocol Identity Store implementasyonu.
/// Core Data ile identity key'leri ve güven seviyelerini yönetir.
public class CryptoIdentityStoreImpl {

    // MARK: - Properties

    private let identityDAO: IdentityDAO

    // MARK: - Initialization

    public init(identityDAO: IdentityDAO = IdentityDAO()) {
        self.identityDAO = identityDAO
    }

    // MARK: - Public Methods

    /// Identity key kaydet
    public func saveIdentity(_ address: SignalAddress, identityKey: Data) async throws {
        let addressName = address.sessionId
        try await identityDAO.insert(addressName: addressName, identityKey: identityKey, trustLevel: .untrusted)
    }

    /// Identity key yükle
    public func getIdentity(for address: SignalAddress) async throws -> Data? {
        let addressName = address.sessionId
        if let (identityKey, _) = try await identityDAO.get(addressName: addressName) {
            return identityKey
        }
        return nil
    }

    /// Identity key var mı kontrol et
    public func containsIdentity(for address: SignalAddress) async throws -> Bool {
        let addressName = address.sessionId
        return try await identityDAO.exists(addressName: addressName)
    }

    /// Identity key güven seviyesini getir
    public func getTrustLevel(for address: SignalAddress) async throws -> TrustLevel? {
        let addressName = address.sessionId
        return try await identityDAO.getTrustLevel(addressName: addressName)
    }

    /// Identity key güven seviyesini ayarla
    public func setTrustLevel(_ trustLevel: TrustLevel, for address: SignalAddress) async throws {
        let addressName = address.sessionId
        try await identityDAO.updateTrustLevel(addressName: addressName, trustLevel: trustLevel)
    }

    /// Identity key değişikliğini kontrol et
    public func isTrustedIdentity(_ address: SignalAddress, identityKey: Data) async throws -> Bool {
        let addressName = address.sessionId

        // Mevcut identity key'i kontrol et
        if let (existingKey, trustLevel) = try await identityDAO.get(addressName: addressName) {
            // Key aynıysa ve güvenilir ise
            if existingKey == identityKey {
                return trustLevel != .untrusted
            } else {
                // Identity key değişmiş - güvenilmez
                return false
            }
        }

        // Yeni identity key - güvenilir kabul edilebilir (first contact)
        return true
    }

    /// Identity key değişikliği tespit et
    public func hasIdentityKeyChanged(_ address: SignalAddress, identityKey: Data) async throws -> Bool {
        let addressName = address.sessionId
        return try await identityDAO.checkIdentityKeyChange(addressName: addressName, newIdentityKey: identityKey)
    }

    /// Identity key sil
    public func deleteIdentity(for address: SignalAddress) async throws {
        let addressName = address.sessionId
        try await identityDAO.delete(addressName: addressName)
    }

    /// Tüm identity key'leri sil
    public func clearAllIdentities() async throws {
        try await identityDAO.deleteAll()
    }
}

// MARK: - Identity Management Extensions

extension CryptoIdentityStoreImpl {

    /// Güvenilir identity'leri getir
    public func getTrustedIdentities() async throws -> [SignalAddress: Data] {
        let trustedDict = try await identityDAO.getTrustedIdentities()
        var result: [SignalAddress: Data] = [:]

        for (addressName, (identityKey, _)) in trustedDict {
            if let address = SignalAddress.from(sessionId: addressName) {
                result[address] = identityKey
            }
        }

        return result
    }

    /// Güvenilmeyen identity'leri getir
    public func getUntrustedIdentities() async throws -> [SignalAddress: Data] {
        let untrustedDict = try await identityDAO.getUntrustedIdentities()
        var result: [SignalAddress: Data] = [:]

        for (addressName, identityKey) in untrustedDict {
            if let address = SignalAddress.from(sessionId: addressName) {
                result[address] = identityKey
            }
        }

        return result
    }

    /// Identity'i doğrulanmış olarak işaretle
    public func markAsVerified(_ address: SignalAddress) async throws {
        try await identityDAO.markAsVerified(addressName: address.sessionId)
    }

    /// Identity'i güvenilir unverified olarak işaretle
    public func markAsTrustedUnverified(_ address: SignalAddress) async throws {
        try await identityDAO.markAsTrustedUnverified(addressName: address.sessionId)
    }

    /// Identity'i güvenilmez olarak işaretle
    public func markAsUntrusted(_ address: SignalAddress) async throws {
        try await identityDAO.markAsUntrusted(addressName: address.sessionId)
    }

    /// Kullanıcının tüm identity'lerini sil
    public func deleteAllIdentities(for userId: String) async throws {
        try await identityDAO.deleteIdentitiesForUser(userId: userId)
    }

    /// Identity istatistikleri
    public func getIdentityStatistics() async throws -> IdentityStatistics {
        let totalCount = try await identityDAO.count()
        let verifiedCount = try await identityDAO.count(trustLevel: .trustedVerified)
        let trustedUnverifiedCount = try await identityDAO.count(trustLevel: .trustedUnverified)
        let untrustedCount = try await identityDAO.count(trustLevel: .untrusted)

        return IdentityStatistics(
            totalIdentities: totalCount,
            verifiedIdentities: verifiedCount,
            trustedUnverifiedIdentities: trustedUnverifiedCount,
            untrustedIdentities: untrustedCount
        )
    }

    /// Identity backup için export
    public func exportIdentitiesForBackup() async throws -> [IdentityBackup] {
        let identities = try await identityDAO.getAllForBackup()
        return identities.map { (addressName, identityKey, trustLevel) in
            IdentityBackup(
                addressName: addressName,
                identityKey: identityKey,
                trustLevel: trustLevel
            )
        }
    }

    /// Identity backup'tan import
    public func importIdentitiesFromBackup(_ backups: [IdentityBackup]) async throws {
        let identities = backups.map { ($0.addressName, $0.identityKey, $0.trustLevel) }
        try await identityDAO.restoreFromBackup(identities)
    }

    /// Identity validation (format kontrolü)
    public func validateIdentities() async throws -> IdentityValidationResult {
        let allIdentities = try await identityDAO.getAll()
        var validCount = 0
        var invalidAddresses: [String] = []

        for (addressName, (identityKey, _)) in allIdentities {
            if SignalAddress.from(sessionId: addressName) != nil && !identityKey.isEmpty {
                validCount += 1
            } else {
                invalidAddresses.append(addressName)
            }
        }

        return IdentityValidationResult(
            totalIdentities: allIdentities.count,
            validIdentities: validCount,
            invalidAddresses: invalidAddresses
        )
    }

    /// Identity key conflict resolution
    public func resolveIdentityConflict(
        _ address: SignalAddress,
        newIdentityKey: Data,
        resolution: IdentityConflictResolution
    ) async throws {
        let addressName = address.sessionId

        switch resolution {
        case .acceptNew:
            // Yeni identity key'i kabul et ve güvenilir unverified yap
            try await identityDAO.insert(addressName: addressName, identityKey: newIdentityKey, trustLevel: .trustedUnverified)

        case .rejectNew:
            // Yeni key'i reddet - mevcut key'i koru, güvenilmez yap
            if let (existingKey, _) = try await identityDAO.get(addressName: addressName) {
                try await identityDAO.insert(addressName: addressName, identityKey: existingKey, trustLevel: .untrusted)
            }

        case .markUntrusted:
            // Her iki durumu da güvenilmez yap
            try await identityDAO.insert(addressName: addressName, identityKey: newIdentityKey, trustLevel: .untrusted)
        }
    }
}

// MARK: - Identity Conflict Resolution

public enum IdentityConflictResolution {
    case acceptNew      // Yeni identity key'i kabul et
    case rejectNew      // Yeni identity key'i reddet
    case markUntrusted  // Güvenilmez olarak işaretle
}

// MARK: - Identity Statistics

public struct IdentityStatistics {
    public let totalIdentities: Int
    public let verifiedIdentities: Int
    public let trustedUnverifiedIdentities: Int
    public let untrustedIdentities: Int

    public var trustRatio: Double {
        guard totalIdentities > 0 else { return 0.0 }
        return Double(verifiedIdentities + trustedUnverifiedIdentities) / Double(totalIdentities)
    }

    public var description: String {
        return """
        Identity Statistics:
        - Total: \(totalIdentities)
        - Verified: \(verifiedIdentities)
        - Trusted Unverified: \(trustedUnverifiedIdentities)
        - Untrusted: \(untrustedIdentities)
        - Trust Ratio: \(String(format: "%.1f%%", trustRatio * 100))
        """
    }
}

// MARK: - Identity Validation Result

public struct IdentityValidationResult {
    public let totalIdentities: Int
    public let validIdentities: Int
    public let invalidAddresses: [String]

    public var hasInvalidIdentities: Bool {
        return !invalidAddresses.isEmpty
    }

    public var description: String {
        return """
        Identity Validation:
        - Total: \(totalIdentities)
        - Valid: \(validIdentities)
        - Invalid: \(invalidAddresses.count)
        """
    }
}

// MARK: - Identity Backup

public struct IdentityBackup: Codable {
    public let addressName: String
    public let identityKey: Data
    public let trustLevel: TrustLevel

    public init(addressName: String, identityKey: Data, trustLevel: TrustLevel) {
        self.addressName = addressName
        self.identityKey = identityKey
        self.trustLevel = trustLevel
    }

    /// SignalAddress çıkar
    public var signalAddress: SignalAddress? {
        return SignalAddress.from(sessionId: addressName)
    }
}

// MARK: - Signal Protocol Integration

extension CryptoIdentityStoreImpl {

    /// Signal Protocol için identity doğrulama
    public func verifyIdentityForSignalProtocol(
        _ address: SignalAddress,
        identityKey: Data,
        direction: ProtocolDirection
    ) async throws -> Bool {
        let addressName = address.sessionId

        // Mevcut identity key kontrolü
        if let (existingKey, trustLevel) = try await identityDAO.get(addressName: addressName) {
            if existingKey == identityKey {
                // Key aynı - güven seviyesine bak
                return trustLevel != .untrusted
            } else {
                // Identity key değişmiş - güvenlik riski
                return false
            }
        } else {
            // Yeni identity key - direction'a göre karar ver
            switch direction {
            case .sending:
                // Gönderirken yeni identity kabul edilebilir
                try await saveIdentity(address, identityKey: identityKey)
                return true

            case .receiving:
                // Alırken daha dikkatli olmalı - kullanıcı onayı gerekebilir
                try await saveIdentity(address, identityKey: identityKey)
                return true
            }
        }
    }
}

// MARK: - Protocol Direction

public enum ProtocolDirection {
    case sending
    case receiving
}