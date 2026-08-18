package com.securechat.botapi

import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class ProductionDeploymentPolicyTest {
    private val valid = mapOf(
        "PRIVACY_PRODUCTION_MODE" to "true",
        "DATABASE_URL" to "jdbc:postgresql://db.internal/securechat?sslmode=verify-full",
        "ALLOW_LEGACY_PLAINTEXT_QUEUE" to "false",
        "BOT_PUBLIC_SOCKET" to "/run/bot/bot-public.sock",
        "BOT_ADMIN_SOCKET" to "/run/bot/bot-admin.sock",
    )

    @Test
    fun `accepts the production transport and socket boundary`() {
        assertDoesNotThrow { ProductionDeploymentPolicy.validate(valid) }
    }

    @Test
    fun `rejects insecure database and legacy queue settings`() {
        for (override in listOf(
            mapOf("DATABASE_URL" to "jdbc:postgresql://db.internal/securechat"),
            mapOf("DATABASE_URL" to "jdbc:postgresql://u:p@db/securechat?sslmode=verify-full"),
            mapOf("DATABASE_URL" to "jdbc:postgresql://db/securechat?sslmode=verify-full&password=p"),
            mapOf("ALLOW_LEGACY_PLAINTEXT_QUEUE" to "true"),
            mapOf("PRIVACY_PRODUCTION_MODE" to "false"),
        )) {
            assertThrows(IllegalArgumentException::class.java) {
                ProductionDeploymentPolicy.validate(valid + override)
            }
        }
    }

    @Test
    fun `rejects Unix socket paths outside the private tmpfs`() {
        for (socket in listOf("/tmp/public.sock", "/run/bot/../public.sock")) {
            assertThrows(IllegalArgumentException::class.java) {
                ProductionDeploymentPolicy.validate(
                    valid + ("BOT_PUBLIC_SOCKET" to socket),
                )
            }
        }
    }
}
