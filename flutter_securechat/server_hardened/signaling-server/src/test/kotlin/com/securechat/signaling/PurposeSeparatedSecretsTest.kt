package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class PurposeSeparatedSecretsTest {
    private fun environment(): MutableMap<String, String> = mutableMapOf(
        "PRIVACY_INDEX_KEY" to "privacy-index",
        "OFFLINE_QUEUE_ENCRYPTION_KEY" to "offline-queue",
        "FCM_TOKEN_ENCRYPTION_KEY" to "fcm-token",
        "JWT_SECRET" to "jwt-secret",
        "TURN_SECRET" to "turn-secret",
        "METRICS_BEARER_TOKEN" to "metrics-token",
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
            this["JANUS_API_SECRET"] = "janus-api"
            this["JANUS_ADMIN_SECRET"] = getValue("JWT_SECRET")
        }
        assertThrows(IllegalArgumentException::class.java) {
            PurposeSeparatedSecrets.validate(environment)
        }
    }
}
