package com.securechat.signaling

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.UUID
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Grup aramasinin katilimci tavani ve SFU'ya gecis kosullari.
 *
 * Mesh'te her cihaz N-1 encode ve N-1 upload yapar; tavanin ustunde arama
 * sessizce kullanilamaz hale gelirdi. SFU'ya gecis ise medyanin Janus'ta
 * acik olup olmadigina baglidir.
 */
class GroupCallCapacityTest {

    private val groupId = UUID.randomUUID().toString()

    @AfterEach
    fun tearDown() {
        GroupCallSessionStore.end(groupId)
    }

    private fun startCall(callType: String, mediaE2ee: Boolean = false) {
        GroupCallSessionStore.start(
            groupId = groupId,
            callId = UUID.randomUUID().toString(),
            coordinatorId = "coordinator",
            callType = callType,
            participants = listOf("coordinator"),
            mode = "MESH",
            mediaE2eeParticipants = if (mediaE2ee) setOf("coordinator") else emptySet(),
        )
    }

    @Test
    fun `mesh video calls stop at the practical ceiling`() {
        startCall("VIDEO")
        val capacity = SfuPolicy.meshCapacity("VIDEO")

        repeat(capacity - 1) { index ->
            assertEquals(
                GroupCallSessionStore.JoinResult.ADDED,
                GroupCallSessionStore.addParticipant(groupId, "member-$index", capacity),
            )
        }
        // Tavan dolduktan sonraki katilim sessizce degil, acikca reddedilir.
        assertEquals(
            GroupCallSessionStore.JoinResult.CAPACITY_REACHED,
            GroupCallSessionStore.addParticipant(groupId, "overflow", capacity),
        )
        assertEquals(capacity, GroupCallSessionStore.get(groupId)!!.participants.size)
    }

    @Test
    fun `voice calls carry a higher ceiling than video`() {
        assertTrue(SfuPolicy.meshCapacity("VOICE") > SfuPolicy.meshCapacity("VIDEO"))
        assertEquals(6, SfuPolicy.meshCapacity("VIDEO"))
        assertEquals(10, SfuPolicy.meshCapacity("VOICE"))
    }

    @Test
    fun `a rejoining participant does not consume a second slot`() {
        startCall("VOICE")
        val capacity = SfuPolicy.meshCapacity("VOICE")
        assertEquals(
            GroupCallSessionStore.JoinResult.ADDED,
            GroupCallSessionStore.addParticipant(groupId, "member", capacity),
        )
        assertEquals(
            GroupCallSessionStore.JoinResult.ALREADY_PRESENT,
            GroupCallSessionStore.addParticipant(groupId, "member", capacity),
        )
        assertEquals(2, GroupCallSessionStore.get(groupId)!!.participants.size)
    }

    @Test
    fun `parallel joins never exceed the ceiling`() {
        startCall("VIDEO")
        val capacity = SfuPolicy.meshCapacity("VIDEO")
        val attempts = capacity * 3
        val pool = Executors.newFixedThreadPool(8)
        try {
            val added = pool.invokeAll(
                (0 until attempts).map { index ->
                    Callable {
                        GroupCallSessionStore.addParticipant(groupId, "member-$index", capacity)
                    }
                },
            ).count { it.get() == GroupCallSessionStore.JoinResult.ADDED }
            assertEquals(capacity - 1, added)
            assertEquals(capacity, GroupCallSessionStore.get(groupId)!!.participants.size)
        } finally {
            pool.shutdown()
            pool.awaitTermination(30, TimeUnit.SECONDS)
        }
    }

    @Test
    fun `media encryption is only claimed when every participant declares it`() {
        startCall("VIDEO", mediaE2ee = true)
        val capacity = SfuPolicy.meshCapacity("VIDEO")

        GroupCallSessionStore.addParticipant(groupId, "capable", capacity, mediaE2ee = true)
        assertTrue(GroupCallSessionStore.get(groupId)!!.mediaEndToEndEncrypted)

        // Tek bir eski istemci bile karari dusurur.
        GroupCallSessionStore.addParticipant(groupId, "legacy", capacity, mediaE2ee = false)
        assertFalse(GroupCallSessionStore.get(groupId)!!.mediaEndToEndEncrypted)

        // Ayrildiginda karar geri gelir.
        assertTrue(GroupCallSessionStore.removeParticipant(groupId, "legacy"))
        assertTrue(GroupCallSessionStore.get(groupId)!!.mediaEndToEndEncrypted)
    }

    @Test
    fun `promotion without media encryption needs an explicit acknowledgement`() {
        val enabled = mapOf(
            "JANUS_WS_URL" to "ws://janus:8188",
            "SFU_ENABLED" to "true",
            "PRIVACY_PRODUCTION_MODE" to "true",
        )
        // Medya Janus'ta acik: kabul beyani olmadan gecilemez.
        assertFalse(SfuPolicy.canPromote(mediaEndToEndEncrypted = false, environment = enabled))
        assertTrue(
            SfuPolicy.canPromote(
                mediaEndToEndEncrypted = false,
                environment = enabled +
                    ("SFU_MEDIA_BOUNDARY_ACK" to SfuPolicy.REQUIRED_ACKNOWLEDGEMENT),
            ),
        )
        // Medya uctan uca sifreliyse Janus yalniz ciphertext yonlendirir;
        // beyan gerekmez.
        assertTrue(SfuPolicy.canPromote(mediaEndToEndEncrypted = true, environment = enabled))
    }

    @Test
    fun `an operator who never enabled the sfu never promotes`() {
        assertFalse(
            SfuPolicy.canPromote(
                mediaEndToEndEncrypted = true,
                environment = mapOf("JANUS_WS_URL" to "ws://janus:8188"),
            ),
        )
    }
}
