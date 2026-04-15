package com.securechat.crypto

import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.state.IdentityKeyStore
import org.whispersystems.libsignal.util.KeyHelper
import com.google.common.truth.Truth.assertThat

/**
 * SecureChatProtocolStore unit testleri.
 * Mock store'lar ile Signal Protocol store interface'inin
 * dogru delegasyon yaptigini dogrular.
 */
class SecureChatProtocolStoreTest {

    private lateinit var preKeyStore: CryptoPreKeyStore
    private lateinit var signedPreKeyStore: CryptoSignedPreKeyStore
    private lateinit var sessionStore: CryptoSessionStore
    private lateinit var identityStore: CryptoIdentityStore
    private lateinit var protocolStore: SecureChatProtocolStore

    @Before
    fun setUp() {
        preKeyStore = mockk(relaxed = true)
        signedPreKeyStore = mockk(relaxed = true)
        sessionStore = mockk(relaxed = true)
        identityStore = mockk(relaxed = true)
        protocolStore = SecureChatProtocolStore(
            preKeyStore = preKeyStore,
            signedPreKeyStore = signedPreKeyStore,
            sessionStore = sessionStore,
            identityStore = identityStore
        )
    }

    @Test
    fun `getIdentityKeyPair should deserialize from store`() {
        val keyPair = KeyHelper.generateIdentityKeyPair()
        coEvery { identityStore.getIdentityKeyPair() } returns keyPair.serialize()

        val result = protocolStore.identityKeyPair
        assertThat(result.publicKey).isEqualTo(keyPair.publicKey)
    }

    @Test(expected = IllegalStateException::class)
    fun `getIdentityKeyPair should throw when not found`() {
        coEvery { identityStore.getIdentityKeyPair() } returns null
        protocolStore.identityKeyPair
    }

    @Test
    fun `getLocalRegistrationId should delegate to identity store`() {
        coEvery { identityStore.getLocalRegistrationId() } returns 12345

        val result = protocolStore.localRegistrationId
        assertThat(result).isEqualTo(12345)
    }

    @Test
    fun `saveIdentity should serialize and store identity key`() {
        val keyPair = KeyHelper.generateIdentityKeyPair()
        val address = SignalProtocolAddress("user123", 1)
        coEvery { identityStore.storeIdentity(any(), any()) } returns false

        val result = protocolStore.saveIdentity(address, keyPair.publicKey)
        assertThat(result).isFalse()

        coVerify { identityStore.storeIdentity("user123", keyPair.publicKey.serialize()) }
    }

    @Test
    fun `isTrustedIdentity should return true for new identity`() {
        val keyPair = KeyHelper.generateIdentityKeyPair()
        val address = SignalProtocolAddress("newuser", 1)
        coEvery { identityStore.loadIdentity("newuser") } returns null

        val result = protocolStore.isTrustedIdentity(
            address,
            keyPair.publicKey,
            IdentityKeyStore.Direction.SENDING
        )
        assertThat(result).isTrue()
    }

    @Test
    fun `isTrustedIdentity should return true for matching identity`() {
        val keyPair = KeyHelper.generateIdentityKeyPair()
        val address = SignalProtocolAddress("existinguser", 1)
        coEvery { identityStore.loadIdentity("existinguser") } returns keyPair.publicKey.serialize()

        val result = protocolStore.isTrustedIdentity(
            address,
            keyPair.publicKey,
            IdentityKeyStore.Direction.SENDING
        )
        assertThat(result).isTrue()
    }

    @Test
    fun `isTrustedIdentity should return false for changed identity`() {
        val originalKeyPair = KeyHelper.generateIdentityKeyPair()
        val newKeyPair = KeyHelper.generateIdentityKeyPair()
        val address = SignalProtocolAddress("changeduser", 1)
        coEvery { identityStore.loadIdentity("changeduser") } returns originalKeyPair.publicKey.serialize()

        val result = protocolStore.isTrustedIdentity(
            address,
            newKeyPair.publicKey,
            IdentityKeyStore.Direction.SENDING
        )
        assertThat(result).isFalse()
    }

    @Test
    fun `containsPreKey should delegate to prekey store`() {
        coEvery { preKeyStore.containsPreKey(42) } returns true

        val result = protocolStore.containsPreKey(42)
        assertThat(result).isTrue()
    }

    @Test
    fun `containsSession should delegate to session store`() {
        val address = SignalProtocolAddress("peer1", 1)
        coEvery { sessionStore.containsSession("peer1", 1) } returns true

        val result = protocolStore.containsSession(address)
        assertThat(result).isTrue()
    }

    @Test
    fun `loadSession should return new SessionRecord when not found`() {
        val address = SignalProtocolAddress("unknown", 1)
        coEvery { sessionStore.loadSession("unknown", 1) } returns null

        val result = protocolStore.loadSession(address)
        assertThat(result).isNotNull()
    }

    @Test
    fun `getSubDeviceSessions should delegate to session store`() {
        coEvery { sessionStore.getSubDeviceSessions("user1") } returns listOf(1, 2, 3)

        val result = protocolStore.getSubDeviceSessions("user1")
        assertThat(result).containsExactly(1, 2, 3)
    }

    @Test
    fun `getAvailablePreKeyCount should delegate to prekey store`() = runTest {
        coEvery { preKeyStore.getAvailablePreKeyCount() } returns 50

        val result = protocolStore.getAvailablePreKeyCount()
        assertThat(result).isEqualTo(50)
    }

    @Test
    fun `getNextPreKeyId should delegate to prekey store`() = runTest {
        coEvery { preKeyStore.getNextPreKeyId() } returns 101

        val result = protocolStore.getNextPreKeyId()
        assertThat(result).isEqualTo(101)
    }
}
