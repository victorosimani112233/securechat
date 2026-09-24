package com.securechat.signaling

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class GroupCallSessionPrivacyTest {
    @AfterEach
    fun clearEphemeralCalls() {
        GroupCallSessionStore.all().keys.forEach(GroupCallSessionStore::end)
    }

    @Test
    fun `active call metadata is explicit in-memory state and end erases it`() {
        val callToken = "A".repeat(43)
        GroupCallSessionStore.start(
            groupId = callToken,
            callId = "call-private",
            coordinatorId = "123e4567-e89b-42d3-a456-426614174000",
            callType = "VOICE",
            participants = listOf(
                "123e4567-e89b-42d3-a456-426614174000",
                "123e4567-e89b-42d3-a456-426614174001",
            ),
            mode = "MESH",
        )

        val active = GroupCallSessionStore.get(callToken)
        assertEquals("call-private", active?.callId)
        assertEquals(2, active?.participants?.size)
        assertTrue(GroupCallSessionStore.isActive(callToken))

        GroupCallSessionStore.end(callToken)
        assertNull(GroupCallSessionStore.get(callToken))
        assertFalse(GroupCallSessionStore.all().containsKey(callToken))
    }

    @Test
    fun `SFU promotion is one-shot and rollback restores mesh`() {
        val callToken = "B".repeat(43)
        GroupCallSessionStore.start(
            groupId = callToken,
            callId = "call-sfu",
            coordinatorId = "123e4567-e89b-42d3-a456-426614174000",
            callType = "VIDEO",
            participants = (0..6).map { "member-$it" },
            mediaE2eeParticipants = (0..6).map { "member-$it" }.toSet(),
            mode = "MESH",
        )
        val environment = mapOf("SFU_ENABLED" to "true", "JANUS_WS_URL" to "ws://localhost:8188")
        val pending = requireNotNull(GroupCallSessionStore.claimSfuPromotion(callToken, environment))
        assertNull(GroupCallSessionStore.claimSfuPromotion(callToken, environment))
        assertEquals("SFU_PENDING", GroupCallSessionStore.get(callToken)?.mode)
        GroupCallSessionStore.cancelSfuPromotion(pending)
        assertEquals("MESH", GroupCallSessionStore.get(callToken)?.mode)
    }
}
