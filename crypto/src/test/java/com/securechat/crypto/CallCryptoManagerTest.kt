package com.securechat.crypto

import com.securechat.crypto.store.CryptoIdentityStore
import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.crypto.store.CryptoSignedPreKeyStore
import io.mockk.mockk
import org.junit.Before
import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * CallCryptoManager unit testleri.
 * SRTP key turetimi ve bellek sifirlama islemlerini dogrular.
 */
class CallCryptoManagerTest {

    private lateinit var protocolStore: SecureChatProtocolStore
    private lateinit var callCryptoManager: CallCryptoManager

    @Before
    fun setUp() {
        protocolStore = SecureChatProtocolStore(
            preKeyStore = mockk(relaxed = true),
            signedPreKeyStore = mockk(relaxed = true),
            sessionStore = mockk(relaxed = true),
            identityStore = mockk(relaxed = true)
        )
        callCryptoManager = CallCryptoManager(protocolStore)
    }

    @Test
    fun `deriveCallEncryptionKey should return keys with correct sizes`() {
        val keys = callCryptoManager.deriveCallEncryptionKey("peer1")
        assertThat(keys.masterKey).hasLength(32)
        assertThat(keys.masterSalt).hasLength(32)
    }

    @Test
    fun `deriveCallEncryptionKey should return non-zero keys`() {
        val keys = callCryptoManager.deriveCallEncryptionKey("peer1")
        val allZeroKey = ByteArray(32) { 0 }
        // Kriptografik olarak rastgele uretilen anahtarlarin tamami sifir olmamali
        assertThat(keys.masterKey).isNotEqualTo(allZeroKey)
    }

    @Test
    fun `deriveCallEncryptionKey should generate different keys each time`() {
        val keys1 = callCryptoManager.deriveCallEncryptionKey("peer1")
        val keys2 = callCryptoManager.deriveCallEncryptionKey("peer1")
        // Rastgele nonce kullanildigindan her seferinde farkli anahtar uretilmeli
        assertThat(keys1.masterKey).isNotEqualTo(keys2.masterKey)
    }

    @Test
    fun `keys should be clearable after derivation`() {
        val keys = callCryptoManager.deriveCallEncryptionKey("peer1")
        keys.clear()
        val expectedZero = ByteArray(32) { 0 }
        assertThat(keys.masterKey).isEqualTo(expectedZero)
        assertThat(keys.masterSalt).isEqualTo(expectedZero)
    }
}
