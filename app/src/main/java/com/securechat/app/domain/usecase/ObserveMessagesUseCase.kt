package com.securechat.app.domain.usecase

import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.repository.MessageRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

/**
 * Mesajlari reaktif olarak gozlemleme use case'i.
 * Belirtilen konusmadaki mesajlari Flow olarak doner.
 */
class ObserveMessagesUseCase @Inject constructor(
    private val messageRepository: MessageRepository
) {
    /**
     * Belirtilen konusmadaki tum mesajlari reaktif olarak getirir.
     *
     * @param conversationId Gozlemlenecek konusma kimlik numarasi
     * @return Mesaj listesi Flow'u
     */
    operator fun invoke(conversationId: String): Flow<List<LocalMessage>> {
        return messageRepository.getMessages(conversationId)
    }
}
