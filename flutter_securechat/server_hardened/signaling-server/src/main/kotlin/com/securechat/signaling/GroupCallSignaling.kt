package com.securechat.signaling

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.*
import org.slf4j.LoggerFactory

/** The same admission boundary is used by the socket route and contract tests. */
internal suspend fun handleGroupCallSignal(
    senderId: String,
    frame: JsonObject,
    send: suspend (String, String) -> Unit,
    promote: (String) -> Unit,
): Boolean {
    val type = frame["type"]?.jsonPrimitive?.contentOrNull
    if (type !in setOf("group_call_invite", "group_call_join_request")) return false
    val groupId = frame["groupId"]?.jsonPrimitive?.contentOrNull.orEmpty()
    val callId = frame["callId"]?.jsonPrimitive?.contentOrNull.orEmpty()
    val callType = frame["callType"]?.jsonPrimitive?.contentOrNull.orEmpty()
    val recipient = frame["recipientId"]?.jsonPrimitive?.contentOrNull.orEmpty()
    val capable = frame["mediaE2ee"]?.jsonPrimitive?.booleanOrNull == true
    if (!groupId.matches(Regex("^[A-Za-z0-9_-]{43}=?$")) || callId.isBlank() || callId.length > 128 ||
        callType !in setOf("VOICE", "VIDEO") || recipient == senderId ||
        runCatching { java.util.UUID.fromString(recipient) }.isFailure) return true

    val result = if (type == "group_call_invite") {
        GroupCallSessionStore.invite(groupId, callId, senderId, callType, recipient, capable)
    } else {
        GroupCallSessionStore.confirmJoin(groupId, callId, recipient, callType, senderId, capable)
    }
    if (result !in setOf(GroupCallSessionStore.JoinResult.ADDED, GroupCallSessionStore.JoinResult.ALREADY_PRESENT)) {
        send(senderId, serverFrame("group_call_error", senderId) {
            put("groupId", groupId)
            put("callId", callId)
            put("code", result.name)
        })
        if (result == GroupCallSessionStore.JoinResult.ENCRYPTION_REQUIRED) {
            GroupCallSessionStore.removeParticipant(groupId, senderId)
            send(senderId, serverFrame("call_control", senderId) {
                put("groupId", groupId)
                put("action", "HANGUP")
            })
            GroupCallSessionStore.get(groupId)?.participants?.forEach { member ->
                send(member, serverFrame("group_call_member_left", member) {
                    put("groupId", groupId)
                    put("groupCallId", callId)
                    put("leftMemberId", senderId)
                })
            }
        }
        return true
    }
    // Do not forward a client-supplied sender or a redundant social graph.
    val routed = JsonObject(frame.filterKeys { it != "participants" && it != "senderId" } +
        ("senderId" to JsonPrimitive(senderId)))
    send(recipient, routed.toString())
    if (type == "group_call_join_request") {
        val active = GroupCallSessionStore.get(groupId)
        if (active?.mode == "SFU" && senderId in active.joinedParticipants) {
            send(senderId, sfuRoomFrame(active, senderId))
        } else {
            promote(groupId)
        }
    }
    return true
}

internal fun sfuRoomFrame(call: GroupCallSessionStore.ActiveCall, recipient: String): String =
    serverFrame("sfu_room_created", recipient) {
        put("groupId", call.groupId)
        put("callId", call.callId)
        put("roomId", requireNotNull(call.sfuRoomId))
        put("janusWsUrl", requireNotNull(call.janusWsUrl))
    }

internal class GroupCallPromotion(
    private val environment: Map<String, String> = System.getenv(),
    private val createRoom: suspend (GroupCallSessionStore.ActiveCall) -> SfuRoomInfo = { call ->
        JanusOrchestrator.createVideoRoom(call.groupId, call.instanceId)
        requireNotNull(JanusOrchestrator.getRoomInfo(call.groupId, call.instanceId))
    },
    private val destroyRoom: suspend (GroupCallSessionStore.ActiveCall, Long) -> Unit = { call, room ->
        JanusOrchestrator.destroyVideoRoom(call.groupId, room, call.instanceId)
    },
) {
    suspend fun promote(groupId: String, send: suspend (String, String) -> Unit) {
        // Covers room creation, commit and stale-room disposal, including a
        // replacement call using the same routing token during the await.
        locks[(groupId.hashCode() and Int.MAX_VALUE) % locks.size].withLock {
            val pending = GroupCallSessionStore.claimSfuPromotion(groupId, environment) ?: return
            var room: SfuRoomInfo? = null
            try {
                room = createRoom(pending)
                val committed = GroupCallSessionStore.completeSfuPromotion(pending, room.roomId, room.janusWsUrl)
                if (committed == null) {
                    dispose(pending, room)
                    GroupCallSessionStore.cancelSfuPromotion(pending)
                    return
                }
                for (member in committed.joinedParticipants) {
                    // Sending one closed socket must not roll back a committed room.
                    runCatching { send(member, sfuRoomFrame(committed, member)) }
                }
            } catch (error: Exception) {
                GroupCallSessionStore.cancelSfuPromotion(pending)
                room?.let { runCatching { dispose(pending, it) } }
                if (error is CancellationException) throw error
                log.warn("Group SFU promotion failed; encrypted mesh retained: {}", error.javaClass.simpleName)
            }
        }
    }

    private suspend fun dispose(call: GroupCallSessionStore.ActiveCall, room: SfuRoomInfo) {
        GroupCallSessionStore.queueRoomCleanup(call.copy(sfuRoomId = room.roomId, janusWsUrl = room.janusWsUrl))
        destroyRoom(call, room.roomId)
        GroupCallSessionStore.roomCleanupCompleted(call.instanceId)
    }

    companion object {
        private val locks = Array(64) { Mutex() }
        private val log = LoggerFactory.getLogger("GroupCallPromotion")
    }
}
