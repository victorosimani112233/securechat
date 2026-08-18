package com.securechat.botapi.db

import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class RedisEphemeralPolicyTest {
    @Test
    fun `bot redis accepts only no-aof no-rdb configuration`() {
        RedisEphemeralPolicy.requireMemoryOnly(
            mapOf("appendonly" to "no", "save" to "")
        )
        assertThrows(IllegalArgumentException::class.java) {
            RedisEphemeralPolicy.requireMemoryOnly(
                mapOf("appendonly" to "yes", "save" to "")
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            RedisEphemeralPolicy.requireMemoryOnly(
                mapOf("appendonly" to "no", "save" to "60 1000")
            )
        }
    }
}
