package com.securechat.crypto

import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import io.mockk.coEvery
import io.mockk.mockk
import org.junit.Before
import org.junit.Test
import org.whispersystems.libsignal.SignalProtocolAddress
import com.google.common.truth.Truth.assertThat

/**
 * SessionManager unit testleri.
 * Session varlik kontrolu ve SessionCipher erisimini dogrular.
 */
class SessionManagerTest {

    private lateinit var preKeyStore: CryptoPreKeyStore
    private lateinit var signedPreKeyStore: CryptoSignedPreKeyStore
    private lateinit var sessionStore: CryptoSessionStore
    private lateinit var identityStore: CryptoIdentityStore
    private lateinit var protocolStore: SecureChatProtocolStore
    private lateinit var sessionManager: SessionManager

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
        sessionManager = SessionManager(protocolStore)
    }

    @Test
    fun `hasSession should return false when no session exists`() {
        coEvery { sessionStore.containsSession("user1", 1) } returns false

        val result = sessionManager.hasSession("user1")
        assertThat(result).isFalse()
    }

    @Test
    fun `hasSession should return true when session exists`() {
        coEvery { sessionStore.containsSession("user1", 1) } returns true

        val result = sessionManager.hasSession("user1")
        assertThat(result).isTrue()
    }

    @Test
    fun `hasSession should use custom deviceId`() {
        coEvery { sessionStore.containsSession("user1", 2) } returns true

        val result = sessionManager.hasSession("user1", deviceId = 2)
        assertThat(result).isTrue()
    }

    @Test
    fun `getSessionCipher should return cipher for address`() {
        val address = SignalProtocolAddress("user1", 1)
        val cipher = sessionManager.getSessionCipher(address)
        assertThat(cipher).isNotNull()
    }
}
