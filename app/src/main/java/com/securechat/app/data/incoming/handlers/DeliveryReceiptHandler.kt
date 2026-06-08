package com.securechat.app.data.incoming.handlers

import com.securechat.network.SignalMessage
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Gelen DeliveryReceipt mesajini isler — DELIVERED veya READ statusu set eder.
 *
 * Status sirasi: SENDING(0) < SENT(1) < DELIVERED(2) < READ(3).
 * Sadece ileri yonde guncellenir — geri alinmaz (READ olan mesaj DELIVERED'a dusmez).
 *
 * Faz 10: IncomingMessageHandler.handleDeliveryReceipt extract edildi.
 */
@Singleton
class DeliveryReceiptHandler @Inject constructor(
    private val messageRepository: MessageRepository
) : SignalHandler<SignalMessage.DeliveryReceipt> {

    override suspend fun handle(signal: SignalMessage.DeliveryReceipt) {
        android.util.Log.d("DeliveryReceiptHandler", "msgId=${signal.messageId} status=${signal.status}")
        val newStatus = when (signal.status) {
            "DELIVERED" -> MessageStatus.DELIVERED
            "READ" -> MessageStatus.READ
            else -> return
        }
        val currentMessage = messageRepository.getMessageById(signal.messageId)
        if (currentMessage != null) {
            val currentOrder = STATUS_ORDER[currentMessage.status] ?: -1
            val newOrder = STATUS_ORDER[newStatus] ?: -1
            if (newOrder > currentOrder) {
                messageRepository.updateMessageStatus(signal.messageId, newStatus)
                android.util.Log.d("DeliveryReceiptHandler", "Receipt: ${currentMessage.status} -> $newStatus")
            } else {
                android.util.Log.d("DeliveryReceiptHandler", "Receipt ignored: ${currentMessage.status} >= $newStatus")
            }
        } else {
            // Race condition: mesaj henuz DB'de yok, yine de set et
            messageRepository.updateMessageStatus(signal.messageId, newStatus)
        }
    }

    companion object {
        private val STATUS_ORDER = mapOf(
            MessageStatus.SENDING to 0,
            MessageStatus.SENT to 1,
            MessageStatus.DELIVERED to 2,
            MessageStatus.READ to 3,
            MessageStatus.FAILED to -1
        )
    }
}
