package com.securechat.storage

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.crypto.CryptoPreKeyStoreImpl
import com.securechat.storage.dao.PreKeyDao
import com.securechat.storage.entity.PreKeyEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * CryptoPreKeyStoreImpl icin unit testler.
 * DAO mock'lanarak store operasyonlari test edilir.
 */
class CryptoPreKeyStoreImplTest {

    private lateinit var preKeyDao: PreKeyDao
    private lateinit var store: CryptoPreKeyStoreImpl

    @Before
    fun setup() {
        preKeyDao = mockk(relaxed = true)
        store = CryptoPreKeyStoreImpl(preKeyDao)
    }

    @Test
    fun `loadPreKey returns record when exists`() = runTest {
        val record = byteArrayOf(1, 2, 3, 4)
        coEvery { preKeyDao.get(42) } returns PreKeyEntity(42, record)

        val result = store.loadPreKey(42)

        assertThat(result).isEqualTo(record)
    }

    @Test
    fun `loadPreKey returns null when not exists`() = runTest {
        coEvery { preKeyDao.get(99) } returns null

        val result = store.loadPreKey(99)

        assertThat(result).isNull()
    }

    @Test
    fun `storePreKey inserts entity via DAO`() = runTest {
        val record = byteArrayOf(5, 6, 7)

        store.storePreKey(10, record)

        coVerify { preKeyDao.insert(PreKeyEntity(10, record)) }
    }

    @Test
    fun `containsPreKey delegates to DAO exists`() = runTest {
        coEvery { preKeyDao.exists(10) } returns true
        coEvery { preKeyDao.exists(99) } returns false

        assertThat(store.containsPreKey(10)).isTrue()
        assertThat(store.containsPreKey(99)).isFalse()
    }

    @Test
    fun `removePreKey delegates to DAO delete`() = runTest {
        store.removePreKey(42)

        coVerify { preKeyDao.delete(42) }
    }

    @Test
    fun `getAvailablePreKeyCount returns DAO count`() = runTest {
        coEvery { preKeyDao.count() } returns 25

        assertThat(store.getAvailablePreKeyCount()).isEqualTo(25)
    }

    @Test
    fun `getNextPreKeyId returns maxId plus one`() = runTest {
        coEvery { preKeyDao.maxId() } returns 99

        assertThat(store.getNextPreKeyId()).isEqualTo(100)
    }

    @Test
    fun `getNextPreKeyId returns 0 when no keys exist`() = runTest {
        coEvery { preKeyDao.maxId() } returns null

        assertThat(store.getNextPreKeyId()).isEqualTo(0)
    }
}
