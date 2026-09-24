package com.securechat.signaling

import kotlinx.coroutines.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test

class GroupCallAdmissionLifecycleTest {
    @Test
    fun `departed invitee can rejoin but outsider and encryption downgrade cannot`() {
        val added = GroupCallSessionStore.JoinResult.ADDED
        assertEquals(added, GroupCallSessionStore.invite("g", "c", "host", "VOICE", "member", true))
        GroupCallSessionStore.removeParticipant("g", "member")
        assertTrue("member" in GroupCallSessionStore.get("g")!!.invitedParticipants)
        assertFalse("member" in GroupCallSessionStore.get("g")!!.participants)
        assertEquals(GroupCallSessionStore.JoinResult.NOT_INVITED,
            GroupCallSessionStore.confirmJoin("g", "c", "host", "VOICE", "outsider", true))
        assertEquals(GroupCallSessionStore.JoinResult.ENCRYPTION_REQUIRED,
            GroupCallSessionStore.confirmJoin("g", "c", "host", "VOICE", "member", false))
        assertEquals(added, GroupCallSessionStore.confirmJoin("g", "c", "host", "VOICE", "member", true))
        assertTrue("member" in GroupCallSessionStore.get("g")!!.joinedParticipants)
        GroupCallSessionStore.end("g")
        assertEquals(GroupCallSessionStore.JoinResult.CALL_NOT_FOUND,
            GroupCallSessionStore.confirmJoin("g", "c", "host", "VOICE", "member", true))
    }

    @BeforeEach
    @AfterEach
    fun clearFixtures() {
        GroupCallSessionStore.all().keys.forEach { GroupCallSessionStore.end(it) }
        GroupCallSessionStore.roomsAwaitingCleanup().forEach { GroupCallSessionStore.roomCleanupCompleted(it.instanceId) }
    }

    @Test
    fun `per user admission is atomic across different routing tokens`() = runBlocking {
        val results = (1..64).map { n -> async(Dispatchers.Default) {
            GroupCallSessionStore.invite("group$n", "call$n", "caller", "VIDEO", "recipient$n", true)
        } }.awaitAll()
        assertEquals(GroupCallSessionStore.MAX_CALLS_PER_USER, results.count { it == GroupCallSessionStore.JoinResult.ADDED })
        assertEquals(60, results.count { it == GroupCallSessionStore.JoinResult.USER_CAPACITY_REACHED })
        GroupCallSessionStore.end("group" + (1..64).first { GroupCallSessionStore.get("group$it") != null })
        assertEquals(GroupCallSessionStore.JoinResult.ADDED,
            GroupCallSessionStore.invite("replacement", "call", "caller", "VOICE", "new-peer", true))
    }

    @Test
    fun `global admission is bounded atomically and expiry releases mesh reservations`() = runBlocking {
        val limit = GroupCallSessionStore.MAX_ACTIVE_CALLS
        val results = (1..limit + 32).map { n -> async(Dispatchers.Default) {
            GroupCallSessionStore.invite("group$n", "call$n", "caller$n", "VOICE", "peer$n", true)
        } }.awaitAll()
        assertEquals(limit, results.count { it == GroupCallSessionStore.JoinResult.ADDED })
        assertEquals(32, results.count { it == GroupCallSessionStore.JoinResult.SERVER_CAPACITY_REACHED })
        cleanExpiredGroupCalls(System.currentTimeMillis() + GroupCallSessionStore.MAX_CALL_LIFETIME_MILLIS + 1) {
            fail<Unit>("Mesh expiry must not touch Janus")
        }
        assertTrue(GroupCallSessionStore.all().isEmpty())
        assertEquals(GroupCallSessionStore.JoinResult.ADDED,
            GroupCallSessionStore.invite("new", "call", "caller", "VIDEO", "peer", true))
    }

    @Test
    fun `expiry cannot race a join to resurrect an expired snapshot`() = runBlocking {
        repeat(100) { n ->
            val group = "race$n"
            GroupCallSessionStore.invite(group, "call", "caller", "VOICE", "peer", true)
            val expiredAt = System.currentTimeMillis() + GroupCallSessionStore.MAX_CALL_LIFETIME_MILLIS + 1
            listOf(
                async(Dispatchers.Default) { repeat(10) { GroupCallSessionStore.confirmJoin(group, "call", "caller", "VOICE", "peer", true) } },
                async(Dispatchers.Default) { GroupCallSessionStore.purgeExpired(expiredAt) },
                async(Dispatchers.Default) { repeat(10) { GroupCallSessionStore.addParticipant(group, "peer2", 8, true) } },
            ).awaitAll()
            assertNull(GroupCallSessionStore.get(group))
        }
    }

    @Test
    fun `expired SFU disposal retries with old instance and cannot end replacement`() = runBlocking {
        GroupCallSessionStore.start("group", "A", "caller", "VIDEO", listOf("caller"), "SFU", 42)
        val old = requireNotNull(GroupCallSessionStore.get("group"))
        val expiredAt = old.startedAt + GroupCallSessionStore.MAX_CALL_LIFETIME_MILLIS + 1
        cleanExpiredGroupCalls(expiredAt) { call ->
            assertEquals(old.instanceId, call.instanceId)
            error("Janus unavailable")
        }
        assertNull(GroupCallSessionStore.get("group"))
        assertEquals(listOf(old), GroupCallSessionStore.roomsAwaitingCleanup())
        assertEquals(GroupCallSessionStore.JoinResult.ADDED,
            GroupCallSessionStore.invite("group", "B", "caller", "VIDEO", "peer", true))
        val replacement = requireNotNull(GroupCallSessionStore.get("group"))
        GroupCallSessionStore.end("group", old.instanceId)
        cleanExpiredGroupCalls { call -> assertEquals(old.instanceId, call.instanceId) }
        assertTrue(GroupCallSessionStore.roomsAwaitingCleanup().isEmpty())
        assertEquals(replacement, GroupCallSessionStore.get("group"))
    }

    @Test
    fun `failed SFU disposal retains per user capacity until cleanup succeeds`() = runBlocking {
        repeat(GroupCallSessionStore.MAX_CALLS_PER_USER) { n ->
            GroupCallSessionStore.start("sfu$n", "c$n", "caller", "VOICE", listOf("caller"), "SFU", n + 1L)
            GroupCallSessionStore.end("sfu$n")
        }
        assertEquals(GroupCallSessionStore.JoinResult.USER_CAPACITY_REACHED,
            GroupCallSessionStore.invite("new", "c", "caller", "VIDEO", "peer", true))
        cleanExpiredGroupCalls { }
        assertEquals(GroupCallSessionStore.JoinResult.ADDED,
            GroupCallSessionStore.invite("new", "c", "caller", "VIDEO", "peer", true))
    }
}
