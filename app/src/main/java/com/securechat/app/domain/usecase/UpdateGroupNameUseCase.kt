package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import javax.inject.Inject

/**
 * Grup adini guncelleme use case'i.
 * Sadece grup admin'leri grup adini degistirebilir.
 * Tum grup uyelerine bildirim gonderir.
 */
class UpdateGroupNameUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient
) {

    /**
     * Grup adini gunceller ve gerekli bildirimleri gonderir.
     *
     * @param groupId Grup kimlik numarasi
     * @param newName Yeni grup adi
     * @return Basarili ise true, hata varsa exception throw eder
     */
    suspend operator fun invoke(groupId: String, newName: String): Boolean {
        val currentUserId = userSession.userId ?: throw IllegalStateException("Kullanici giris yapmamis")

        if (newName.isBlank()) {
            throw IllegalArgumentException("Grup adi bos olamaz")
        }

        // Grup bilgilerini al
        val conversation = conversationDao.getById(groupId)
            ?: throw IllegalArgumentException("Grup bulunamadi")

        if (!conversation.isGroup) {
            throw IllegalArgumentException("Bu bir grup konusmasi degil")
        }

        val currentMembers = conversation.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()

        // Admin kontrolu — groupAdmins varsa onu kullan, yoksa geriye uyumluluk icin ilk uyeyi admin kabul et
        val adminIds = conversation.groupAdmins?.split(",")?.filter { it.isNotBlank() }
            ?: listOf(currentMembers.firstOrNull() ?: "")
        if (currentUserId !in adminIds) {
            throw IllegalAccessException("Sadece grup admin'i grup adini degistirebilir")
        }

        // Ayni ad kontrolu
        if (conversation.peerName == newName.trim()) {
            throw IllegalArgumentException("Grup adi zaten bu")
        }

        // Grup adini guncelle
        val updatedConversation = conversation.copy(peerName = newName.trim())
        conversationDao.update(updatedConversation)

        // Tum grup uyelerine grup guncelleme bildirimi gonder
        for (memberId in currentMembers) {
            if (memberId != currentUserId) { // Kendine mesaj gonderme
                signalingClient.sendSignal(
                    SignalMessage.GroupNotification(
                        senderId = currentUserId,
                        recipientId = memberId,
                        timestamp = System.currentTimeMillis(),
                        groupId = groupId,
                        groupName = newName.trim(),
                        action = GroupAction.UPDATE_NAME,
                        groupMembers = currentMembers,
                        targetMemberId = null
                    )
                )
            }
        }

        android.util.Log.d("UpdateGroupNameUseCase", "Grup adi guncellendi: $groupId -> $newName")
        return true
    }
}