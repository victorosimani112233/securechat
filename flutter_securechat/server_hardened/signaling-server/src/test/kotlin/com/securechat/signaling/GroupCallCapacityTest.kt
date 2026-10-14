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
 * Grup aramasinin katilimci tavani.
 *
 * Mesh'te her cihaz N-1 encode ve N-1 upload yapar; tavanin ustunde arama
 * sessizce kullanilamaz hale gelirdi.
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
            mediaE2eeParticipants = if (mediaE2ee) setOf("coordinator") else emptySet(),
        )
    }

    @Test
    fun `mesh video calls stop at the practical ceiling`() {
        startCall("VIDEO")
        val capacity = GroupCallSessionStore.MAX_PARTICIPANTS

        repeat(capacity - 1) { index ->
            assertEquals(
                GroupCallSessionStore.JoinResult.ADDED,
                GroupCallSessionStore.addParticipant(groupId, "member-$index"),
            )
        }
        // Tavan dolduktan sonraki katilim sessizce degil, acikca reddedilir.
        assertEquals(
            GroupCallSessionStore.JoinResult.CAPACITY_REACHED,
            GroupCallSessionStore.addParticipant(groupId, "overflow"),
        )
        assertEquals(capacity, GroupCallSessionStore.get(groupId)!!.participants.size)
    }

    @Test
    fun `voice and video both admit eight`() {
        assertEquals(8, GroupCallSessionStore.MAX_PARTICIPANTS)
    }

    @Test
    fun `a rejoining participant does not consume a second slot`() {
        startCall("VOICE")
        val capacity = GroupCallSessionStore.MAX_PARTICIPANTS
        assertEquals(
            GroupCallSessionStore.JoinResult.ADDED,
            GroupCallSessionStore.addParticipant(groupId, "member"),
        )
        assertEquals(
            GroupCallSessionStore.JoinResult.ALREADY_PRESENT,
            GroupCallSessionStore.addParticipant(groupId, "member"),
        )
        assertEquals(2, GroupCallSessionStore.get(groupId)!!.participants.size)
    }

    @Test
    fun `parallel joins never exceed the ceiling`() {
        startCall("VIDEO")
        val capacity = GroupCallSessionStore.MAX_PARTICIPANTS
        val attempts = capacity * 3
        val pool = Executors.newFixedThreadPool(8)
        try {
            val added = pool.invokeAll(
                (0 until attempts).map { index ->
                    Callable {
                        GroupCallSessionStore.addParticipant(groupId, "member-$index")
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
        val capacity = GroupCallSessionStore.MAX_PARTICIPANTS

        GroupCallSessionStore.addParticipant(groupId, "capable", mediaE2ee = true)
        assertTrue(GroupCallSessionStore.get(groupId)!!.mediaEndToEndEncrypted)

        // Tek bir eski istemci bile karari dusurur.
        GroupCallSessionStore.addParticipant(groupId, "legacy", mediaE2ee = false)
        assertFalse(GroupCallSessionStore.get(groupId)!!.mediaEndToEndEncrypted)

        // Ayrildiginda karar geri gelir.
        assertTrue(GroupCallSessionStore.removeParticipant(groupId, "legacy"))
        assertTrue(GroupCallSessionStore.get(groupId)!!.mediaEndToEndEncrypted)
    }
}
