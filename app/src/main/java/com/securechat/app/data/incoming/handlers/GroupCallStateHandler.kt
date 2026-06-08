package com.securechat.app.data.incoming.handlers

import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.media.CallManager
import com.securechat.network.SignalMessage
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Grup arama STATE sinyalleri — Sfu room oluştu + StatusResponse.
 *
 * Bu handler GroupCall arama state'inin tutuldugu global activeGroupCalls
 * Map'ini gunceller (IncomingMessageHandler companion). ChatScreen banner'i
 * bu state'i izler.
 *
 * Faz 10: handleSfuRoomCreated + handleGroupCallStatusResponse extract edildi.
 * GroupCallInvite + Call/SDP/ICE handler'lari ayri (karmasik dependency chain).
 */
@Singleton
class GroupCallStateHandler @Inject constructor(
    private val userSession: UserSession,
    private val callManager: CallManager
) {

    fun onSfuRoomCreated(signal: SignalMessage.SfuRoomCreated) {
        val localUserId = userSession.userId ?: return
        val session = callManager.currentSession ?: return
        if (!session.isGroupCall || session.groupId != signal.groupId) {
            android.util.Log.d("GroupCallStateHandler", "SfuRoomCreated atlandi — aktif grup arama uyusmuyor")
            return
        }
        if (session.state != com.securechat.media.model.CallState.ACTIVE) {
            android.util.Log.d("GroupCallStateHandler", "SfuRoomCreated atlandi — call ACTIVE degil")
            return
        }
        val info = CallManager.SfuRoomBindInfo(
            roomId = signal.roomId,
            janusWsUrl = signal.janusWsUrl
        )
        callManager.bindSfuRoomFromInvite(localUserId, info)

        // activeGroupCalls state'inde SFU bilgisini ekle (sonradan katilim icin)
        val current = IncomingMessageHandler.activeGroupCalls.value.toMutableMap()
        val existing = current[signal.groupId]
        if (existing != null) {
            current[signal.groupId] = existing.copy(
                mode = "SFU",
                sfuRoomId = signal.roomId,
                janusWsUrl = signal.janusWsUrl
            )
            IncomingMessageHandler.activeGroupCalls.value = current
        }
    }

    fun onStatusResponse(signal: SignalMessage.GroupCallStatusResponse) {
        val current = IncomingMessageHandler.activeGroupCalls.value.toMutableMap()
        val callId = signal.callId
        val coordinatorId = signal.coordinatorId
        val callType = signal.callType
        if (signal.isActive && callId != null && coordinatorId != null && callType != null) {
            current[signal.groupId] = IncomingMessageHandler.Companion.ActiveGroupCallInfo(
                groupId = signal.groupId,
                callId = callId,
                coordinatorId = coordinatorId,
                callType = callType,
                participants = signal.participants,
                mode = signal.mode ?: "MESH",
                sfuRoomId = signal.sfuRoomId,
                janusWsUrl = signal.janusWsUrl
            )
        } else {
            current.remove(signal.groupId)
        }
        IncomingMessageHandler.activeGroupCalls.value = current
        android.util.Log.d("GroupCallStateHandler", "Grup arama durum guncellendi: ${signal.groupId} active=${signal.isActive}")
    }
}
