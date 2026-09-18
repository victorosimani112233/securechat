package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * SFU, medya icin gercek bir uctan uca sifreleme siniri degildir: WebRTC
 * oturumu Janus'ta sonlanir. Bu yuzden varsayilan kapalidir ve production'da
 * acilmasi operatorun sinirI acikca kabul etmesini gerektirir.
 */
class SfuPolicyTest {

    private fun env(vararg pairs: Pair<String, String>) = mapOf(*pairs)

    @Test
    fun `the sfu is disabled by default`() {
        assertFalse(SfuPolicy.isEnabled(env()))
        assertFalse(SfuPolicy.isEnabled(env("JANUS_WS_URL" to "ws://janus:8188")))
    }

    @Test
    fun `enabling requires a janus endpoint`() {
        assertFalse(SfuPolicy.isEnabled(env("SFU_ENABLED" to "true")))
        assertThrows(IllegalArgumentException::class.java) {
            SfuPolicy.validate(env("SFU_ENABLED" to "true"))
        }
    }

    @Test
    fun `production requires an explicit media boundary acknowledgement`() {
        val requested = env(
            "SFU_ENABLED" to "true",
            "JANUS_WS_URL" to "ws://janus:8188",
            "PRIVACY_PRODUCTION_MODE" to "true",
        )
        assertFalse(SfuPolicy.isEnabled(requested))
        // Eksik beyan sessizce "kapali"ya donusmez; startup durur.
        assertThrows(IllegalArgumentException::class.java) { SfuPolicy.validate(requested) }

        val acknowledged = requested + ("SFU_MEDIA_BOUNDARY_ACK" to SfuPolicy.REQUIRED_ACKNOWLEDGEMENT)
        assertTrue(SfuPolicy.isEnabled(acknowledged))
        SfuPolicy.validate(acknowledged)
    }

    @Test
    fun `a wrong acknowledgement value does not enable the sfu`() {
        val env = env(
            "SFU_ENABLED" to "true",
            "JANUS_WS_URL" to "ws://janus:8188",
            "PRIVACY_PRODUCTION_MODE" to "true",
            "SFU_MEDIA_BOUNDARY_ACK" to "true",
        )
        assertFalse(SfuPolicy.isEnabled(env))
        assertThrows(IllegalArgumentException::class.java) { SfuPolicy.validate(env) }
    }

    @Test
    fun `the acknowledgement states what is being accepted`() {
        // Deger kopyalanirken ne kabul edildigi gizlenmemeli.
        assertEquals("sfu-media-not-end-to-end-encrypted", SfuPolicy.REQUIRED_ACKNOWLEDGEMENT)
    }

    @Test
    fun `outside production an explicit enable is enough`() {
        assertTrue(
            SfuPolicy.isEnabled(
                env("SFU_ENABLED" to "true", "JANUS_WS_URL" to "ws://janus:8188"),
            ),
        )
    }
}
