package com.securechat.app.ui.viewmodel.chat

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.repository.MessageRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Faz 9: Sureli mesaj timer state + propagation + cleanup worker.
 *
 * - duration StateFlow (ms, 0 = kapali)
 * - setDuration: lokal DB update + grup/birebir uyelere DisappearingTimer signal
 * - startCleanupLoop: viewModelScope'ta periyodik deleteExpiredMessages
 *   (duration'a gore dinamik interval).
 */
class ChatDisappearingManager(
    private val conversationId: String,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val conversationDao: ConversationDao,
    private val messageRepository: MessageRepository
) {
    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()

    /** Disaridan baslangic degeri (init load sirasinda). */
    fun setLocalCachedDuration(value: Long) {
        _duration.value = value
    }

    suspend fun setDuration(newDuration: Long) {
        _duration.value = newDuration
        messageRepository.updateDisappearingDuration(conversationId, newDuration)

        val userId = userSession.userId ?: return
        val conv = conversationDao.getById(conversationId) ?: return

        if (conv.isGroup) {
            val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            for (memberId in members) {
                if (memberId == userId) continue
                signalingClient.sendSignal(
                    SignalMessage.DisappearingTimer(
                        senderId = userId,
                        recipientId = memberId,
                        timestamp = System.currentTimeMillis(),
                        duration = newDuration,
                        conversationId = conversationId
                    )
                )
            }
        } else {
            signalingClient.sendSignal(
                SignalMessage.DisappearingTimer(
                    senderId = userId,
                    recipientId = conv.peerId,
                    timestamp = System.currentTimeMillis(),
                    duration = newDuration,
                    conversationId = conversationId
                )
            )
        }
    }

    /**
     * Periyodik cleanup loop'unu baslatir.
     * Interval duration'a gore dinamik: kisa timer (60sn alti) 5sn,
     * orta (60sn-1sa) 15sn, uzun (>1sa) 60sn — batarya dostu.
     */
    fun startCleanupLoop(scope: CoroutineScope) {
        scope.launch {
            // Ilk acilis cleanup'i — onceki seansta dolan mesajlar varsa hemen gitsin
            runCatching { messageRepository.deleteExpiredMessages() }
            while (true) {
                val intervalMs = when {
                    _duration.value in 1..60_000L -> 5_000L
                    _duration.value in 60_001..3_600_000L -> 15_000L
                    else -> 60_000L
                }
                delay(intervalMs)
                val deleted = messageRepository.deleteExpiredMessages()
                if (deleted > 0) {
                    android.util.Log.d("ChatDisappearing", "Sureli mesaj temizlendi: $deleted")
                }
            }
        }
    }
}
