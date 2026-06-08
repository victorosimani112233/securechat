package com.securechat.app.ui.viewmodel.chat

import com.securechat.app.data.IncomingMessageHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * Faz 9: Karsi taraf typing/presence state'leri — bu sohbete ozel.
 *
 * IncomingMessageHandler global typingStates + presenceStates Map'lerinden
 * sadece conversationId entry'sini filter eder.
 */
class ChatPresenceManager(
    private val conversationId: String,
    scope: CoroutineScope
) {
    private val _peerIsTyping = MutableStateFlow(false)
    val peerIsTyping: StateFlow<Boolean> = _peerIsTyping

    private val _peerPresence = MutableStateFlow<IncomingMessageHandler.PresenceInfo?>(null)
    val peerPresence: StateFlow<IncomingMessageHandler.PresenceInfo?> = _peerPresence

    init {
        // Typing
        scope.launch {
            IncomingMessageHandler.typingStates
                .stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyMap())
                .collect { map -> _peerIsTyping.value = map[conversationId] == true }
        }
        // Presence
        scope.launch {
            IncomingMessageHandler.presenceStates
                .stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyMap())
                .collect { map -> _peerPresence.value = map[conversationId] }
        }
    }
}
