package com.securechat.storage.domain

/**
 * Konuşma domain modeli. Entity'den bagimsiz, is katmaninda kullanilir.
 */
data class Conversation(
    val id: String,
    val peerId: String,
    val peerName: String,
    val peerPhone: String,
    val lastMessage: String?,
    val lastMessageTimestamp: Long?,
    val unreadCount: Int,
    val isMuted: Boolean,
    val isPinned: Boolean,
    val isGroup: Boolean = false,
    val groupMembers: List<String> = emptyList(),
    val groupAdmins: List<String> = emptyList(),
    val contactNote: String? = null,
    val customNotificationUri: String? = null,
    val isArchived: Boolean = false,
    val disappearingDuration: Long = 0,
    val isFavorite: Boolean = false,
    val isLocked: Boolean = false,
    /** Manuel "Okunmadi isaretle" — ChatScreen acilinca otomatik temizlenir. */
    val manuallyUnread: Boolean = false,
    /** "Sadece admin yazabilir" duyuru kanali bayragi (yalniz grup sohbetlerinde anlamli). */
    val isReadOnly: Boolean = false
) {
    /**
     * Konusma okunmamis durumu — unread_count > 0 VEYA manuel olarak isaretlendi.
     * Sohbet listesi rozetinde bu deger kullanilir.
     */
    val hasUnread: Boolean get() = unreadCount > 0 || manuallyUnread
}
