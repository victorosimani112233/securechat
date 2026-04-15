package com.securechat.app.domain.usecase

import com.securechat.storage.repository.MessageRepository
import javax.inject.Inject

/**
 * Konusmayi okundu olarak isaretleme use case'i.
 */
class MarkAsReadUseCase @Inject constructor(
    private val messageRepository: MessageRepository
) {
    /**
     * Belirtilen konusmadaki tum okunmamis mesajlari okundu olarak isaretler.
     *
     * @param conversationId Okundu isaretlenecek konusma kimlik numarasi
     */
    suspend operator fun invoke(conversationId: String) {
        messageRepository.markConversationAsRead(conversationId)
    }
}
