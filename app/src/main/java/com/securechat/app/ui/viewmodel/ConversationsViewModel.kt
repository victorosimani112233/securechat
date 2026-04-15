package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.usecase.UpdateContactNamesUseCase
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import com.securechat.storage.domain.Conversation
import com.securechat.storage.repository.MessageRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
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
     * Tüm konuşmaların kişi isimlerini ContactNameResolver ile günceller.
     * Bu fonksiyon uygulama başladığında veya rehber değiştiğinde çağrılmalıdır.
     */
    fun updateContactNames() {
        viewModelScope.launch {
            updateContactNamesUseCase()
        }
    }
}
