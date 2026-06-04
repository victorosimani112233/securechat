package com.securechat.botapi.signal

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.security.SecureRandom

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class KeyEncryptorTest {

    @BeforeAll
    fun setUp() {
        // 32 byte test master key — BotApiConfig.load() yerine direkt set
        BotApiConfig.botMasterKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
    }

    @Test
    fun `wrap and unwrap roundtrip`() {
        val plaintext = "Bu cok gizli bir Signal private key".toByteArray()
        val wrapped = KeyEncryptor.wrap(plaintext)
        val recovered = KeyEncryptor.unwrap(wrapped)
        assertThat(recovered).isEqualTo(plaintext)
    }

    @Test
    fun `different nonce for each wrap`() {
        val plaintext = "x".toByteArray()
        val w1 = KeyEncryptor.wrap(plaintext)
        val w2 = KeyEncryptor.wrap(plaintext)
        assertThat(w1.nonce).isNotEqualTo(w2.nonce)
        // Ciphertext de farkli olmali (random nonce)
        assertThat(w1.ciphertext).isNotEqualTo(w2.ciphertext)
    }

    @Test
    fun `unwrap fails with tampered ciphertext`() {
        val wrapped = KeyEncryptor.wrap("hello".toByteArray())
        val tampered = wrapped.ciphertext.copyOf().also { it[0] = (it[0].toInt() xor 0x01).toByte() }
        var threw = false
        try {
            KeyEncryptor.unwrap(KeyEncryptor.WrappedKey(tampered, wrapped.nonce))
        } catch (e: Exception) {
            threw = true   // AEADBadTagException veya benzer
        }
        assertThat(threw).isTrue()
    }
}
