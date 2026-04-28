package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.SendMessageUseCase
import com.securechat.storage.domain.Conversation
import com.securechat.storage.repository.MessageRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Toplu mesaj gonderim ViewModel'i.
 * Secilen alicilara ayni mesaji tek seferde gonderir.
 */
@HiltViewModel
class BulkMessageViewModel @Inject constructor(
    private val messageRepository: MessageRepository,
    private val sendMessageUseCase: SendMessageUseCase,
    private val userSession: UserSession
) : ViewModel() {

    /** Tum konusmalar — alici secimi icin. */
    val conversations: StateFlow<List<Conversation>> = messageRepository.getConversations()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Mesaj icerigi. */
    private val _messageContent = MutableStateFlow("")
    val messageContent: StateFlow<String> = _messageContent.asStateFlow()

    /** Secilen alici ID'leri. */
    private val _selectedRecipientIds = MutableStateFlow<Set<String>>(emptySet())
    val selectedRecipientIds: StateFlow<Set<String>> = _selectedRecipientIds.asStateFlow()

    /** Gonderim devam ediyor mu. */
    private val _isSending = MutableStateFlow(false)
    val isSending: StateFlow<Boolean> = _isSending.asStateFlow()

    /** Gonderim tamamlandiginda tetiklenir — ekrandan geri donmek icin. */
    private val _sendComplete = MutableSharedFlow<Unit>()
    val sendComplete = _sendComplete.asSharedFlow()

    fun setMessageContent(content: String) {
        _messageContent.value = content
    }

    fun toggleRecipient(peerId: String) {
        val current = _selectedRecipientIds.value
        _selectedRecipientIds.value = if (peerId in current) {
            current - peerId
        } else {
            current + peerId
        }
    }

    fun selectAll(conversations: List<Conversation>) {
        _selectedRecipientIds.value = conversations.map { it.peerId }.toSet()
    }

    fun deselectAll() {
        _selectedRecipientIds.value = emptySet()
    }

    /**
     * Secilen tum alicilara mesaji gonderir.
     * Her alici icin sendMessageUseCase cagirilir (conversationId = peerId).
     */
    fun sendBulkMessage() {
        val content = _messageContent.value.trim()
        val recipients = _selectedRecipientIds.value
        if (content.isBlank() || recipients.isEmpty()) return

        viewModelScope.launch {
            _isSending.value = true
            try {
                for (recipientId in recipients) {
                    sendMessageUseCase(
                        conversationId = recipientId,
                        content = content
                    )
                }
            } finally {
                _isSending.value = false
                _messageContent.value = ""
                _selectedRecipientIds.value = emptySet()
                _sendComplete.emit(Unit)
            }
        }
    }
}
