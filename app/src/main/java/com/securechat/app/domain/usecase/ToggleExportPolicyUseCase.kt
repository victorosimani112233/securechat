package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import javax.inject.Inject

/**
 * Grup sohbet disa aktarma iznini ac/kapat use case'i.
 *
 * Yetki: sadece grup admin'i toggle edebilir. Diger uyeler okuma erisimine sahiptir
 * ama UI seviyesinde toggle disabled gosterilir (defansif: server-side admin kontrolu
 * yok, peer-to-peer guven gerektirir).
 *
 * Propagation: Tum grup uyelerine `GroupNotification(action=UPDATE_EXPORT_POLICY)`
 * gonderir. `targetMemberId` alani yeni durumu "true"/"false" stringi olarak tasir
 * (wire formatina yeni alan eklemeden geri-uyumlu kalmak icin).
 */
class ToggleExportPolicyUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient
) {

    /**
     * @param groupId Grup ID
     * @param enabled Yeni durum
     * @return true (basari), exception (yetki yok / grup yok)
     */
    suspend operator fun invoke(groupId: String, enabled: Boolean): Boolean {
        val currentUserId = userSession.userId
            ?: throw IllegalStateException("Kullanici giris yapmamis")

        val conversation = conversationDao.getById(groupId)
            ?: throw IllegalArgumentException("Grup bulunamadi")

        if (!conversation.isGroup) {
            throw IllegalArgumentException("Bu bir grup konusmasi degil")
        }

        val currentMembers = conversation.groupMembers
            ?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
        val currentAdmins = conversation.groupAdmins
            ?.split(",")?.filter { it.isNotBlank() }
            ?: listOf(currentMembers.firstOrNull() ?: "")

        if (currentUserId !in currentAdmins) {
            throw IllegalAccessException("Sadece grup admin'i bu ayari degistirebilir")
        }

        // Lokal DB once — diger uyelere broadcast bunun ardindan
        conversationDao.updateExportEnabled(groupId, enabled)

        // Fanout — broadcast sirasinda WS kapali olabilir; mevcut sendSignal
        // fire-and-forget. PromoteToAdminUseCase ile ayni pattern.
        for (member in currentMembers) {
            if (member != currentUserId) {
                signalingClient.sendSignal(
                    SignalMessage.GroupNotification(
                        senderId = currentUserId,
                        recipientId = member,
                        timestamp = System.currentTimeMillis(),
                        groupId = groupId,
                        groupName = conversation.peerName,
                        action = GroupAction.UPDATE_EXPORT_POLICY,
                        groupMembers = currentMembers,
                        targetMemberId = enabled.toString()
                    )
                )
            }
        }

        android.util.Log.d(
            "ToggleExportPolicyUseCase",
            "Export izni ${if (enabled) "acildi" else "kapatildi"}: $groupId"
        )
        return true
    }
}
