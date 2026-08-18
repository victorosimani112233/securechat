package com.securechat.botapi

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class SecretSourceTest {
    @Test
    fun `reads a mounted secret file`() {
        val value = SecretSource.required(
            "BOT_MASTER_KEY",
            mapOf("BOT_MASTER_KEY_FILE" to "/run/secrets/master"),
        ) { "base64-value\r\n" }
        assertEquals("base64-value", value)
    }

    @Test
    fun `does not let an environment value shadow a mounted secret`() {
        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "BOT_MASTER_KEY",
                mapOf(
                    "BOT_MASTER_KEY" to "old",
                    "BOT_MASTER_KEY_FILE" to "/run/secrets/master",
                ),
            ) { "new" }
        }
    }
}
