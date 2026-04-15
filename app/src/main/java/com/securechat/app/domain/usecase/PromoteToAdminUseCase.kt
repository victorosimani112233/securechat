package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import javax.inject.Inject

/**
 * Bir grup uyesini admin olarak yukseltme use case'i.
 * Sadece mevcut grup admin'leri baska uyeyi admin yapabilir.
 * Tum grup uyelerine UPDATE_ADMIN bildirimi gonderir.
 */
class PromoteToAdminUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient
) {

    /**
     * Belirtilen uyeyi admin olarak yukseltir ve gerekli bildirimleri gonderir.
     *
     * @param groupId Grup kimlik numarasi
     * @param memberId Admin yapilacak uyenin kimlik numarasi
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
        val currentAdmins = conversation.groupAdmins?.split(",")?.filter { it.isNotBlank() }
            ?: listOf(currentMembers.firstOrNull() ?: "")

        if (currentUserId !in currentAdmins) {
            throw IllegalAccessException("Sadece grup admin'i yeni admin atayabilir")
        }

        // Uye var mi kontrolu
        if (!currentMembers.contains(memberId)) {
            throw IllegalArgumentException("Kullanici grup uyesi degil")
        }

        // Zaten admin mi kontrolu
        if (memberId in currentAdmins) {
            throw IllegalArgumentException("Kullanici zaten admin")
        }

        // Admin listesini guncelle
        val updatedAdmins = (currentAdmins + memberId).joinToString(",")
        conversationDao.updateGroupAdmins(groupId, updatedAdmins)

        // Tum grup uyelerine UPDATE_ADMIN bildirimi gonder
        for (member in currentMembers) {
            if (member != currentUserId) {
                signalingClient.sendSignal(
                    SignalMessage.GroupNotification(
                        senderId = currentUserId,
                        recipientId = member,
                        timestamp = System.currentTimeMillis(),
                        groupId = groupId,
                        groupName = conversation.peerName,
                        action = GroupAction.UPDATE_ADMIN,
                        groupMembers = currentMembers,
                        targetMemberId = memberId
                    )
                )
            }
        }

        android.util.Log.d("PromoteToAdminUseCase", "Yeni admin atandi: $memberId -> $groupId")
        return true
    }
}
