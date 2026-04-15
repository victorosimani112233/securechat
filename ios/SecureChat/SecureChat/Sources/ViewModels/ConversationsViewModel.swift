import SwiftUI
import Combine
import SecureChatStorage
import SecureChatNetwork

/// Konuşma listesi ekranı ViewModel'i.
/// Tüm konuşmaları ve bağlantı durumunu yönetir.
@MainActor
public class ConversationsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published public var uiState = ConversationsUIState()
    @Published public var conversations: [Conversation] = []
    @Published public var connectionState: ConnectionState = .disconnected

    // MARK: - Private Properties

    private let messageRepository: MessageRepository
    private let signalingClient: SignalingClient
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(messageRepository: MessageRepository = MessageRepository.shared,
               signalingClient: SignalingClient = SignalingClient.shared) {
        self.messageRepository = messageRepository
        self.signalingClient = signalingClient

        setupSubscriptions()
    }

    // MARK: - Public Methods

    /// Konuşma listesini yenile
    public func refreshConversations() {
        // Konuşmalar otomatik olarak repository'den gelir
    }

    /// Belirtilen konuşmayı ve tüm mesajlarını siler
    public func deleteConversation(_ conversationId: String) {
        Task {
            do {
                try await messageRepository.deleteConversation(conversationId)
            } catch {
                print("Konuşma silinirken hata oluştu: \(error)")
            }
        }
    }

    /// Arama sorgusunu güncelle
    public func updateSearchQuery(_ query: String) {
        uiState.searchQuery = query
    }

    /// Arama görünürlüğünü değiştir
    public func toggleSearchVisibility() {
        uiState.isSearchVisible.toggle()
        if !uiState.isSearchVisible {
            uiState.searchQuery = ""
        }
    }

    /// Filtrelenmiş konuşma listesi
    public var filteredConversations: [Conversation] {
        if uiState.searchQuery.isEmpty {
            return conversations
        } else {
            return conversations.filter { conversation in
                conversation.peerName.localizedCaseInsensitiveContains(uiState.searchQuery) ||
                (conversation.lastMessage?.localizedCaseInsensitiveContains(uiState.searchQuery) ?? false)
            }
        }
    }

    // MARK: - Private Methods

    private func setupSubscriptions() {
        // Konuşmaları dinle
        messageRepository.getConversations()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversations in
                self?.conversations = conversations
                self?.uiState.conversations = conversations
            }
            .store(in: &cancellables)

        // Bağlantı durumunu dinle
        signalingClient.connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                self?.uiState.connectionState = state
            }
            .store(in: &cancellables)
    }
}