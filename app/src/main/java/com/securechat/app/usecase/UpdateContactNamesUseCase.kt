package com.securechat.app.usecase

import com.securechat.storage.repository.MessageRepository
import javax.inject.Inject

/**
 * Konuşmalardaki kişi isimlerini ContactNameResolver ile günceller.
 * Uygulama başlangıcında veya rehber değiştiğinde çağrılmalıdır.
 */
class UpdateContactNamesUseCase @Inject constructor(
    private val messageRepository: MessageRepository
) {
    suspend operator fun invoke() {
        messageRepository.updateConversationNames()
    }
}