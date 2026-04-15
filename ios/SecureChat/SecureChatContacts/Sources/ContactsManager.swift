import Foundation
import Contacts
import Combine

/// iOS Contacts framework ile cihaz rehberinden kişileri okur ve telefon numaralarını E.164 formatına normalize eder.
/// Aynı numaraya sahip tekrar eden kayıtlar otomatik olarak filtrelenir.
public final class ContactsManager: @unchecked Sendable {

    // MARK: - Properties

    private let contactStore: CNContactStore
    private let permissionManager: ContactPermissionManager
    private let phoneNumberNormalizer: PhoneNumberNormalizer

    // MARK: - Initialization

    public init(
        contactStore: CNContactStore = CNContactStore(),
        permissionManager: ContactPermissionManager? = nil,
        phoneNumberNormalizer: PhoneNumberNormalizer = PhoneNumberNormalizer()
    ) {
        self.contactStore = contactStore
        self.permissionManager = permissionManager ?? ContactPermissionManager(contactStore: contactStore)
        self.phoneNumberNormalizer = phoneNumberNormalizer
    }

    // MARK: - Contact Access

    /// Tüm rehber kişilerini okur, numaraları normalize eder ve tekrarları temizler.
    /// - Returns: Normalize edilmiş device contact'lar
    public func getAllContacts() async throws -> [DeviceContact] {
        print("SecureChat: ContactsManager.getAllContacts başladı")

        // İzin kontrolü
        guard await permissionManager.ensurePermission() else {
            throw ContactError.permissionDenied
        }

        do {
            let contacts = try await fetchContacts()
            let normalizedContacts = normalizeContacts(contacts)
            let dedupedContacts = deduplicateContacts(normalizedContacts)

            print("SecureChat: \(contacts.count) kişi okundu, \(normalizedContacts.count) normalize edildi, \(dedupedContacts.count) dedupe edildi")
            return dedupedContacts
        } catch {
            print("SecureChat: Contact okuma hatası: \(error)")
            throw ContactError.contactsAccessFailed
        }
    }

    /// Belirli bir telefon numarası ile kişi arar
    /// - Parameter phoneNumber: Aranacak telefon numarası
    /// - Returns: Bulunan kişi (varsa)
    public func findContact(by phoneNumber: String) async throws -> DeviceContact? {
        let allContacts = try await getAllContacts()
        return allContacts.first { $0.phoneNumber == phoneNumber }
    }

    /// Belirli kişi ID'leri ile kişileri getirir
    /// - Parameter contactIds: Contact identifier'ları
    /// - Returns: Bulunan kişiler
    public func getContacts(byIds contactIds: [String]) async throws -> [DeviceContact] {
        guard await permissionManager.ensurePermission() else {
            throw ContactError.permissionDenied
        }

        let predicate = CNContact.predicateForContacts(withIdentifiers: contactIds)
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]

        do {
            let cnContacts = try contactStore.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            return convertToDeviceContacts(cnContacts)
        } catch {
            throw ContactError.contactsAccessFailed
        }
    }

    // MARK: - Contact Search

    /// Kişi arama (isim veya telefon numarası ile)
    /// - Parameter query: Arama sorgusu
    /// - Returns: Eşleşen kişiler
    public func searchContacts(query: String) async throws -> [DeviceContact] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let allContacts = try await getAllContacts()

        return allContacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(query) ||
            contact.phoneNumber.contains(query)
        }
    }

    // MARK: - Batch Operations

    /// Rehber değişikliklerini toplu olarak kontrol eder (performans için)
    /// - Returns: Değişiklik var mı
    public func hasContactChanges() async -> Bool {
        // iOS Contacts framework'te change tracking için NSPersistentHistoryRequest benzeri bir API yok
        // Bu durumda basit bir implementasyon olarak contact sayısını kontrol edebiliriz
        do {
            let currentCount = try await getAllContacts().count
            return currentCount != getLastKnownContactCount()
        } catch {
            return false
        }
    }

    // MARK: - Contact Observation

    /// CNContactStoreDidChange notification'ını dinler
    /// - Returns: Contact değişiklik publisher'ı
    public func contactChangesPublisher() -> AnyPublisher<Void, Never> {
        NotificationCenter.default
            .publisher(for: .CNContactStoreDidChange)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    // MARK: - Private Methods

    /// CNContactStore'dan kişileri fetch eder
    private func fetchContacts() async throws -> [CNContact] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]

        return try await withCheckedThrowingContinuation { continuation in
            var contacts: [CNContact] = []

            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.sortOrder = .givenName

            do {
                try contactStore.enumerateContacts(with: request) { contact, stop in
                    contacts.append(contact)
                }
                continuation.resume(returning: contacts)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// CNContact'ları DeviceContact'a çevirir ve normalize eder
    private func convertToDeviceContacts(_ cnContacts: [CNContact]) -> [DeviceContact] {
        var deviceContacts: [DeviceContact] = []

        for cnContact in cnContacts {
            let displayName = "\(cnContact.givenName) \(cnContact.familyName)".trimmingCharacters(in: .whitespacesAndNewlines)

            // Avatar URI oluştur (varsa)
            let avatarUri = cnContact.imageDataAvailable ? "contact://\(cnContact.identifier)" : nil

            // Telefon numaralarını işle
            for phoneNumber in cnContact.phoneNumbers {
                let rawNumber = phoneNumber.value.stringValue

                // E.164 formatına normalize et
                if let normalizedNumber = phoneNumberNormalizer.normalizeToE164(rawNumber) {
                    let deviceContact = DeviceContact(
                        id: cnContact.identifier,
                        displayName: displayName.isEmpty ? "Bilinmeyen" : displayName,
                        phoneNumber: normalizedNumber,
                        avatarUri: avatarUri
                    )
                    deviceContacts.append(deviceContact)
                }
            }
        }

        return deviceContacts
    }

    /// Kişileri normalize eder
    private func normalizeContacts(_ cnContacts: [CNContact]) -> [DeviceContact] {
        return convertToDeviceContacts(cnContacts)
    }

    /// Aynı telefon numarasına sahip kişileri temizler
    private func deduplicateContacts(_ contacts: [DeviceContact]) -> [DeviceContact] {
        var uniqueContacts: [String: DeviceContact] = [:]

        for contact in contacts {
            // Aynı telefon numarası varsa, daha uzun isme sahip olanı sakla
            if let existingContact = uniqueContacts[contact.phoneNumber] {
                if contact.displayName.count > existingContact.displayName.count {
                    uniqueContacts[contact.phoneNumber] = contact
                }
            } else {
                uniqueContacts[contact.phoneNumber] = contact
            }
        }

        return Array(uniqueContacts.values).sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    /// Son bilinen contact sayısını döner (UserDefaults'tan)
    private func getLastKnownContactCount() -> Int {
        return UserDefaults.standard.integer(forKey: "SecureChat.LastKnownContactCount")
    }

    /// Contact sayısını kaydet
    private func saveLastKnownContactCount(_ count: Int) {
        UserDefaults.standard.set(count, forKey: "SecureChat.LastKnownContactCount")
    }
}