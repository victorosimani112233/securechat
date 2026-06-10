package com.securechat.app.domain.usecase

import com.securechat.storage.dao.ConversationDao
import javax.inject.Inject

/**
 * Konusmayi manuel olarak "Okunmadi" isaretler veya isareti kaldirir.
 *
 * Yalniz lokal DB'yi gunceller — sunucu/karsi taraf bilgisi yok (manuel rozet
 * tamamen kullaniciya ozel bir hatirlatma davranisidir).
 *
 * ChatScreen acilinca markAsRead otomatik sifirlar (ConversationDao.markAsRead).
 */
class MarkConversationAsUnreadUseCase @Inject constructor(
    private val conversationDao: ConversationDao
) {
    /**
     * @param conversationId Konusma kimligi
     * @param markUnread true = okunmadi isaretle, false = isareti kaldir
     */
    suspend operator fun invoke(conversationId: String, markUnread: Boolean = true) {
        conversationDao.updateManuallyUnread(conversationId, markUnread)
    }
}
