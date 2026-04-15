import SwiftUI
import Combine
import SecureChatStorage
import SecureChatNetwork
import SecureChatContacts

/// Sohbet ekranı ViewModel'i.
/// Mesaj gönderme, alma ve konuşma bilgilerini yönetir.
@MainActor
public class ChatViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published public var uiState = ChatUIState()
    @Published public var messages: [LocalMessage] = []
    @Published public var conversationInfo: ConversationInfo?

    // MARK: - Private Properties

    private let conversationId: String
    private let messageRepository: MessageRepository
    private let contactsManager: ContactsManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    public init(conversationId: String,
               messageRepository: MessageRepository = MessageRepository.shared,
               contactsManager: ContactsManager = ContactsManager.shared) {
        self.conversationId = conversationId
        self.messageRepository = messageRepository
        self.contactsManager = contactsManager

        setupSubscriptions()
        loadConversationInfo()
        markMessagesAsRead()
    }

    // MARK: - Public Methods

    /// Mesaj gönder
    public func sendMessage(_ content: String) {
        guard !content.isEmpty else { return }

        uiState.messageText = ""

        Task {
            do {
                try await messageRepository.sendMessage(
                    conversationId: conversationId,
                    content: content,
                    contentType: .text
                )
            } catch {
                print("Mesaj gönderilirken hata oluştu: \(error)")
            }
        }
    }

    /// Mesaj metnini güncelle
    public func updateMessageText(_ text: String) {
        uiState.messageText = text
    }

    /// Sesli arama başlat
    public func startVoiceCall() -> String? {
        return conversationInfo?.peerId
    }

    /// Görüntülü arama başlat
    public func startVideoCall() -> String? {
        return conversationInfo?.peerId
    }

    /// Dosya gönder
    public func sendFile(at url: URL) {
        Task {
            do {
                // TODO: Dosya yükleme implementasyonu
                // Şimdilik dosya adını text olarak gönder
                try await messageRepository.sendMessage(
                    conversationId: conversationId,
                    content: "📎 \(url.lastPathComponent)",
                    contentType: .text
                )
            } catch {
                print("Dosya gönderilirken hata oluştu: \(error)")
            }
        }
    }

    /// Mesajları okundu olarak işaretle
    public func markMessagesAsRead() {
        Task {
            do {
                try await messageRepository.markMessagesAsRead(conversationId: conversationId)
            } catch {
                print("Mesajlar okundu işaretlenirken hata oluştu: \(error)")
            }
        }
    }

    // MARK: - Private Methods

    private func setupSubscriptions() {
        // Mesajları dinle
        messageRepository.getMessages(conversationId: conversationId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] messages in
                self?.messages = messages
                self?.uiState.messages = messages
            }
            .store(in: &cancellables)
    }

    private func loadConversationInfo() {
        Task {
            do {
                // Konuşma bilgilerini yükle
                if let conversation = try await messageRepository.getConversation(id: conversationId) {
                    let info = ConversationInfo(
                        id: conversation.id,
                        peerName: conversation.peerName,
                        peerId: conversation.peerId,
                        isGroup: conversation.isGroup,
                        isOnline: false, // TODO: Online durumu kontrol et
                        lastSeen: nil // TODO: Son görülme zamanını kontrol et
                    )
                    self.conversationInfo = info
                    self.uiState.conversationInfo = info
                }
            } catch {
                print("Konuşma bilgileri yüklenirken hata oluştu: \(error)")
            }
        }
    }
}