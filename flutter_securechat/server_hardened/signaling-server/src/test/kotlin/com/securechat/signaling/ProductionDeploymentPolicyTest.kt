package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class ProductionDeploymentPolicyTest {
    private val valid = mapOf(
        "PRIVACY_PRODUCTION_MODE" to "true",
        "DATABASE_URL" to "jdbc:postgresql://db.internal/securechat?sslmode=verify-full",
        "DIRECTORY_OPRF_KEY_BACKEND" to "PKCS11",
        "ALLOW_LEGACY_PLAINTEXT_QUEUE" to "false",
        "SMTP_TLS" to "starttls",
        "JANUS_WS_URL" to "ws://janus:8188",
        "JANUS_PUBLIC_WS_URL" to "wss://janus.example.invalid",
        "FIREBASE_SERVICE_ACCOUNT_PATH" to "/run/secrets/firebase_service_account",
        "TURN_HOST" to "relay.example.invalid",
        "SEALED_SENDER_SERVER_CERTIFICATE" to "Zm9ybWF0LWNoZWNrZWQtZWxzZXdoZXJl",
        "SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY" to "Zm9ybWF0LWNoZWNrZWQtZWxzZXdoZXJl",
    )

    @Test
    fun `accepts the fail-closed production boundary`() {
        assertDoesNotThrow { ProductionDeploymentPolicy.validate(valid) }
    }

    @Test
    fun `refuses a trust-root private key on the relay`() {
        // Trust root public key istemci binary'sine pinlidir; ozel anahtari
        // ele geciren biri istedigi hesap adina gecerli sender certificate
        // uretebilir ve bu ancak yeni bir uygulama surumuyle geri alinir.
        // Relay'in calismak icin ozel anahtara ihtiyaci yoktur.
        assertThrows(IllegalArgumentException::class.java) {
            ProductionDeploymentPolicy.validate(
                valid + ("SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY" to "c29tZS1wcml2YXRlLWtleS1tYXRlcmlhbA=="),
            )
        }
    }

    @Test
    fun `requires an offline-issued sender certificate`() {
        for (missing in listOf(
            "SEALED_SENDER_SERVER_CERTIFICATE",
            "SEALED_SENDER_TRUST_ROOT_PUBLIC_KEY",
        )) {
            assertThrows(IllegalArgumentException::class.java) {
                ProductionDeploymentPolicy.validate(valid - missing)
            }
        }
    }

    @Test
    fun `rejects insecure database transport or embedded credentials`() {
        for (url in listOf(
            "jdbc:postgresql://db.internal/securechat",
            "jdbc:postgresql://user:secret@db.internal/securechat?sslmode=verify-full",
            "jdbc:postgresql://db.internal/securechat?sslmode=verify-full&password=secret",
            "jdbc:postgresql://db.internal/securechat?sslmode=require",
        )) {
            assertThrows(IllegalArgumentException::class.java) {
                ProductionDeploymentPolicy.validate(valid + ("DATABASE_URL" to url))
            }
        }
    }

    @Test
    fun `rejects non-production crypto and transport settings`() {
        for (override in listOf(
            mapOf("PRIVACY_PRODUCTION_MODE" to "false"),
            mapOf("DIRECTORY_OPRF_KEY_BACKEND" to "PKCS8"),
            mapOf("ALLOW_LEGACY_PLAINTEXT_QUEUE" to "true"),
            mapOf("SMTP_TLS" to "none"),
            mapOf("JANUS_PUBLIC_WS_URL" to "ws://public.example.invalid"),
            mapOf("FIREBASE_SERVICE_ACCOUNT_PATH" to "relative.json"),
            // Duz TURN, relay adresini ve kimligi yol uzerindeki gozlemciye acar.
            mapOf("TURN_ALLOW_PLAINTEXT" to "true"),
            mapOf("TURN_HOST" to ""),
        )) {
            assertThrows(IllegalArgumentException::class.java) {
                ProductionDeploymentPolicy.validate(valid + override)
            }
        }
    }
}
