package com.securechat.signaling

import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue

class GroupCallSignalingContractTest {
    private class Fixture(val type: String = "VIDEO", val encrypted: Boolean = true) {
        val group = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { java.security.SecureRandom().nextBytes(it) })
        val call = UUID.randomUUID().toString()
        val users = (0..8).map { UUID.randomUUID().toString() }
        val delivered = ConcurrentLinkedQueue<Pair<String, JsonObject>>()
        val send: suspend (String, String) -> Unit = { recipient, raw ->
            delivered.add(recipient to Json.parseToJsonElement(raw).jsonObject)
        }
        suspend fun invite(index: Int, callId: String = call) = signal("group_call_invite", users[0], users[index], callId, encrypted)
        suspend fun join(index: Int, capability: Boolean = encrypted, callId: String = call) =
            signal("group_call_join_request", users[index], users[0], callId, capability)
        private suspend fun signal(type: String, sender: String, recipient: String, callId: String, capability: Boolean) {
            val encoded = buildJsonObject {
                put("type", type); put("recipientId", recipient); put("senderId", "forged")
                put("groupId", group); put("callId", callId); put("callType", this@Fixture.type)
                put("mediaE2ee", capability)
                putJsonArray("participants") { add("must-not-be-forwarded") }
            }.toString()
            assertTrue(handleGroupCallSignal(sender, Json.parseToJsonElement(encoded).jsonObject, send))
        }
        fun frames(type: String) = delivered.filter { it.second["type"]?.jsonPrimitive?.content == type }
        fun state() = requireNotNull(GroupCallSessionStore.get(group))
    }

    @Test
    fun `voice and video admit eight before capability joins and reject ninth with correlation`() = runBlocking {
        for (type in listOf("VOICE", "VIDEO")) {
            val f = Fixture(type)
            try {
                (1..7).map { async(Dispatchers.Default) { f.invite(it) } }.awaitAll()
                assertEquals(8, f.state().participants.size)
                assertEquals(setOf(f.users[0]), f.state().joinedParticipants)
                assertEquals(setOf(f.users[0]), f.state().mediaE2eeParticipants)
                assertEquals(7, f.frames("group_call_invite").size)
                assertTrue(f.frames("group_call_invite").all { (_, frame) ->
                    frame["participants"] == null && frame["senderId"]?.jsonPrimitive?.content == f.users[0]
                })
                f.invite(8)
                val rejected = f.frames("group_call_error").single().second
                assertEquals(f.call, rejected["callId"]?.jsonPrimitive?.content)
                assertEquals(f.group, rejected["groupId"]?.jsonPrimitive?.content)
                assertEquals("server", rejected["senderId"]?.jsonPrimitive?.content)
                assertEquals("CAPACITY_REACHED", rejected["code"]?.jsonPrimitive?.content)
                assertEquals(8, f.state().participants.size)
                f.invite(7)
                assertEquals(8, f.state().participants.size)
            } finally { GroupCallSessionStore.end(f.group) }
        }
    }

    // Janus SFU 2026-10-14'te kaldirildi: 7. ve 8. katilimci da mesh'e
    // katilir, sunucu hicbir zaman oda bildirimi uretmez.
    @Test
    fun `eight joined members stay in mesh and no room is ever announced`() = runBlocking {
        for (type in listOf("VOICE", "VIDEO")) {
            val f = Fixture(type)
            try {
                (1..7).forEach { f.invite(it); f.join(it) }
                assertEquals(f.users.take(8).toSet(), f.state().joinedParticipants)
                assertTrue(f.state().mediaEndToEndEncrypted)
                assertEquals(7, f.frames("group_call_join_request").size)
                assertTrue(f.frames("sfu_room_created").isEmpty())
                f.join(7)
                assertTrue(f.frames("sfu_room_created").isEmpty())
            } finally { GroupCallSessionStore.end(f.group) }
        }
    }

    @Test
    fun `a client cannot forge the retired room announcement`() {
        // Eski istemciler bu cerceveyi isleyip icindeki adrese baglanir.
        assertTrue(isServerOnlyFrameType("sfu_room_created"))
    }

    @Test
    fun `incapable join is rejected without downgrading encrypted call and foreign context is refused`() = runBlocking {
        val f = Fixture()
        try {
            f.invite(1)
            f.join(1, callId = "wrong-call")
            assertEquals(setOf(f.users[0]), f.state().joinedParticipants)
            f.join(2)
            assertFalse(f.users[2] in f.state().participants)
            f.join(1, capability = false)
            assertFalse(f.users[1] in f.state().participants)
            assertTrue(f.state().requiresMediaE2ee)
            assertTrue(f.frames("group_call_join_request").isEmpty())
            assertEquals("HANGUP", f.frames("call_control").single().second["action"]?.jsonPrimitive?.content)
            assertEquals("ENCRYPTION_REQUIRED", f.frames("group_call_error").last().second["code"]?.jsonPrimitive?.content)
        } finally { GroupCallSessionStore.end(f.group) }
    }

    @Test
    fun `eight unencrypted mesh participants are admitted`() = runBlocking {
        val f = Fixture(encrypted = false)
        try {
            (1..7).forEach { f.invite(it); f.join(it) }
            assertEquals(8, f.state().joinedParticipants.size)
            assertTrue(f.frames("sfu_room_created").isEmpty())
        } finally { GroupCallSessionStore.end(f.group) }
    }
}
