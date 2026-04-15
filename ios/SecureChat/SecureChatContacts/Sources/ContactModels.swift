import Foundation

// MARK: - Device Contact

/// Cihaz rehberinden okunan kişi modeli.
/// Telefon numarası E.164 formatında normalize edilmiş olarak saklanır.
public struct DeviceContact: Equatable, Hashable {
    public let id: String
    public let displayName: String
    public let phoneNumber: String // E.164 format
    public let avatarUri: String?

    public init(
        id: String,
        displayName: String,
        phoneNumber: String,
        avatarUri: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.avatarUri = avatarUri
    }

    public static func == (lhs: DeviceContact, rhs: DeviceContact) -> Bool {
        return lhs.id == rhs.id &&
               lhs.displayName == rhs.displayName &&
               lhs.phoneNumber == rhs.phoneNumber &&
               lhs.avatarUri == rhs.avatarUri
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(phoneNumber)
    }
}

// MARK: - Registered Contact

/// SecureChat'e kayıtlı olan kişi modeli.
/// Sunucudan gelen userId ile cihaz rehberindeki bilgiler eşleştirilir.
public struct RegisteredContact: Equatable, Hashable {
    public let userId: String
    public let displayName: String
    public let phoneNumber: String
    public let phoneHash: String
    public let avatarUri: String?

    public init(
        userId: String,
        displayName: String,
        phoneNumber: String,
        phoneHash: String,
        avatarUri: String? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.phoneNumber = phoneNumber
        self.phoneHash = phoneHash
        self.avatarUri = avatarUri
    }

    public static func == (lhs: RegisteredContact, rhs: RegisteredContact) -> Bool {
        return lhs.userId == rhs.userId &&
               lhs.displayName == rhs.displayName &&
               lhs.phoneNumber == rhs.phoneNumber &&
               lhs.phoneHash == rhs.phoneHash &&
               lhs.avatarUri == rhs.avatarUri
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
        hasher.combine(phoneHash)
    }
}

// MARK: - API Models

/// Kullanıcı keşfi için sunucuya gönderilen istek.
/// Yalnızca telefon numaralarının SHA-256 hash'lerini içerir,
/// plaintext numara ASLA gönderilmez.
public struct CheckUsersRequest: Codable {
    public let hashes: [String]

    public init(hashes: [String]) {
        self.hashes = hashes
    }
}

/// Sunucudan dönen kayıtlı kullanıcı listesi.
/// Her kullanıcı için userId ve eşleşme sağlayan phoneHash döner.
public struct CheckUsersResponse: Codable {
    public let users: [ServerUser]

    public init(users: [ServerUser]) {
        self.users = users
    }
}

/// Sunucuda kayıtlı olan kullanıcı bilgisi.
public struct ServerUser: Codable {
    public let userId: String
    public let phoneHash: String

    public init(userId: String, phoneHash: String) {
        self.userId = userId
        self.phoneHash = phoneHash
    }
}

// MARK: - Contact Permission Status

/// iOS Contacts framework izin durumu
public enum ContactPermissionStatus: Equatable {
    case notDetermined
    case denied
    case authorized

    public var isAuthorized: Bool {
        return self == .authorized
    }
}

// MARK: - Contact Discovery Result

/// Kullanıcı keşfi sonucu
public struct ContactDiscoveryResult {
    public let discoveredContacts: [RegisteredContact]
    public let totalHashesChecked: Int
    public let registeredCount: Int

    public init(
        discoveredContacts: [RegisteredContact],
        totalHashesChecked: Int,
        registeredCount: Int
    ) {
        self.discoveredContacts = discoveredContacts
        self.totalHashesChecked = totalHashesChecked
        self.registeredCount = registeredCount
    }
}

// MARK: - Contact Sync Status

/// Rehber senkronizasyon durumu
public enum ContactSyncStatus: Equatable {
    case idle
    case syncing
    case completed(result: ContactDiscoveryResult)
    case failed(error: ContactError)

    public static func == (lhs: ContactSyncStatus, rhs: ContactSyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.syncing, .syncing):
            return true
        case (.completed(let lResult), .completed(let rResult)):
            return lResult.discoveredContacts.count == rResult.discoveredContacts.count
        case (.failed(let lError), .failed(let rError)):
            return lError.localizedDescription == rError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Contact Error

/// Rehber işlemlerinde oluşabilecek hatalar
public enum ContactError: LocalizedError {
    case permissionDenied
    case contactsAccessFailed
    case normalizationFailed(phoneNumber: String)
    case discoveryFailed(underlying: Error)
    case hashingFailed
    case networkError(underlying: Error)
    case storageError(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Contacts permission denied"
        case .contactsAccessFailed:
            return "Failed to access contacts"
        case .normalizationFailed(let phoneNumber):
            return "Failed to normalize phone number: \(phoneNumber)"
        case .discoveryFailed(let error):
            return "Contact discovery failed: \(error.localizedDescription)"
        case .hashingFailed:
            return "Phone number hashing failed"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        }
    }
}