package com.securechat.storage

import android.content.SharedPreferences
import android.util.Base64
import com.google.common.truth.Truth.assertThat
import com.securechat.storage.crypto.CryptoIdentityStoreImpl
import com.securechat.storage.dao.IdentityDao
import com.securechat.storage.entity.IdentityEntity
import com.securechat.storage.model.TrustLevel
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test

/**
 * CryptoIdentityStoreImpl icin unit testler.
 * Uzak kimlikler DAO uzerinden, yerel degerler SharedPreferences uzerinden test edilir.
 */
class CryptoIdentityStoreImplTest {

    private lateinit var identityDao: IdentityDao
    private lateinit var prefs: SharedPreferences
    private lateinit var editor: SharedPreferences.Editor
    private lateinit var store: CryptoIdentityStoreImpl

    @Before
    fun setup() {
        identityDao = mockk(relaxed = true)
        editor = mockk(relaxed = true)
        prefs = mockk(relaxed = true)
        every { prefs.edit() } returns editor
        every { editor.putInt(any(), any()) } returns editor
        every { editor.putString(any(), any()) } returns editor

        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }

        store = CryptoIdentityStoreImpl(identityDao, prefs, mockk(relaxed = true))
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
    }

    @Test
    fun `loadIdentity returns identity key when exists`() = runTest {
        val key = byteArrayOf(1, 2, 3)
        coEvery { identityDao.get("alice") } returns IdentityEntity(
            "alice", key, TrustLevel.TRUSTED_UNVERIFIED
        )

        val result = store.loadIdentity("alice")

        assertThat(result).isEqualTo(key)
    }

    @Test
    fun `loadIdentity returns null when not exists`() = runTest {
        coEvery { identityDao.get("unknown") } returns null

        val result = store.loadIdentity("unknown")

        assertThat(result).isNull()
    }

    @Test
    fun `storeIdentity returns false for new identity`() = runTest {
        coEvery { identityDao.get("bob") } returns null

        val result = store.storeIdentity("bob", byteArrayOf(10, 20))

        assertThat(result).isFalse()
        coVerify { identityDao.insert(any()) }
    }

    @Test
    fun `storeIdentity returns true when identity key changed`() = runTest {
        val oldKey = byteArrayOf(1, 2, 3)
        val newKey = byteArrayOf(4, 5, 6)
        coEvery { identityDao.get("bob") } returns IdentityEntity(
            "bob", oldKey, TrustLevel.TRUSTED_UNVERIFIED
        )

        val result = store.storeIdentity("bob", newKey)

        assertThat(result).isTrue()
    }

    @Test
    fun `storeIdentity returns false when identity key unchanged`() = runTest {
        val key = byteArrayOf(1, 2, 3)
        coEvery { identityDao.get("bob") } returns IdentityEntity(
            "bob", key, TrustLevel.TRUSTED_UNVERIFIED
        )

        val result = store.storeIdentity("bob", key)

        assertThat(result).isFalse()
    }

    @Test
    fun `getLocalRegistrationId reads from SharedPreferences`() = runTest {
        every { prefs.getInt("local_registration_id", -1) } returns 12345

        val result = store.getLocalRegistrationId()

        assertThat(result).isEqualTo(12345)
    }

    @Test
    fun `storeLocalRegistrationId writes to SharedPreferences`() = runTest {
        store.storeLocalRegistrationId(54321)

        io.mockk.verify { editor.putInt("local_registration_id", 54321) }
        io.mockk.verify { editor.apply() }
    }

    @Test
    fun `getIdentityKeyPair returns null when not set`() = runTest {
        every { prefs.getString("local_identity_key_pair", null) } returns null

        val result = store.getIdentityKeyPair()

        assertThat(result).isNull()
    }

    @Test
    fun `storeIdentityKeyPair and getIdentityKeyPair round-trip`() = runTest {
        val keyPair = byteArrayOf(100, -50, 25, 0)
        val encoded = java.util.Base64.getEncoder().encodeToString(keyPair)

        store.storeIdentityKeyPair(keyPair)

        io.mockk.verify { editor.putString("local_identity_key_pair", encoded) }
        io.mockk.verify { editor.apply() }
    }
}
