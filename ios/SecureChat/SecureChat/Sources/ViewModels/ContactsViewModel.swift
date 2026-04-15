import SwiftUI
import Combine
import SecureChatContacts

/// Kişiler ekranı ViewModel'i.
/// Rehber kişilerini ve kullanıcı keşfini yönetir.
@MainActor
public class ContactsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published public var uiState = ContactsUIState()
    @Published public var contacts: [ContactInfo] = []
    @Published public var hasPermission: Bool = false

    // MARK: - Private Properties

    private let contactsManager: ContactsManager
    private let contactDiscoveryService: ContactDiscoveryService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(contactsManager: ContactsManager = ContactsManager.shared,
               contactDiscoveryService: ContactDiscoveryService = ContactDiscoveryService.shared) {
        self.contactsManager = contactsManager
        self.contactDiscoveryService = contactDiscoveryService

        setupSubscriptions()
        checkPermissions()
    }

    // MARK: - Public Methods

    /// Kişi izni iste
    public func requestPermission() {
        Task {
            do {
                let granted = try await contactsManager.requestPermission()
                self.hasPermission = granted
                self.uiState.hasPermission = granted

                if granted {
                    await loadContacts()
                }
            } catch {
                print("Kişi izni istenirken hata oluştu: \(error)")
            }
        }
    }

    /// Kişileri yenile
    public func refreshContacts() {
        guard hasPermission else { return }

        Task {
            await loadContacts()
        }
    }

    /// Arama sorgusunu güncelle
    public func updateSearchQuery(_ query: String) {
        uiState.searchQuery = query
    }

    /// Filtrelenmiş kişi listesi
    public var filteredContacts: [ContactInfo] {
        if uiState.searchQuery.isEmpty {
            return contacts
        } else {
            return contacts.filter { contact in
                contact.displayName.localizedCaseInsensitiveContains(uiState.searchQuery) ||
                contact.phoneNumber.contains(uiState.searchQuery)
            }
        }
    }

    /// SecureChat kullanıcısı olan kişiler
    public var secureChatUsers: [ContactInfo] {
        return filteredContacts.filter { $0.isSecureChatUser }
    }

    /// SecureChat kullanıcısı olmayan kişiler
    public var nonSecureChatUsers: [ContactInfo] {
        return filteredContacts.filter { !$0.isSecureChatUser }
    }

    /// Kişi ile sohbet başlat
    public func startChat(with contact: ContactInfo) -> String? {
        guard contact.isSecureChatUser else { return nil }

        // Kişinin SecureChat kullanıcı ID'sini döndür
        return contact.secureChatUserId
    }

    /// Kişiyi SecureChat'e davet et
    public func inviteContact(_ contact: ContactInfo) {
        Task {
            do {
                // TODO: Davet işlemi implementasyonu
                print("Kişi davet edildi: \(contact.displayName)")
            } catch {
                print("Kişi davet edilirken hata oluştu: \(error)")
            }
        }
    }

    // MARK: - Private Methods

    private func setupSubscriptions() {
        // Kişileri dinle
        contactsManager.contactsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] contacts in
                self?.contacts = contacts
                self?.uiState.contacts = contacts
            }
            .store(in: &cancellables)
    }

    private func checkPermissions() {
        Task {
            let granted = await contactsManager.hasPermission()
            self.hasPermission = granted
            self.uiState.hasPermission = granted

            if granted {
                await loadContacts()
            }
        }
    }

    private func loadContacts() async {
        uiState.isLoading = true

        do {
            let allContacts = try await contactsManager.loadContacts()

            // Kişilerin SecureChat kullanıcısı olup olmadığını kontrol et
            let discoveredContacts = try await contactDiscoveryService.discoverUsers(from: allContacts)

            self.contacts = discoveredContacts
            self.uiState.contacts = discoveredContacts
        } catch {
            print("Kişiler yüklenirken hata oluştu: \(error)")
        }

        uiState.isLoading = false
    }
}