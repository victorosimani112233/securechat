package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import javax.inject.Inject

/**
 * Gruba yeni uye ekleme use case'i.
 * Sadece grup admin'leri yeni uye ekleyebilir.
 * Yeni uyeye grup katilim bildirimi gonderir.
 */
class AddGroupMemberUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient
) {

    /**
     * Gruba yeni uye ekler ve gerekli bildirimleri gonderir.
     *
     * @param groupId Grup kimlik numarasi
     * @param newMemberId Eklenecek uyenin kimlik numarasi
     * @return Basarili ise true, hata varsa exception throw eder
     */
    suspend operator fun invoke(groupId: String, newMemberId: String): Boolean {
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
            throw IllegalAccessException("Sadece grup admin'i yeni uye ekleyebilir")
        }

        // Zaten uye mi kontrolu
        if (currentMembers.contains(newMemberId)) {
            throw IllegalArgumentException("Kullanici zaten grup uyesi")
        }

        // Yeni uyeyi ekle
        val updatedMembers = (currentMembers + newMemberId).joinToString(",")
        conversationDao.updateGroupMembers(groupId, updatedMembers)

        // Tum grup uyelerine (yeni uye dahil) grup guncelleme bildirimi gonder
        val allMembers = currentMembers + newMemberId
        for (memberId in allMembers) {
            if (memberId != currentUserId) { // Kendine mesaj gonderme
                signalingClient.sendSignal(
                    SignalMessage.GroupNotification(
                        senderId = currentUserId,
                        recipientId = memberId,
                        timestamp = System.currentTimeMillis(),
                        groupId = groupId,
                        groupName = conversation.peerName,
                        action = GroupAction.ADD_MEMBER,
                        groupMembers = allMembers,
                        targetMemberId = newMemberId
                    )
                )
            }
        }

        android.util.Log.d("AddGroupMemberUseCase", "Uye eklendi: $newMemberId -> $groupId")
        return true
    }
}