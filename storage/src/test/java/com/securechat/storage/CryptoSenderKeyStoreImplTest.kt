package com.securechat.storage

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.crypto.CryptoSenderKeyStoreImpl
import com.securechat.storage.dao.SenderKeyDao
import com.securechat.storage.entity.SenderKeyEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * CryptoSenderKeyStoreImpl icin unit testler. DAO delegasyonu ve composite key dogrulanir.
 */
class CryptoSenderKeyStoreImplTest {

    private lateinit var dao: SenderKeyDao
    private lateinit var store: CryptoSenderKeyStoreImpl

    @Before
    fun setup() {
        dao = mockk(relaxed = true)
        store = CryptoSenderKeyStoreImpl(dao)
    }

    @Test
    fun `loadSenderKey returns record bytes from DAO`() = runTest {
        val record = byteArrayOf(1, 2, 3)
        coEvery { dao.get("g1", "alice", 1) } returns SenderKeyEntity("g1", "alice", 1, record, 100L)

        val result = store.loadSenderKey("g1", "alice", 1)

        assertThat(result).isEqualTo(record)
    }

    @Test
    fun `loadSenderKey returns null when not found`() = runTest {
        coEvery { dao.get("g1", "bob", 1) } returns null

        val result = store.loadSenderKey("g1", "bob", 1)

        assertThat(result).isNull()
    }

    @Test
    fun `storeSenderKey inserts entity with composite key`() = runTest {
        val record = byteArrayOf(9, 8, 7)
        val slot = slot<SenderKeyEntity>()
        coEvery { dao.put(capture(slot)) } returns Unit

        store.storeSenderKey("g1", "alice", 1, record)

        assertThat(slot.captured.groupId).isEqualTo("g1")
        assertThat(slot.captured.senderId).isEqualTo("alice")
        assertThat(slot.captured.deviceId).isEqualTo(1)
        assertThat(slot.captured.record).isEqualTo(record)
        assertThat(slot.captured.updatedAt).isGreaterThan(0L)
    }

    @Test
    fun `deleteSenderKey delegates to DAO with composite key`() = runTest {
        store.deleteSenderKey("g1", "alice", 1)

        coVerify { dao.delete("g1", "alice", 1) }
    }

    @Test
    fun `deleteAllForGroup delegates to DAO`() = runTest {
        store.deleteAllForGroup("g1")

        coVerify { dao.deleteAllForGroup("g1") }
    }

    @Test
    fun `containsSenderKey delegates to DAO exists`() = runTest {
        coEvery { dao.exists("g1", "alice", 1) } returns true

        assertThat(store.containsSenderKey("g1", "alice", 1)).isTrue()
    }
}
