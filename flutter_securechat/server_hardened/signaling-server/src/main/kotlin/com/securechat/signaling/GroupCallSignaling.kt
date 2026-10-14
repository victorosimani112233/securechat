package com.securechat.signaling

import kotlinx.serialization.json.*

/** The same admission boundary is used by the socket route and contract tests. */
internal suspend fun handleGroupCallSignal(
    senderId: String,
    frame: JsonObject,
    send: suspend (String, String) -> Unit,
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
    return true
}
