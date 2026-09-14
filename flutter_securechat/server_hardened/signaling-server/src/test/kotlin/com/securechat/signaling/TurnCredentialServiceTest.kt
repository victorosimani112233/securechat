package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * TURN relay yapilandirmasi.
 *
 * Duz `turn:` uzerinde username ve relay adresi yol uzerindeki gozlemciye
 * aciktir; production'da yalniz `turns:` sunulmalidir.
 */
class TurnCredentialServiceTest {

    private fun servers(environment: Map<String, String>) =
        TurnCredentialService.iceServers("1:user", "sig", environment)

    @Test
    fun `production only offers tls relays`() {
        val result = servers(
            mapOf(
                "TURN_HOST" to "relay.example",
                "PRIVACY_PRODUCTION_MODE" to "true",
                // Acikca istense bile production'da duz relay eklenmez.
                "TURN_ALLOW_PLAINTEXT" to "true",
            ),
        )

        val relays = result.filter { it.credential != null }
        assertTrue(relays.isNotEmpty())
        assertTrue(relays.all { it.urls.startsWith("turns:") }, result.toString())
        assertTrue(result.any { it.urls.startsWith("stun:") })
    }

    @Test
    fun `tls relay is offered before any plaintext relay`() {
        val result = servers(
            mapOf(
                "TURN_HOST" to "relay.example",
                "TURN_ALLOW_PLAINTEXT" to "true",
            ),
        )

        val firstRelay = result.first { it.credential != null }
        assertTrue(firstRelay.urls.startsWith("turns:"), firstRelay.urls)
        assertTrue(result.any { it.urls.startsWith("turn:") })
    }

    @Test
    fun `plaintext relay stays off unless explicitly enabled`() {
        val result = servers(mapOf("TURN_HOST" to "relay.example"))

        assertTrue(result.none { it.urls.startsWith("turn:") }, result.toString())
    }

    @Test
    fun `tls host and port can differ from the stun endpoint`() {
        val result = servers(
            mapOf(
                "TURN_HOST" to "relay.example",
                "TURN_PORT" to "3478",
                "TURN_TLS_HOST" to "turn.example",
                "TURN_TLS_PORT" to "443",
            ),
        )

        assertEquals("stun:relay.example:3478", result.first().urls)
        assertTrue(result.all { it.credential == null || it.urls.startsWith("turns:turn.example:443") })
    }

    @Test
    fun `a missing host is refused instead of falling back to a baked in address`() {
        assertThrows(IllegalArgumentException::class.java) { servers(emptyMap()) }
    }

    @Test
    fun `an out of range port is refused`() {
        assertThrows(IllegalArgumentException::class.java) {
            servers(mapOf("TURN_HOST" to "relay.example", "TURN_TLS_PORT" to "70000"))
        }
    }

    @Test
    fun `production policy rejects plaintext turn`() {
        assertThrows(IllegalArgumentException::class.java) {
            ProductionDeploymentPolicy.requireTlsRelay(
                mapOf("TURN_HOST" to "relay.example", "TURN_ALLOW_PLAINTEXT" to "true"),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            ProductionDeploymentPolicy.requireTlsRelay(emptyMap())
        }
        ProductionDeploymentPolicy.requireTlsRelay(mapOf("TURN_HOST" to "relay.example"))
    }

    @Test
    fun `the secret is re-read so rotation does not need a restart`() {
        // `by lazy` surece sabitlerdi: operator secret'i degistirse bile
        // sunucu restart edilene kadar eski sir kullanilirdi.
        val text = java.io.File(
            "src/main/kotlin/com/securechat/signaling/TurnCredentialService.kt",
        ).readLines()
            .filterNot { it.trimStart().startsWith("*") || it.trimStart().startsWith("//") }
            .joinToString("\n")

        assertTrue("by lazy" !in text, "TURN secret surece sabitlenmemeli")
        assertTrue("SECRET_REFRESH_MILLIS" in text)
    }

    @Test
    fun `successive credentials use unlinkable opaque user tags`() {
        val first = TurnCredentialService.newOpaqueUserTag()
        val second = TurnCredentialService.newOpaqueUserTag()

        assertTrue(first.matches(Regex("^[A-Za-z0-9_-]{22}$")))
        assertTrue(second.matches(Regex("^[A-Za-z0-9_-]{22}$")))
        assertTrue(first != second)
    }

    @Test
    fun `coturn hmac sha1 matches the RFC 2202 known answer`() {
        val key = String(ByteArray(20) { 0x0b }, Charsets.ISO_8859_1)
        assertEquals(
            "thcxhlUFcmTii8C2+zeMjvFGvgA=",
            TurnCredentialService.hmacSha1(key, "Hi There"),
        )
    }
}
