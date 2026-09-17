package com.securechat.signaling

import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.util.Base64
import java.util.UUID

/**
 * SFU kontrol duzlemi, gercek bir WebSocket uzerinden.
 *
 * Janus oturumu ve odasi burada uretim kodunun kendisiyle kurulur. Bu
 * duzlem hem gizlilik hem kullanilabilirlik acisindan onemlidir: oda
 * kimligi tahmin edilebilir olursa baska bir grubun cagrisina katilma
 * girisimi onemsizlesir; sirlar gonderilmezse Janus istegi reddeder;
 * bekleyen istekler temizlenmezse baglanti koptugunda cagri kurulumu
 * timeout'a kadar asili kalir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class JanusControlPlaneTest {

    private val janus = FakeJanusServer()

    private fun groupId(): String =
        Base64.getUrlEncoder().withoutPadding()
            .encodeToString(ByteArray(32).also { java.security.SecureRandom().nextBytes(it) })

    @BeforeAll
    fun setUp() {
        janus.start()
        JanusOrchestrator.init()
        // Baglanti kurulana kadar bekle.
        runBlocking {
            withTimeoutOrNull(10_000) {
                while (!JanusOrchestrator.isConnected()) delay(50)
                true
            }
        }
    }

    @AfterAll
    fun tearDown() {
        runBlocking { runCatching { JanusOrchestrator.destroyAllRooms() } }
        janus.stop()
    }

    @BeforeEach
    fun clearRequests() {
        janus.clear()
        janus.silent = false
    }

    @Test
    fun `the control connection comes up`() {
        assertTrue(JanusOrchestrator.isConnected())
    }

    @Test
    fun `creating a room establishes a session and a videoroom handle`() = runBlocking {
        val group = groupId()

        val roomId = JanusOrchestrator.createVideoRoom(group)

        assertTrue(roomId > 0)
        val kinds = janus.received.map { it["janus"]?.jsonPrimitive?.content }
        assertTrue(kinds.contains("create"), kinds.toString())
        assertTrue(kinds.contains("attach"), kinds.toString())
        assertTrue(kinds.contains("message"), kinds.toString())
        JanusOrchestrator.destroyVideoRoom(group)
    }

    @Test
    fun `every request carries the api secret`() = runBlocking {
        val group = groupId()

        JanusOrchestrator.createVideoRoom(group)

        // Sir gonderilmezse Janus istegi reddeder; sessiz basarisizlik
        // cagriyi kurulmamis birakirdi.
        assertTrue(janus.received.isNotEmpty())
        for (request in janus.received) {
            assertNotNull(request["apisecret"], request.toString())
        }
        JanusOrchestrator.destroyVideoRoom(group)
    }

    @Test
    fun `room creation carries the admin key and hardened media settings`() = runBlocking {
        val group = groupId()

        JanusOrchestrator.createVideoRoom(group)

        val create = janus.received.first { request ->
            request["body"]?.jsonObject?.get("request")?.jsonPrimitive?.content == "create"
        }
        val body = create["body"]!!.jsonObject
        assertNotNull(body["admin_key"])
        // Kayit acik olsaydi medya sunucu diskine yazilirdi.
        assertEquals("false", body["record"]!!.jsonPrimitive.content)
        assertEquals("8", body["publishers"]!!.jsonPrimitive.content)
        JanusOrchestrator.destroyVideoRoom(group)
    }

    @Test
    fun `the same group reuses its room instead of creating a second one`() = runBlocking {
        val group = groupId()

        val first = JanusOrchestrator.createVideoRoom(group)
        janus.clear()
        val second = JanusOrchestrator.createVideoRoom(group)

        assertEquals(first, second)
        // Ikinci cagri hicbir istek uretmemeli.
        assertTrue(janus.received.isEmpty(), janus.received.toString())
        JanusOrchestrator.destroyVideoRoom(group)
    }

    @Test
    fun `two groups get different rooms`() = runBlocking {
        val first = groupId()
        val second = groupId()

        val firstRoom = JanusOrchestrator.createVideoRoom(first)
        val secondRoom = JanusOrchestrator.createVideoRoom(second)

        assertFalse(firstRoom == secondRoom)
        JanusOrchestrator.destroyVideoRoom(first)
        JanusOrchestrator.destroyVideoRoom(second)
    }

    @Test
    fun `room details are exposed only through the pinned public url`() = runBlocking {
        val group = groupId()
        val roomId = JanusOrchestrator.createVideoRoom(group)

        val info = JanusOrchestrator.getRoomInfo(group)

        assertNotNull(info)
        assertEquals(roomId, info!!.roomId)
        // Istemciye ic adres degil, pinlenmis public adres verilir.
        assertTrue(info.janusWsUrl.startsWith("wss://"), info.janusWsUrl)
        JanusOrchestrator.destroyVideoRoom(group)
    }

    @Test
    fun `an unknown group has no room`() {
        assertNull(JanusOrchestrator.getRoomInfo(groupId()))
        assertFalse(JanusOrchestrator.hasActiveRoom(groupId()))
    }

    @Test
    fun `destroying a room removes it from the active set`() = runBlocking {
        val group = groupId()
        JanusOrchestrator.createVideoRoom(group)
        assertTrue(JanusOrchestrator.hasActiveRoom(group))

        JanusOrchestrator.destroyVideoRoom(group)

        assertFalse(JanusOrchestrator.hasActiveRoom(group))
        assertNull(JanusOrchestrator.getRoomInfo(group))
    }

    @Test
    fun `destroying an unknown room is a no-op`() = runBlocking {
        JanusOrchestrator.destroyVideoRoom(groupId())

        assertTrue(janus.received.isEmpty())
    }

    @Test
    fun `a silent gateway times out instead of hanging forever`() = runBlocking {
        val group = groupId()
        janus.silent = true

        var failed = false
        try {
            withTimeoutOrNull(20_000) { JanusOrchestrator.createVideoRoom(group) }
                ?: run { failed = true }
        } catch (_: Exception) {
            failed = true
        }

        // Yanit gelmeyen bir gateway cagri kurulumunu sonsuza kadar
        // askida birakmamalidir.
        assertTrue(failed)
        assertFalse(JanusOrchestrator.hasActiveRoom(group))
        assertEquals(0, JanusOrchestrator.pendingRequestCount())
    }

    @Test
    fun `transactions are unique per request`() = runBlocking {
        val group = groupId()
        JanusOrchestrator.createVideoRoom(group)

        val transactions = janus.received.mapNotNull { it["transaction"]?.jsonPrimitive?.content }

        assertEquals(transactions.size, transactions.toSet().size)
        JanusOrchestrator.destroyVideoRoom(group)
    }

    @Test
    fun `destroying all rooms clears every active group`() = runBlocking {
        val first = groupId()
        val second = groupId()
        JanusOrchestrator.createVideoRoom(first)
        JanusOrchestrator.createVideoRoom(second)

        JanusOrchestrator.destroyAllRooms()

        assertFalse(JanusOrchestrator.hasActiveRoom(first))
        assertFalse(JanusOrchestrator.hasActiveRoom(second))
    }
}
