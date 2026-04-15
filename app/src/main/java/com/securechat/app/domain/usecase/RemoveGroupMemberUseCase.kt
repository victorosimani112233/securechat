package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import javax.inject.Inject

/**
 * Gruptan uye cikartma use case'i.
 * Sadece grup admin'leri uye cikartabilir.
 * Cikartilan uyeye ve kalan uyelere bildirim gonderir.
 */
class RemoveGroupMemberUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient
) {

    /**
     * Gruptan uye cikarir ve gerekli bildirimleri gonderir.
     *
     * @param groupId Grup kimlik numarasi
     * @param memberId Cikarilacak uyenin kimlik numarasi
     * @return Basarili ise true, hata varsa exception throw eder
     */
    suspend operator fun invoke(groupId: String, memberId: String): Boolean {
        val currentUserId = userSession.userId ?: throw IllegalStateException("Kullanici giris yapmamis")

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
            throw IllegalAccessException("Sadece grup admin'i uye cikartabilir")
        }

        // Kendini cikartma kontrolu
        if (memberId == currentUserId) {
            throw IllegalArgumentException("Kendinizi gruptan cikartamazsiniz")
        }

        // Uye var mi kontrolu
        if (!currentMembers.contains(memberId)) {
            throw IllegalArgumentException("Kullanici grup uyesi degil")
        }

        // Uyeyi cikar
        val updatedMembers = currentMembers.filter { it != memberId }
        conversationDao.updateGroupMembers(groupId, updatedMembers.joinToString(","))

        // Cikartilan uyeye bildirim gonder
        signalingClient.sendSignal(
            SignalMessage.GroupNotification(
                senderId = currentUserId,
                recipientId = memberId,
                timestamp = System.currentTimeMillis(),
                groupId = groupId,
                groupName = conversation.peerName,
                action = GroupAction.REMOVE_MEMBER,
                groupMembers = updatedMembers, // Artik uye degil
                targetMemberId = memberId
            )
        )

        // Kalan grup uyelerine grup guncelleme bildirimi gonder
        for (remainingMemberId in updatedMembers) {
            if (remainingMemberId != currentUserId) { // Kendine mesaj gonderme
                signalingClient.sendSignal(
                    SignalMessage.GroupNotification(
                        senderId = currentUserId,
                        recipientId = remainingMemberId,
                        timestamp = System.currentTimeMillis(),
                        groupId = groupId,
                        groupName = conversation.peerName,
                        action = GroupAction.REMOVE_MEMBER,
                        groupMembers = updatedMembers,
                        targetMemberId = memberId
                    )
                )
            }
        }

        android.util.Log.d("RemoveGroupMemberUseCase", "Uye cikarildi: $memberId <- $groupId")
        return true
    }
}