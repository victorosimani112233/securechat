package com.securechat.app.ui.viewmodel.chat

import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.ObserveMessagesUseCase
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Sohbet acikken gelen mesajlar icin READ receipt + DB durumu yonetimi.
 *
 * Faz 9: ChatViewModel.markIncomingMessagesAsRead() ve readReceiptSentIds
 * extract edildi. Davranis aynidir; ChatViewModel artik delegate eder.
 *
 * Davranis ozeti:
 *   - observeMessagesUseCase + isAppInForegroundFlow combine
 *   - Foreground'da, READ olmayan, daha once gonderilmemis gelen mesajlari
 *     bul -> ID'leri set'e rezerve et (re-emit duplicate onlemi)
 *   - 800ms gecikme (DELIVERED tik'inin gonderici tarafindan gozlenebilmesi)
 *   - DB'de READ marking + DeliveryReceipt(READ) sinyali
 *
 * Lifecycle: ChatViewModel.init'de start(scope) cagrilir, ChatViewModel
 * onCleared'da reset() ile temizlenir.
 */
class ChatReceiptManager(
    private val conversationId: String,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val messageRepository: MessageRepository,
    private val observeMessagesUseCase: ObserveMessagesUseCase
) {
    /** READ receipt gonderdigi mesaj ID'leri — duplicate onleme. */
    private val readReceiptSentIds = mutableSetOf<String>()

    /** Collector'i baslatir — viewModelScope icinde cagirilmali. */
    fun start(scope: CoroutineScope) {
        scope.launch {
            markIncomingMessagesAsRead()
        }
    }

    /** Lifecycle bitince temizle. */
    fun reset() {
        readReceiptSentIds.clear()
    }

    private suspend fun markIncomingMessagesAsRead() {
        val localUserId = userSession.userId ?: return
        combine(
            observeMessagesUseCase(conversationId),
            IncomingMessageHandler.isAppInForegroundFlow
        ) { messageList, isForeground -> messageList to isForeground }
            .collect { (messageList, isForeground) ->
                if (!isForeground) return@collect

                val unreadIncoming = messageList.filter {
                    !it.isOutgoing && it.status != MessageStatus.READ && it.id !in readReceiptSentIds
                }
                if (unreadIncoming.isEmpty()) return@collect

                // ID'leri hemen rezerv et — Flow bu collector'i yeniden tetiklerse
                // (DB updateMessageStatus emit'i) ayni mesajlar tekrar islenmesin.
                for (msg in unreadIncoming) readReceiptSentIds.add(msg.id)

                // DELIVERED tikinin gonderici tarafindan gozlenebilmesi icin minik bekleme.
                // IncomingMessageHandler mesaj geldiginde DELIVERED receipt'i anlik gonderir;
                // bu delay olmadan READ receipt 10-50ms sonra giderdi ve gonderici tarafta
                // gri cift tik hic gorunmeden direkt maviye gecerdi. Local network'te dogal
                // latency yok, o yuzden kasitli bir pencere koyuyoruz (WhatsApp ~500-800ms).
                delay(800)

                for (msg in unreadIncoming) {
                    messageRepository.updateMessageStatus(msg.id, MessageStatus.READ)
                    signalingClient.sendSignal(
                        SignalMessage.DeliveryReceipt(
                            senderId = localUserId,
                            recipientId = msg.senderId,
                            timestamp = System.currentTimeMillis(),
                            messageId = msg.id,
                            status = "READ"
                        )
                    )
                }
            }
    }
}
