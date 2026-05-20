package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.usecase.UpdateContactNamesUseCase
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import com.securechat.storage.domain.Conversation
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Konusma listesi ekrani ViewModel'i.
 * Tum konusmalari ve baglanti durumunu yonetir.
 */
@HiltViewModel
class ConversationsViewModel @Inject constructor(
    private val messageRepository: MessageRepository,
    private val signalingClient: SignalingClient,
    private val updateContactNamesUseCase: UpdateContactNamesUseCase
) : ViewModel() {

    /** Aktif (arşivlenmemiş) konuşmaların reaktif listesi. */
    val conversations: StateFlow<List<Conversation>> = messageRepository.getConversations()
        .map { list -> list.filter { !it.isArchived } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Arşivlenmiş konuşmaların reaktif listesi. */
    val archivedConversations: StateFlow<List<Conversation>> = messageRepository.getArchivedConversations()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Signaling sunucusu baglanti durumu. */
    val connectionState: StateFlow<ConnectionState> = signalingClient.connectionState
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ConnectionState.Disconnected)

    init {
        // Ana ekrandayken current chat'i "conversations" olarak set et
        // Boylece diger sohbetlerden gelen mesajlar icin bildirim gosterilir
        IncomingMessageHandler.currentChatId = "conversations"
        android.util.Log.d("ConversationsViewModel", "Current chat set to: conversations")

        // Sureli mesajlari acilista bir kez temizle — konusma listesinde bayat preview kalmasin.
        // MessageRepositoryImpl etkilenen konusmalarin lastMessage'ini da tazeler.
        viewModelScope.launch {
            runCatching { messageRepository.deleteExpiredMessages() }
        }
    }

    override fun onCleared() {
        super.onCleared()
        // Ana ekran kapatildiginda current chat'i temizle
        IncomingMessageHandler.currentChatId = null
        android.util.Log.d("ConversationsViewModel", "Current chat cleared from conversations")
    }

    /**
     * Belirtilen konusmayi ve tum mesajlarini siler.
     *
     * @param conversationId Silinecek konusmanin kimlik numarasi
     */
    fun deleteConversation(conversationId: String) {
        viewModelScope.launch {
            messageRepository.deleteConversation(conversationId)
        }
    }

    /**
     * Konuşmayı arşivler.
     */
    fun archiveConversation(conversationId: String) {
        viewModelScope.launch {
            messageRepository.updateConversationArchived(conversationId, true)
        }
    }

    /**
     * Konuşmayı arşivden çıkarır.
     */
    fun unarchiveConversation(conversationId: String) {
        viewModelScope.launch {
            messageRepository.updateConversationArchived(conversationId, false)
        }
    }

    /**
     * Konuşmayı favorilere ekler/çıkarır.
     */
    fun toggleFavorite(conversationId: String, isFavorite: Boolean) {
        viewModelScope.launch {
            messageRepository.updateConversationFavorite(conversationId, isFavorite)
        }
    }

    fun toggleMuted(conversationId: String, isMuted: Boolean) {
        viewModelScope.launch {
            messageRepository.updateConversationMuted(conversationId, isMuted)
        }
    }

    // --- Global mesaj arama ---

    private val _globalSearchResults = MutableStateFlow<List<LocalMessage>>(emptyList())
    val globalSearchResults: StateFlow<List<LocalMessage>> = _globalSearchResults.asStateFlow()

    private val _isGlobalSearching = MutableStateFlow(false)
    val isGlobalSearching: StateFlow<Boolean> = _isGlobalSearching.asStateFlow()

    fun searchGlobal(query: String) {
        if (query.length < 2) {
            _globalSearchResults.value = emptyList()
            return
        }
        viewModelScope.launch {
            _isGlobalSearching.value = true
            _globalSearchResults.value = messageRepository.searchAllMessages(query)
            _isGlobalSearching.value = false
        }
    }

    fun clearGlobalSearch() {
        _globalSearchResults.value = emptyList()
    }

    /** DEBUG: Test sohbeti olusturur. */
    fun createTestConversation() {
        viewModelScope.launch {
            val testPeerId = "test_user_${System.currentTimeMillis()}"
            val now = System.currentTimeMillis()
            val messages = listOf(
                "Merhaba, nasılsın?",
                "Toplantı saat kaçta?",
                "Tamam, görüşürüz 👋",
                "Belgeyi gönderdim, kontrol eder misin?",
                "Bu akşam müsait misin?"
            )
            // Gelen mesaj kaydet — saveMessage otomatik konusma olusturur
            messageRepository.saveMessage(
                LocalMessage(
                    id = java.util.UUID.randomUUID().toString(),
                    conversationId = testPeerId,
                    senderId = testPeerId,
                    peerId = testPeerId,
                    content = messages.random(),
                    contentType = MessageContentType.TEXT,
                    timestamp = now,
                    status = MessageStatus.DELIVERED,
                    isOutgoing = false
                )
            )
        }
    }

    /**
     * Tüm konuşmaların kişi isimlerini ContactNameResolver ile günceller.
     * Bu fonksiyon uygulama başladığında veya rehber değiştiğinde çağrılmalıdır.
     */
    fun updateContactNames() {
        viewModelScope.launch {
            updateContactNamesUseCase()
        }
    }
}
