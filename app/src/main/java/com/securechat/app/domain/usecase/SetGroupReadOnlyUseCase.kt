package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import javax.inject.Inject

/**
 * Grup "Sadece admin yazabilir" (duyuru kanali) bayragini degistirir.
 *
 * Yetki: yalniz grup admin'i (ToggleExportPolicyUseCase ile ayni pattern).
 *
 * Propagation: tum uyelere `GroupNotification(action=SET_READ_ONLY)` gonderir.
 * `targetMemberId` alani "true"/"false" yeni durumu tasir — yeni wire alani
 * eklemeden geri-uyumlu kalmak icin.
 */
class SetGroupReadOnlyUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient
) {
    suspend operator fun invoke(groupId: String, isReadOnly: Boolean): Boolean {
        val currentUserId = userSession.userId
            ?: throw IllegalStateException("Kullanici giris yapmamis")

        val conversation = conversationDao.getById(groupId)
            ?: throw IllegalArgumentException("Grup bulunamadi")

        if (!conversation.isGroup) {
            throw IllegalArgumentException("Bu bir grup konusmasi degil")
        }

        val members = conversation.groupMembers
            ?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
        val admins = conversation.groupAdmins
            ?.split(",")?.filter { it.isNotBlank() }
            ?: listOf(members.firstOrNull() ?: "")

        if (currentUserId !in admins) {
            throw IllegalAccessException("Sadece grup admin'i bu ayari degistirebilir")
        }

        conversationDao.updateReadOnly(groupId, isReadOnly)

        val ts = System.currentTimeMillis()
        for (member in members) {
            if (member != currentUserId) {
                signalingClient.sendSignal(
                    SignalMessage.GroupNotification(
                        senderId = currentUserId,
                        recipientId = member,
                        timestamp = ts,
                        groupId = groupId,
                        groupName = conversation.peerName,
                        action = GroupAction.SET_READ_ONLY,
                        groupMembers = members,
                        targetMemberId = isReadOnly.toString()
                    )
                )
            }
        }

        android.util.Log.d(
            "SetGroupReadOnlyUseCase",
            "Read-only ${if (isReadOnly) "acildi" else "kapatildi"}: $groupId"
        )
        return true
    }
}
