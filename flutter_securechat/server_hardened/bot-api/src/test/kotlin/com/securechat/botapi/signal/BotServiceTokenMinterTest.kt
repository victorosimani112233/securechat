package com.securechat.botapi.signal

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64

/**
 * Uretilen servis assertion'inin signaling tarafindaki `ServiceAssertion`
 * sozlesmesine uydugunu sabitler: `sc1.<b64url payload>.<b64url imza>`,
 * imza ilk iki bolumun ASCII byte'lari uzerinde, omur ust siniri altinda.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class BotServiceTokenMinterTest {

    private lateinit var keys: KeyPair
    private val decoder: Base64.Decoder = Base64.getUrlDecoder()
    private val subject = "123e4567-e89b-42d3-a456-426614174000"

    @BeforeAll
    fun setUp() {
        keys = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        BotApiConfig.serviceSigningKey = keys.private
    }

    @Test
    fun `assertion carries the documented envelope and verifies with the public key`() {
        val assertion = BotServiceTokenMinter.issue(
            subject,
            BotServiceTokenMinter.Scope.PREKEY_UPLOAD,
        )

        val parts = assertion.split('.')
        assertThat(parts).hasSize(3)
        assertThat(parts[0]).isEqualTo("sc1")

        val verified = Signature.getInstance("Ed25519").run {
            initVerify(keys.public)
            update("${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII))
            verify(decoder.decode(parts[2]))
        }
        assertThat(verified).isTrue()

        val payload = decoder.decode(parts[1]).toString(Charsets.UTF_8)
        assertThat(payload).contains("\"sub\":\"$subject\"")
        assertThat(payload).contains("\"scp\":\"prekey.upload\"")
        assertThat(payload).contains("\"jti\":\"")
    }

    @Test
    fun `lifetime stays inside the verifier ceiling`() {
        val assertion = BotServiceTokenMinter.issue(
            subject,
            BotServiceTokenMinter.Scope.WS_CONNECT,
        )
        val payload = decoder.decode(assertion.split('.')[1]).toString(Charsets.UTF_8)
        val issuedAt = Regex("\"iat\":(\\d+)").find(payload)!!.groupValues[1].toLong()
        val expiresAt = Regex("\"exp\":(\\d+)").find(payload)!!.groupValues[1].toLong()
        assertThat(expiresAt - issuedAt).isAtMost(120L)
        assertThat(expiresAt).isGreaterThan(issuedAt)
    }

    @Test
    fun `each scope is emitted verbatim`() {
        for (scope in BotServiceTokenMinter.Scope.entries) {
            val assertion = BotServiceTokenMinter.issue(subject, scope)
            val payload = decoder.decode(assertion.split('.')[1]).toString(Charsets.UTF_8)
            assertThat(payload).contains("\"scp\":\"${scope.wire}\"")
        }
    }

    @Test
    fun `every assertion gets a distinct identifier`() {
        val first = BotServiceTokenMinter.issue(subject, BotServiceTokenMinter.Scope.PREKEY_FETCH)
        val second = BotServiceTokenMinter.issue(subject, BotServiceTokenMinter.Scope.PREKEY_FETCH)
        assertThat(first).isNotEqualTo(second)
    }
}
