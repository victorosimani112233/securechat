import Foundation
import Combine

/// Gizlilik öncelikli kullanıcı keşfi servisi.
/// Telefon numaralarını SHA-256 ile hash'leyerek sunucuya gönderir,
/// plaintext numara ASLA sunucuya iletilmez.
/// Eşleşen kullanıcılar yerel veritabanına kaydedilir.
public final class ContactDiscoveryService: @unchecked Sendable {

    // MARK: - Properties

    private let contactsManager: ContactsManager
    private let phoneNumberHasher: PhoneNumberHasher
    private let networkService: ContactDiscoveryNetworkService

    // MARK: - Initialization

    public init(
        contactsManager: ContactsManager,
        phoneNumberHasher: PhoneNumberHasher = PhoneNumberHasher(),
        networkService: ContactDiscoveryNetworkService
    ) {
        self.contactsManager = contactsManager
        self.phoneNumberHasher = phoneNumberHasher
        self.networkService = networkService
    }

    // MARK: - Contact Discovery

    /// Cihaz rehberindeki numaraları hash'leyerek sunucuda kayıtlı kullanıcıları bulur.
    /// Eşleşen kişiler yerel storage'a kaydedilir.
    /// - Returns: Bulunan kayıtlı kişiler
    public func discoverRegisteredUsers() async throws -> ContactDiscoveryResult {
        print("SecureChat: Contact discovery başladı")

        // Cihaz rehberinden kişileri al
        let deviceContacts = try await contactsManager.getAllContacts()
        guard !deviceContacts.isEmpty else {
            print("SecureChat: Cihaz rehberi boş")
            return ContactDiscoveryResult(
                discoveredContacts: [],
                totalHashesChecked: 0,
                registeredCount: 0
            )
        }

        // Telefon numaralarını hash'le
        let hashMapping = phoneNumberHasher.createHashMapping(from: deviceContacts)
        guard !hashMapping.isEmpty else {
            print("SecureChat: Hash oluşturma başarısız")
            throw ContactError.hashingFailed
        }

        print("SecureChat: \(hashMapping.count) telefon numarası hash'lendi")

        do {
            // Hash'leri sunucuya gönder (plaintext numara GÖNDERİLMEZ)
            let request = CheckUsersRequest(hashes: Array(hashMapping.keys))
            let response = try await networkService.checkRegisteredUsers(request)

            print("SecureChat: \(response.users.count) kayıtlı kullanıcı bulundu")

            // Sunucudan dönen hash'lerle eşleşen cihaz kişilerini bul
            let registeredContacts = mapToRegisteredContacts(
                serverUsers: response.users,
                hashMapping: hashMapping
            )

            let result = ContactDiscoveryResult(
                discoveredContacts: registeredContacts,
                totalHashesChecked: hashMapping.count,
                registeredCount: registeredContacts.count
            )

            print("SecureChat: Contact discovery tamamlandı - \(registeredContacts.count) kayıtlı kişi")
            return result

        } catch {
            print("SecureChat: Contact discovery network hatası: \(error)")
            throw ContactError.networkError(underlying: error)
        }
    }

    /// Belirli telefon numaralarının kayıtlı olup olmadığını kontrol eder
    /// - Parameter phoneNumbers: Kontrol edilecek telefon numaraları (E.164 format)
    /// - Returns: Kayıtlı olan numaralar
    public func checkSpecificNumbers(_ phoneNumbers: [String]) async throws -> [RegisteredContact] {
        guard !phoneNumbers.isEmpty else {
            return []
        }

        // Telefon numaralarını hash'le
        let hashes = phoneNumberHasher.createHashes(from: phoneNumbers)
        guard !hashes.isEmpty else {
            throw ContactError.hashingFailed
        }

        do {
            let request = CheckUsersRequest(hashes: hashes)
            let response = try await networkService.checkRegisteredUsers(request)

            // Device contact'lar olmadığı için manuel mapping
            var registeredContacts: [RegisteredContact] = []
            for serverUser in response.users {
                // Hash'ten orijinal numarayı bul
                for phoneNumber in phoneNumbers {
                    if let hash = phoneNumberHasher.hashPhoneNumber(phoneNumber),
                       hash == serverUser.phoneHash {
                        let contact = RegisteredContact(
                            userId: serverUser.userId,
                            displayName: phoneNumber, // Display name yok, numara kullan
                            phoneNumber: phoneNumber,
                            phoneHash: serverUser.phoneHash
                        )
                        registeredContacts.append(contact)
                        break
                    }
                }
            }

            return registeredContacts
        } catch {
            throw ContactError.networkError(underlying: error)
        }
    }

    /// Rehber değişikliklerini dinler ve otomatik sync yapar
    /// - Returns: Discovery result publisher
    public func observeContactChangesAndSync() -> AnyPublisher<ContactDiscoveryResult, Error> {
        return contactsManager
            .contactChangesPublisher()
            .debounce(for: .seconds(2), scheduler: DispatchQueue.global()) // Throttle changes
            .asyncMap { [weak self] _ in
                guard let self = self else {
                    throw ContactError.discoveryFailed(underlying: NSError(domain: "ContactDiscoveryService", code: -1))
                }
                return try await self.discoverRegisteredUsers()
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Batch Discovery

    /// Büyük rehberler için sayfalı (paginated) discovery
    /// - Parameter batchSize: Her batch'teki hash sayısı
    /// - Returns: Discovery result stream
    public func discoverRegisteredUsersBatched(batchSize: Int = 1000) -> AsyncThrowingStream<ContactDiscoveryResult, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let deviceContacts = try await contactsManager.getAllContacts()
                    let hashMapping = phoneNumberHasher.createHashMapping(from: deviceContacts)

                    let hashPairs = Array(hashMapping)
                    let batches = hashPairs.chunked(into: batchSize)

                    var allRegisteredContacts: [RegisteredContact] = []

                    for (index, batch) in batches.enumerated() {
                        let batchHashes = batch.map { $0.key }
                        let batchMapping = Dictionary(batch, uniquingKeysWith: { first, _ in first })

                        let request = CheckUsersRequest(hashes: batchHashes)
                        let response = try await networkService.checkRegisteredUsers(request)

                        let batchRegisteredContacts = mapToRegisteredContacts(
                            serverUsers: response.users,
                            hashMapping: batchMapping
                        )

                        allRegisteredContacts.append(contentsOf: batchRegisteredContacts)

                        // Her batch sonrası ara sonuç döner
                        let intermediateResult = ContactDiscoveryResult(
                            discoveredContacts: batchRegisteredContacts,
                            totalHashesChecked: batchHashes.count,
                            registeredCount: batchRegisteredContacts.count
                        )

                        continuation.yield(intermediateResult)

                        print("SecureChat: Batch \(index + 1)/\(batches.count) tamamlandı")
                    }

                    // Final sonuç
                    let finalResult = ContactDiscoveryResult(
                        discoveredContacts: allRegisteredContacts,
                        totalHashesChecked: hashMapping.count,
                        registeredCount: allRegisteredContacts.count
                    )

                    continuation.yield(finalResult)
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// ServerUser'ları RegisteredContact'lara çevirir
    private func mapToRegisteredContacts(
        serverUsers: [ServerUser],
        hashMapping: [String: DeviceContact]
    ) -> [RegisteredContact] {
        return serverUsers.compactMap { serverUser in
            guard let deviceContact = hashMapping[serverUser.phoneHash] else {
                return nil
            }

            return RegisteredContact(
                userId: serverUser.userId,
                displayName: deviceContact.displayName,
                phoneNumber: deviceContact.phoneNumber,
                phoneHash: serverUser.phoneHash,
                avatarUri: deviceContact.avatarUri
            )
        }
    }
}

// MARK: - Contact Discovery Network Service

/// Network layer abstraction for contact discovery
public protocol ContactDiscoveryNetworkService: Sendable {
    func checkRegisteredUsers(_ request: CheckUsersRequest) async throws -> CheckUsersResponse
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Publisher Extensions

extension Publisher {
    func asyncMap<T>(_ transform: @escaping (Output) async throws -> T) -> Publishers.FlatMap<Future<T, Error>, Self> {
        return flatMap { value in
            Future { promise in
                Task {
                    do {
                        let result = try await transform(value)
                        promise(.success(result))
                    } catch {
                        promise(.failure(error))
                    }
                }
            }
        }
    }
}