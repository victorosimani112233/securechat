import Foundation
import Combine
import SecureChatStorage

/// Ana kişi yönetimi servisi.
/// Cihaz rehberini okuma, izin yönetimi, kullanıcı keşfi ve yerel storage entegrasyonunu sağlar.
/// WhatsApp benzeri kontakt yönetimi sunar.
public final class ContactsService: ObservableObject, @unchecked Sendable {

    // MARK: - Published Properties

    @Published public private(set) var syncStatus: ContactSyncStatus = .idle
    @Published public private(set) var registeredContacts: [RegisteredContact] = []
    @Published public private(set) var permissionStatus: ContactPermissionStatus = .notDetermined

    // MARK: - Properties

    private let contactsManager: ContactsManager
    private let permissionManager: ContactPermissionManager
    private let discoveryService: ContactDiscoveryService
    private let phoneNumberHasher: PhoneNumberHasher
    private let contactDAO: ContactDAO

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(
        contactsManager: ContactsManager,
        permissionManager: ContactPermissionManager,
        discoveryService: ContactDiscoveryService,
        phoneNumberHasher: PhoneNumberHasher = PhoneNumberHasher(),
        contactDAO: ContactDAO
    ) {
        self.contactsManager = contactsManager
        self.permissionManager = permissionManager
        self.discoveryService = discoveryService
        self.phoneNumberHasher = phoneNumberHasher
        self.contactDAO = contactDAO

        setupObservers()
        loadCachedContacts()
    }

    // MARK: - Permission Management

    /// Rehber izni var mı kontrol eder
    public var hasContactPermission: Bool {
        permissionManager.hasPermission
    }

    /// Rehber iznini talep eder
    @MainActor
    public func requestContactPermission() async -> Bool {
        let granted = await permissionManager.requestPermission()
        permissionStatus = permissionManager.permissionStatus
        return granted
    }

    /// Ayarlar uygulamasını açar (izin reddedildiyse)
    public func openContactSettings() {
        permissionManager.openSettings()
    }

    // MARK: - Contact Sync

    /// Rehber senkronizasyonunu başlatır
    public func syncContacts() async {
        await syncContactsInternal()
    }

    /// Rehber senkronizasyonunu başlatır (internal)
    @MainActor
    private func syncContactsInternal() async {
        guard syncStatus != .syncing else { return }

        syncStatus = .syncing

        do {
            let result = try await discoveryService.discoverRegisteredUsers()

            // Bulunan kişileri yerel storage'a kaydet
            try await saveDiscoveredContacts(result.discoveredContacts)

            // Cached contacts'ı güncelle
            loadCachedContacts()

            syncStatus = .completed(result: result)
            print("SecureChat: Contact sync completed - \(result.registeredCount) registered users found")

        } catch {
            print("SecureChat: Contact sync failed: \(error)")
            syncStatus = .failed(error: error as? ContactError ?? ContactError.discoveryFailed(underlying: error))
        }
    }

    /// Otomatik senkronizasyonu başlatır (rehber değişikliklerinde)
    public func enableAutoSync() {
        discoveryService
            .observeContactChangesAndSync()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("SecureChat: Auto sync failed: \(error)")
                    }
                },
                receiveValue: { [weak self] result in
                    guard let self = self else { return }
                    Task {
                        try? await self.saveDiscoveredContacts(result.discoveredContacts)
                        self.loadCachedContacts()
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Contact Access

    /// Tüm kayıtlı kişileri getirir (cache'den)
    public func getRegisteredContacts() -> [RegisteredContact] {
        return registeredContacts
    }

    /// Telefon numarası ile kayıtlı kişi arar
    public func findRegisteredContact(by phoneNumber: String) -> RegisteredContact? {
        return registeredContacts.first { $0.phoneNumber == phoneNumber }
    }

    /// Kullanıcı ID ile kayıtlı kişi arar
    public func findRegisteredContact(by userId: String) -> RegisteredContact? {
        return registeredContacts.first { $0.userId == userId }
    }

    /// Telefon hash'i ile kayıtlı kişi arar
    public func findRegisteredContact(by phoneHash: String) -> RegisteredContact? {
        return registeredContacts.first { $0.phoneHash == phoneHash }
    }

    // MARK: - Contact Search

    /// Kayıtlı kişiler içinde arama yapar
    public func searchRegisteredContacts(query: String) -> [RegisteredContact] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return registeredContacts
        }

        let lowercasedQuery = query.lowercased()
        return registeredContacts.filter { contact in
            contact.displayName.localizedLowercase.contains(lowercasedQuery) ||
            contact.phoneNumber.contains(query)
        }
    }

    /// Cihaz rehberinde arama yapar (tüm kişiler, kayıtlı olmayan dahil)
    public func searchDeviceContacts(query: String) async throws -> [DeviceContact] {
        return try await contactsManager.searchContacts(query: query)
    }

    // MARK: - Contact Validation

    /// Telefon numarasının SecureChat'e kayıtlı olup olmadığını kontrol eder
    public func isPhoneNumberRegistered(_ phoneNumber: String) -> Bool {
        return registeredContacts.contains { $0.phoneNumber == phoneNumber }
    }

    /// Birden çok telefon numarasını kontrol eder
    public func checkPhoneNumbers(_ phoneNumbers: [String]) async throws -> [RegisteredContact] {
        return try await discoveryService.checkSpecificNumbers(phoneNumbers)
    }

    // MARK: - Manual Contact Addition

    /// Manuel olarak telefon numarası ekler ve kontrol eder
    public func addManualContact(phoneNumber: String, displayName: String? = nil) async throws -> RegisteredContact? {
        let normalizer = PhoneNumberNormalizer()
        guard let normalizedNumber = normalizer.normalizeToE164(phoneNumber) else {
            throw ContactError.normalizationFailed(phoneNumber: phoneNumber)
        }

        let registeredContacts = try await discoveryService.checkSpecificNumbers([normalizedNumber])

        if let registeredContact = registeredContacts.first {
            // Display name'i güncelle eğer manuel olarak verilmişse
            let updatedContact = RegisteredContact(
                userId: registeredContact.userId,
                displayName: displayName ?? registeredContact.displayName,
                phoneNumber: registeredContact.phoneNumber,
                phoneHash: registeredContact.phoneHash,
                avatarUri: registeredContact.avatarUri
            )

            try await saveDiscoveredContacts([updatedContact])
            loadCachedContacts()
            return updatedContact
        }

        return nil
    }

    // MARK: - Contact Export/Import

    /// Kayıtlı kişileri dışa aktarır (backup için)
    public func exportRegisteredContacts() -> Data? {
        do {
            return try JSONEncoder().encode(registeredContacts)
        } catch {
            print("SecureChat: Contact export failed: \(error)")
            return nil
        }
    }

    /// Kayıtlı kişileri içe aktarır (restore için)
    public func importRegisteredContacts(data: Data) async throws {
        do {
            let contacts = try JSONDecoder().decode([RegisteredContact].self, from: data)
            try await saveDiscoveredContacts(contacts)
            loadCachedContacts()
        } catch {
            throw ContactError.storageError(underlying: error)
        }
    }

    // MARK: - Statistics

    /// Kişi istatistiklerini getirir
    public func getContactStatistics() -> ContactStatistics {
        return ContactStatistics(
            totalRegisteredContacts: registeredContacts.count,
            lastSyncDate: getLastSyncDate(),
            syncStatus: syncStatus
        )
    }

    // MARK: - Private Methods

    /// Observer'ları kurar
    private func setupObservers() {
        // Permission değişikliklerini dinle
        permissionManager.observePermissionChanges { [weak self] status in
            DispatchQueue.main.async {
                self?.permissionStatus = status
            }
        }

        // Contact değişikliklerini dinle
        contactsManager
            .contactChangesPublisher()
            .debounce(for: .seconds(5), scheduler: DispatchQueue.global())
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.syncContactsInternal()
                }
            }
            .store(in: &cancellables)
    }

    /// Cache'lenmiş kişileri yükler
    private func loadCachedContacts() {
        Task {
            do {
                let contacts = try await contactDAO.getAll()
                    .compactMap { $0.first }
                    .asyncMap { contact -> RegisteredContact in
                        return RegisteredContact(
                            userId: contact.id,
                            displayName: contact.displayName,
                            phoneNumber: contact.phoneNumber,
                            phoneHash: contact.phoneHash,
                            avatarUri: contact.avatarURI
                        )
                    }

                await MainActor.run {
                    self.registeredContacts = await contacts
                }
            } catch {
                print("SecureChat: Failed to load cached contacts: \(error)")
            }
        }
    }

    /// Keşfedilen kişileri storage'a kaydeder
    private func saveDiscoveredContacts(_ contacts: [RegisteredContact]) async throws {
        let contactDataList = contacts.map { contact in
            ContactData(
                id: contact.userId,
                phoneNumber: contact.phoneNumber,
                phoneHash: contact.phoneHash,
                displayName: contact.displayName,
                isRegistered: true,
                avatarUri: contact.avatarUri,
                lastSeen: Date().timeIntervalSince1970.rounded()
            )
        }

        do {
            try await contactDAO.insertBatch(contactDataList)
        } catch {
            throw ContactError.storageError(underlying: error)
        }
    }

    /// Son sync tarihini getirir
    private func getLastSyncDate() -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: "SecureChat.LastContactSync")
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    /// Son sync tarihini kaydeder
    private func setLastSyncDate(_ date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "SecureChat.LastContactSync")
    }
}

// MARK: - Contact Statistics

/// Kişi istatistikleri
public struct ContactStatistics {
    public let totalRegisteredContacts: Int
    public let lastSyncDate: Date?
    public let syncStatus: ContactSyncStatus

    public var hasNeverSynced: Bool {
        return lastSyncDate == nil
    }

    public var daysSinceLastSync: Int? {
        guard let lastSyncDate = lastSyncDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastSyncDate, to: Date()).day
    }
}

// MARK: - Async Sequence Extensions

private extension Sequence {
    func asyncMap<T>(_ transform: @escaping (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}