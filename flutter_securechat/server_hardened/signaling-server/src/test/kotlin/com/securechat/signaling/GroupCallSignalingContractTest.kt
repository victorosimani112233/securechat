package com.securechat.signaling

import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue

class GroupCallSignalingContractTest {
    private val enabled = mapOf("SFU_ENABLED" to "true", "JANUS_WS_URL" to "ws://127.0.0.1:8188")

    private class Fixture(val type: String = "VIDEO", val encrypted: Boolean = true) {
        val group = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also { java.security.SecureRandom().nextBytes(it) })
        val call = UUID.randomUUID().toString()
        val users = (0..8).map { UUID.randomUUID().toString() }
        val delivered = ConcurrentLinkedQueue<Pair<String, JsonObject>>()
        val promotionRequests = ConcurrentLinkedQueue<String>()
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
            assertTrue(handleGroupCallSignal(sender, Json.parseToJsonElement(encoded).jsonObject, send, promotionRequests::add))
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
                assertTrue(f.promotionRequests.isEmpty())
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

    @Test
    fun `capability join triggers one promotion and announcement uses latest joined membership`() = runBlocking {
        for (type in listOf("VOICE", "VIDEO")) {
            val f = Fixture(type)
            var creations = 0
            val started = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val promotion = GroupCallPromotion(enabled, createRoom = {
                creations++; started.complete(Unit); release.await(); SfuRoomInfo(42, "wss://signal.invalid/janus")
            }, destroyRoom = { _, _ -> fail("Committed room must not be destroyed") })
            try {
                (1..7).forEach { f.invite(it) }
                (1..5).forEach { f.join(it) }
                promotion.promote(f.group, f.send)
                assertEquals(0, creations)
                f.join(6)
                val first = launch { promotion.promote(f.group, f.send) }
                withTimeout(2000) { started.await() }
                f.join(7)
                val duplicates = (1..7).map { launch { promotion.promote(f.group, f.send) } }
                release.complete(Unit)
                first.join(); duplicates.joinAll()
                assertEquals(1, creations)
                assertEquals("SFU", f.state().mode)
                assertEquals(8, f.frames("sfu_room_created").size)
                assertTrue(f.frames("sfu_room_created").all { (_, frame) ->
                    frame["roomId"]?.jsonPrimitive?.long == 42L && frame["callId"]?.jsonPrimitive?.content == f.call
                })
                f.join(7)
                assertEquals(9, f.frames("sfu_room_created").size, "Rejoin gets current room without recreation")
            } finally { GroupCallSessionStore.end(f.group) }
        }
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
    fun `eight unencrypted mesh participants never promote even with legacy override`() = runBlocking {
        val f = Fixture(encrypted = false)
        try {
            (1..7).forEach { f.invite(it); f.join(it) }
            val promotion = GroupCallPromotion(enabled + ("SFU_MEDIA_BOUNDARY_ACK" to SfuPolicy.REQUIRED_ACKNOWLEDGEMENT),
                createRoom = { throw AssertionError("No plaintext SFU") })
            promotion.promote(f.group, f.send)
            assertEquals("MESH", f.state().mode)
            assertEquals(8, f.state().joinedParticipants.size)
        } finally { GroupCallSessionStore.end(f.group) }
    }

    @Test
    fun `room failure rolls back for retry without dropping encrypted mesh`() = runBlocking {
        val f = Fixture()
        try {
            (1..6).forEach { f.invite(it); f.join(it) }
            GroupCallPromotion(enabled, createRoom = { error("offline") }).promote(f.group, f.send)
            assertEquals("MESH", f.state().mode)
            assertTrue(f.frames("sfu_room_created").isEmpty())
            GroupCallPromotion(enabled, createRoom = { SfuRoomInfo(42, "wss://signal.invalid/janus") })
                .promote(f.group, f.send)
            assertEquals("SFU", f.state().mode)
        } finally { GroupCallSessionStore.end(f.group) }
    }

    @Test
    fun `late creation cannot attach to replacement call or resurrect ended call`() = runBlocking {
        val f = Fixture()
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val destroyed = mutableListOf<Long>()
        try {
            (1..6).forEach { f.invite(it); f.join(it) }
            val promotion = GroupCallPromotion(enabled, createRoom = {
                started.complete(Unit); release.await(); SfuRoomInfo(42, "wss://signal.invalid/janus")
            }, destroyRoom = { _, room -> destroyed.add(room); Unit })
            val job = launch { promotion.promote(f.group, f.send) }
            started.await()
            GroupCallSessionStore.end(f.group)
            f.invite(1, callId = "replacement")
            release.complete(Unit); job.join()
            assertEquals(listOf(42L), destroyed)
            assertEquals("replacement", f.state().callId)
            assertEquals("MESH", f.state().mode)
            assertTrue(f.frames("sfu_room_created").isEmpty())
        } finally { GroupCallSessionStore.end(f.group) }
    }
}
