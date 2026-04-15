package com.securechat.storage

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.crypto.CryptoSignedPreKeyStoreImpl
import com.securechat.storage.dao.SignedPreKeyDao
import com.securechat.storage.entity.SignedPreKeyEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

/**
 * CryptoSignedPreKeyStoreImpl icin unit testler.
 */
class CryptoSignedPreKeyStoreImplTest {

    private lateinit var signedPreKeyDao: SignedPreKeyDao
    private lateinit var store: CryptoSignedPreKeyStoreImpl

    @Before
    fun setup() {
        signedPreKeyDao = mockk(relaxed = true)
        store = CryptoSignedPreKeyStoreImpl(signedPreKeyDao)
    }

    @Test
    fun `loadSignedPreKey returns record when exists`() = runTest {
        val record = byteArrayOf(11, 22, 33)
        coEvery { signedPreKeyDao.get(5) } returns SignedPreKeyEntity(5, record, 1000L)

        val result = store.loadSignedPreKey(5)

        assertThat(result).isEqualTo(record)
    }

    @Test
    fun `loadSignedPreKey returns null when not exists`() = runTest {
        coEvery { signedPreKeyDao.get(99) } returns null

        val result = store.loadSignedPreKey(99)

        assertThat(result).isNull()
    }

    @Test
    fun `loadAllSignedPreKeys returns all records`() = runTest {
        val rec1 = byteArrayOf(1, 2)
        val rec2 = byteArrayOf(3, 4)
        coEvery { signedPreKeyDao.getAll() } returns listOf(
            SignedPreKeyEntity(1, rec1, 1000L),
            SignedPreKeyEntity(2, rec2, 2000L)
        )

        val result = store.loadAllSignedPreKeys()

        assertThat(result).hasSize(2)
        assertThat(result[0]).isEqualTo(rec1)
        assertThat(result[1]).isEqualTo(rec2)
    }

    @Test
    fun `storeSignedPreKey inserts entity with timestamp`() = runTest {
        val record = byteArrayOf(5, 6)
        val entitySlot = slot<SignedPreKeyEntity>()
        coEvery { signedPreKeyDao.insert(capture(entitySlot)) } returns Unit

        store.storeSignedPreKey(10, record)

        assertThat(entitySlot.captured.id).isEqualTo(10)
        assertThat(entitySlot.captured.record).isEqualTo(record)
        assertThat(entitySlot.captured.createdAt).isGreaterThan(0L)
    }

    @Test
    fun `containsSignedPreKey delegates to DAO`() = runTest {
        coEvery { signedPreKeyDao.exists(10) } returns true

        assertThat(store.containsSignedPreKey(10)).isTrue()
    }

    @Test
    fun `removeSignedPreKey delegates to DAO`() = runTest {
        store.removeSignedPreKey(10)

        coVerify { signedPreKeyDao.delete(10) }
    }
}
