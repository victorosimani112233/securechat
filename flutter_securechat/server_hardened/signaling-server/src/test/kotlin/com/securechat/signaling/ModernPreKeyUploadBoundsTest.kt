package com.securechat.signaling

import java.util.Base64
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ModernPreKeyUploadBoundsTest {
    private fun b64(size: Int): String =
        Base64.getEncoder().encodeToString(ByteArray(size) { 7 })

    private fun oneTime(
        id: Int = 1,
        ecSize: Int = 33,
        kyberSize: Int = 1568,
        signatureSize: Int = 64,
    ) = ModernOneTimePreKeyEntry(id, b64(ecSize), b64(kyberSize), b64(signatureSize))

    private fun request(
        protocolVersion: Int = 2,
        registrationId: Int = 1234,
        keys: List<ModernOneTimePreKeyEntry> = listOf(oneTime()),
        lastResortId: Int = 0xFFFFFF,
        lastResortSize: Int = 1568,
    ) = ModernPreKeyUploadRequest(
        protocolVersion = protocolVersion,
        identityPublicKey = b64(33),
        registrationId = registrationId,
        signedPreKeyId = 7,
        signedPreKey = b64(33),
        signedPreKeySignature = b64(64),
        oneTimePreKeys = keys,
        lastResortKyberPreKey = ModernKyberPreKeyEntry(
            lastResortId,
            b64(lastResortSize),
            b64(64),
            true,
        ),
    )

    @Test
    fun `well formed PQXDH material is accepted`() {
        assertTrue(request().hasSaneKeyMaterial())
    }

    @Test
    fun `wrong protocol and registration ranges are refused`() {
        assertFalse(request(protocolVersion = 1).hasSaneKeyMaterial())
        assertFalse(request(registrationId = 0).hasSaneKeyMaterial())
        assertFalse(request(registrationId = 16_381).hasSaneKeyMaterial())
    }

    @Test
    fun `duplicate and reserved one time ids are refused`() {
        assertFalse(request(keys = listOf(oneTime(9), oneTime(9))).hasSaneKeyMaterial())
        assertFalse(request(keys = listOf(oneTime(0xFFFFFF))).hasSaneKeyMaterial())
    }

    @Test
    fun `Kyber material has strict decoded bounds`() {
        assertFalse(request(keys = listOf(oneTime(kyberSize = 511))).hasSaneKeyMaterial())
        assertFalse(request(keys = listOf(oneTime(kyberSize = 4097))).hasSaneKeyMaterial())
        assertFalse(request(lastResortSize = 4097).hasSaneKeyMaterial())
        assertFalse(request(lastResortId = 4).hasSaneKeyMaterial())
    }

    @Test
    fun `invalid base64 is refused without throwing`() {
        val invalid = oneTime().copy(kyberPublicKey = "%%%")
        assertFalse(request(keys = listOf(invalid)).hasSaneKeyMaterial())
    }
}
