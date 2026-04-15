import Foundation
import SignalProtocolKit

/// Signal Protocol'un gerektirdiği tüm store interface'lerini implement eder.
/// Async storage interface'lerini Signal'in sync interface'lerine köprüler.
///
/// NOT: Signal Protocol sync erişim gerektirdiğinden, storage çağrıları
/// sync olarak yapılır ancak internal async store'lar kullanılır.
///
/// GÜVENLIK: Private key ASLA loga yazılmaz.
public class SecureChatProtocolStore {

    // MARK: - Properties

    private let identityStore: CryptoIdentityStore
    private let preKeyStore: CryptoPreKeyStore
    private let signedPreKeyStore: CryptoSignedPreKeyStore
    private let sessionStore: CryptoSessionStore

    // MARK: - Initialization

    public init(
        identityStore: CryptoIdentityStore,
        preKeyStore: CryptoPreKeyStore,
        signedPreKeyStore: CryptoSignedPreKeyStore,
        sessionStore: CryptoSessionStore
    ) {
        self.identityStore = identityStore
        self.preKeyStore = preKeyStore
        self.signedPreKeyStore = signedPreKeyStore
        self.sessionStore = sessionStore
    }

    // MARK: - Async Helper Methods

    /// Mevcut kullanılabilir PreKey sayısını döndürür.
    /// PreKey yenileme kararı için kullanılır.
    public func getAvailablePreKeyCount() async -> Int {
        return await preKeyStore.getAvailablePreKeyCount()
    }

    /// Sıradaki PreKey ID'sini döndürür.
    /// Yeni PreKey batch üretiminde başlangıç ID olarak kullanılır.
    public func getNextPreKeyId() async -> UInt32 {
        return await preKeyStore.getNextPreKeyId()
    }

    /// Local registration ID'yi döndürür (async version)
    public func getLocalRegistrationId() async -> UInt32 {
        return await identityStore.getLocalRegistrationId()
    }
}

// MARK: - SPKIdentityKeyStore Protocol

extension SecureChatProtocolStore: SPKIdentityKeyStore {

    public func identityKeyPair() -> SPKIdentityKeyPair? {
        // Sync olarak çağrıldığı için Task.synchronous kullanıyoruz
        return Task {
            guard let bytes = await identityStore.getIdentityKeyPair() else {
                return nil
            }
            return try? SPKIdentityKeyPair(bytes: bytes)
        }.result
    }

    public func localRegistrationId() -> UInt32 {
        return Task {
            await identityStore.getLocalRegistrationId()
        }.result ?? 0
    }

    public func save(identity: SPKIdentityKey, for address: SPKAddress) -> Bool {
        let success = Task {
            await identityStore.storeIdentity(address.name, identityKey: identity.keyBytes)
        }.result ?? false
        return success
    }

    public func isTrustedIdentity(_ identity: SPKIdentityKey, for address: SPKAddress, direction: SPKDirection) -> Bool {
        let result = Task {
            if let existingKey = await identityStore.loadIdentity(address.name) {
                return existingKey == identity.keyBytes
            }
            return true // İlk görülme güvenilir kabul edilir
        }.result ?? false
        return result
    }

    public func identity(for address: SPKAddress) -> SPKIdentityKey? {
        return Task {
            guard let keyData = await identityStore.loadIdentity(address.name) else {
                return nil
            }
            return try? SPKIdentityKey(keyData: keyData)
        }.result
    }
}

// MARK: - SPKPreKeyStore Protocol

extension SecureChatProtocolStore: SPKPreKeyStore {

    public func loadPreKey(for preKeyId: UInt32) -> SPKPreKeyRecord? {
        return Task {
            guard let bytes = await preKeyStore.loadPreKey(preKeyId) else {
                return nil
            }
            return try? SPKPreKeyRecord(bytes: bytes)
        }.result
    }

    public func store(_ preKey: SPKPreKeyRecord, for preKeyId: UInt32) {
        Task {
            await preKeyStore.storePreKey(preKeyId, record: preKey.data)
        }.result
    }

    public func containsPreKey(for preKeyId: UInt32) -> Bool {
        return Task {
            await preKeyStore.containsPreKey(preKeyId)
        }.result ?? false
    }

    public func removePreKey(for preKeyId: UInt32) {
        Task {
            await preKeyStore.removePreKey(preKeyId)
        }.result
    }
}

// MARK: - SPKSignedPreKeyStore Protocol

extension SecureChatProtocolStore: SPKSignedPreKeyStore {

    public func loadSignedPreKey(for signedPreKeyId: UInt32) -> SPKSignedPreKeyRecord? {
        return Task {
            guard let bytes = await signedPreKeyStore.loadSignedPreKey(signedPreKeyId) else {
                return nil
            }
            return try? SPKSignedPreKeyRecord(bytes: bytes)
        }.result
    }

    public func store(_ signedPreKey: SPKSignedPreKeyRecord, for signedPreKeyId: UInt32) {
        Task {
            await signedPreKeyStore.storeSignedPreKey(signedPreKeyId, record: signedPreKey.data)
        }.result
    }

    public func containsSignedPreKey(for signedPreKeyId: UInt32) -> Bool {
        return Task {
            await signedPreKeyStore.containsSignedPreKey(signedPreKeyId)
        }.result ?? false
    }

    public func removeSignedPreKey(for signedPreKeyId: UInt32) {
        Task {
            await signedPreKeyStore.removeSignedPreKey(signedPreKeyId)
        }.result
    }

    public func loadAllSignedPreKeys() -> [SPKSignedPreKeyRecord] {
        return Task {
            let allRecords = await signedPreKeyStore.loadAllSignedPreKeys()
            return allRecords.compactMap { try? SPKSignedPreKeyRecord(bytes: $0) }
        }.result ?? []
    }
}

// MARK: - SPKSessionStore Protocol

extension SecureChatProtocolStore: SPKSessionStore {

    public func loadSession(for address: SPKAddress) -> SPKSessionRecord? {
        return Task {
            guard let bytes = await sessionStore.loadSession(address.name, deviceId: address.deviceId) else {
                // Yeni boş session oluştur
                return try? SPKSessionRecord()
            }
            return try? SPKSessionRecord(bytes: bytes)
        }.result
    }

    public func storeSession(_ session: SPKSessionRecord, for address: SPKAddress) {
        Task {
            await sessionStore.storeSession(address.name, deviceId: address.deviceId, sessionData: session.data)
        }.result
    }

    public func containsSession(for address: SPKAddress) -> Bool {
        return Task {
            await sessionStore.containsSession(address.name, deviceId: address.deviceId)
        }.result ?? false
    }

    public func deleteSession(for address: SPKAddress) {
        Task {
            await sessionStore.deleteSession(address.name, deviceId: address.deviceId)
        }.result
    }

    public func deleteAllSessions(for name: String) {
        Task {
            await sessionStore.deleteAllSessions(name)
        }.result
    }

    public func subDeviceSessions(for name: String) -> [NSNumber] {
        return Task {
            let deviceIds = await sessionStore.getSubDeviceSessions(name)
            return deviceIds.map { NSNumber(value: $0) }
        }.result ?? []
    }
}

// MARK: - Task Synchronous Helper

private extension Task where Failure == Never {
    /// Task'i sync olarak çalıştırmak için helper
    var result: Success? {
        if #available(iOS 16.0, *) {
            return self.value
        } else {
            // iOS 15 ve altı için DispatchSemaphore kullanarak sync yapma
            var result: Success?
            let semaphore = DispatchSemaphore(value: 0)

            Task {
                result = await self.value
                semaphore.signal()
            }

            semaphore.wait()
            return result
        }
    }
}