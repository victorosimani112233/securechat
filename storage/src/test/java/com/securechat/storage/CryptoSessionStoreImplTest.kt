package com.securechat.storage

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.crypto.CryptoSessionStoreImpl
import com.securechat.storage.dao.SessionDao
import com.securechat.storage.entity.SessionEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * CryptoSessionStoreImpl icin unit testler.
 * Session id formati ($name:$deviceId) ve DAO delegasyonu test edilir.
 */
class CryptoSessionStoreImplTest {

    private lateinit var sessionDao: SessionDao
    private lateinit var store: CryptoSessionStoreImpl

    @Before
    fun setup() {
        sessionDao = mockk(relaxed = true)
        store = CryptoSessionStoreImpl(sessionDao)
    }

    @Test
    fun `loadSession builds correct id and returns record`() = runTest {
        val record = byteArrayOf(10, 20, 30)
        coEvery { sessionDao.get("alice:1") } returns SessionEntity("alice:1", record)

        val result = store.loadSession("alice", 1)

        assertThat(result).isEqualTo(record)
    }

    @Test
    fun `loadSession returns null when session not found`() = runTest {
        coEvery { sessionDao.get("bob:2") } returns null

        val result = store.loadSession("bob", 2)

        assertThat(result).isNull()
    }

    @Test
    fun `storeSession builds correct id and inserts`() = runTest {
        val record = byteArrayOf(1, 2)

        store.storeSession("alice", 3, record)

        coVerify { sessionDao.insert(SessionEntity("alice:3", record)) }
    }

    @Test
    fun `containsSession builds correct id and checks existence`() = runTest {
        coEvery { sessionDao.exists("alice:1") } returns true

        assertThat(store.containsSession("alice", 1)).isTrue()
    }

    @Test
    fun `deleteSession builds correct id and deletes`() = runTest {
        store.deleteSession("alice", 1)

        coVerify { sessionDao.delete("alice:1") }
    }

    @Test
    fun `deleteAllSessions delegates to DAO`() = runTest {
        store.deleteAllSessions("alice")

        coVerify { sessionDao.deleteAllForName("alice") }
    }

    @Test
    fun `getSubDeviceSessions parses device ids from session ids`() = runTest {
        coEvery { sessionDao.getSessionIdsForName("alice") } returns listOf(
            "alice:1", "alice:2", "alice:5"
        )

        val result = store.getSubDeviceSessions("alice")

        assertThat(result).containsExactly(1, 2, 5)
    }

    @Test
    fun `getSubDeviceSessions returns empty list when no sessions`() = runTest {
        coEvery { sessionDao.getSessionIdsForName("nobody") } returns emptyList()

        val result = store.getSubDeviceSessions("nobody")

        assertThat(result).isEmpty()
    }
}
