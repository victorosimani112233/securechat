package com.securechat.signaling

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

class RecoveryRecordCipherTest {
    private val cipher = RecoveryRecordCipher(ByteArray(32) { it.toByte() }, ByteArray(32) { (it + 32).toByte() })

    @Test fun `expiry fields survive default Ktor JSON serialization`() {
        val responses = listOf(
            Json.encodeToString(RecoveryChallenge("id", 600)),
            Json.encodeToString(RecoveryEnrollmentChallenge("id", "nonce", "epoch", "v1", 600)),
            Json.encodeToString(RecoveryGrant("token", "user", "v1", "key", 1234, 300)),
        )
        responses.forEach { assertTrue(Json.parseToJsonElement(it).jsonObject.containsKey("expiresIn")) }
    }

    @Test fun `AAD tampering and cross purpose indexes cannot alias`() {
        val encrypted = cipher.seal("binding-a", "account@example.com")
        assertEquals("account@example.com", cipher.open("binding-a", encrypted))
        assertThrows(Exception::class.java) { cipher.open("binding-b", encrypted) }
        encrypted[15] = (encrypted[15].toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { cipher.open("binding-a", encrypted) }
        assertNotEquals(cipher.index("enroll", "value"), cipher.index("login", "value"))
        assertNotEquals(cipher.index("email", "value"), cipher.index("account", "value"))
    }

    @Test fun `absent dedicated secrets disable recovery and partial configuration fails closed`() {
        assertNull(RecoveryRecordCipher.configured(emptyMap()))
        assertThrows(IllegalArgumentException::class.java) {
            RecoveryRecordCipher.configured(mapOf("RECOVERY_INDEX_KEY" to "test"))
        }
        assertThrows(IllegalArgumentException::class.java) { RecoveryRecordCipher(ByteArray(32) { it.toByte() }, ByteArray(32) { it.toByte() }) }
    }

    @Test fun `email normalization rejects header injection unicode and ambiguous addresses`() {
        assertEquals("alice@example.com", RecoveryRecordCipher.normalizeEmail(" Alice@EXAMPLE.COM "))
        for (email in listOf("a@example.com\nBcc:x@example.com", "a\u0000@example.com", "a@localhost", "a@@example.com", "a@ex\u00e4mple.com")) {
            assertThrows(IllegalArgumentException::class.java) { RecoveryRecordCipher.normalizeEmail(email) }
        }
    }

    @Test fun `signature preimages are immutable newline separated UTF8 without final newline`() {
        val context = RecoveryAuthService.Context("user", "alice@example.com", "epoch", "nonce", "v1")
        assertEquals("securechat/recovery-enroll/v1\nchallenge\nnonce\nuser\nepoch\nalice@example.com\nv1",
            RecoveryAuthService.enrollmentPreimage("challenge", context))
        val request = RecoveryComplete("token", "completion", "replace", "v1", "public", 42, "signature")
        val message = "securechat/recovery-complete/v1\ntoken\ncompletion\nuser\nreplace\nv1\npublic\n42"
        assertEquals(message, RecoveryAuthService.completionPreimage("user", request))
        // Kurtarma imzasi artik Ed25519 (vodozemac `account.sign()`), 32 bayt
        // ham acik anahtar. JDK Ed25519 X.509 ile cikti verdigi icin SPKI
        // onekini (12 bayt) soyup ham anahtari aliyoruz.
        val pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        val publicRaw = pair.public.encoded.copyOfRange(12, 44)
        val signature = Signature.getInstance("Ed25519").run {
            initSign(pair.private)
            update(message.toByteArray())
            Base64.getEncoder().encodeToString(sign())
        }
        assertTrue(RecoveryRecordCipher.verify(publicRaw, message, signature))
        assertFalse(RecoveryRecordCipher.verify(publicRaw, "$message\n", signature))
    }
}
