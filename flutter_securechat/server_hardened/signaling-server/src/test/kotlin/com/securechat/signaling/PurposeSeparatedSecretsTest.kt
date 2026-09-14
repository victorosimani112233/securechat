package com.securechat.signaling

import java.util.Base64
import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class PurposeSeparatedSecretsTest {
    private fun key(seed: Int): String = Base64.getEncoder().encodeToString(
        ByteArray(32) { (seed + it).toByte() },
    )

    private fun environment(): MutableMap<String, String> = mutableMapOf(
        "PRIVACY_INDEX_KEY" to key(1),
        "OFFLINE_QUEUE_ENCRYPTION_KEY" to key(65),
        "FCM_TOKEN_ENCRYPTION_KEY" to key(129),
        "JWT_SECRET" to "jwt-secret-material-with-more-than-32-bytes",
        "TURN_SECRET" to "turn-secret-material-with-more-than-32-bytes",
        "METRICS_BEARER_TOKEN" to "metrics-bearer-material-with-more-than-32-bytes",
    )

    @Test
    fun `accepts purpose-separated secrets`() {
        assertDoesNotThrow { PurposeSeparatedSecrets.validate(environment()) }
    }

    @Test
    fun `rejects reuse across encryption and authentication purposes`() {
        val environment = environment().apply {
            this["FCM_TOKEN_ENCRYPTION_KEY"] = getValue("PRIVACY_INDEX_KEY")
        }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(environment)
        }
    }

    @Test
    fun `includes Janus secrets when SFU is enabled`() {
        val environment = environment().apply {
            this["JANUS_WS_URL"] = "wss://janus.invalid"
            this["JANUS_API_SECRET"] = "janus-api-material-with-more-than-32-bytes"
            this["JANUS_ADMIN_SECRET"] = getValue("JWT_SECRET")
        }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(environment)
        }
    }

    @Test
    fun `rejects equivalent padded and unpadded base64 key material`() {
        val material = ByteArray(32) { (it + 1).toByte() }
        val padded = Base64.getEncoder().encodeToString(material)
        val environment = environment().apply {
            this["PRIVACY_INDEX_KEY"] = padded
            this["FCM_TOKEN_ENCRYPTION_KEY"] = padded.trimEnd('=')
        }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(environment)
        }
    }

    @Test
    fun `rejects an AEAD key copied as an authentication secret`() {
        val material = ByteArray(32) { (it + 1).toByte() }
        val encoded = Base64.getEncoder().encodeToString(material)
        val environment = environment().apply {
            this["PRIVACY_INDEX_KEY"] = encoded
            this["JWT_SECRET"] = encoded
        }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(environment)
        }
    }

    @Test
    fun `rejects weak metrics and Janus authentication secrets`() {
        val weakMetrics = environment().apply {
            this["METRICS_BEARER_TOKEN"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(weakMetrics)
        }

        val weakJanus = environment().apply {
            this["JANUS_WS_URL"] = "wss://janus.invalid"
            this["JANUS_API_SECRET"] = "short"
            this["JANUS_ADMIN_SECRET"] = "janus-admin-material-with-more-than-32-bytes"
        }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(weakJanus)
        }
    }

    @Test
    fun `rejects short authentication secrets`() {
        val environment = environment().apply { this["TURN_SECRET"] = "short" }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(environment)
        }
    }

    @Test
    fun `rejects low diversity encryption keys`() {
        val weak = Base64.getEncoder().encodeToString(ByteArray(32) { 7 })
        val environment = environment().apply { this["PRIVACY_INDEX_KEY"] = weak }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(environment)
        }
    }
}
