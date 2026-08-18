package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class SecretSourceTest {
    @Test
    fun `reads a mounted secret without retaining its newline`() {
        val value = SecretSource.required(
            "JWT_SECRET",
            mapOf("JWT_SECRET_FILE" to "/run/secrets/jwt"),
        ) { path ->
            assertEquals("/run/secrets/jwt", path)
            "secret-value\n"
        }
        assertEquals("secret-value", value)
    }

    @Test
    fun `rejects ambiguous direct and file values`() {
        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "JWT_SECRET",
                mapOf(
                    "JWT_SECRET" to "old-value",
                    "JWT_SECRET_FILE" to "/run/secrets/jwt",
                ),
            ) { "new-value" }
        }
    }

    @Test
    fun `rejects empty mounted secrets`() {
        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "JWT_SECRET",
                mapOf("JWT_SECRET_FILE" to "/run/secrets/jwt"),
            ) { "\n" }
        }
    }
}
