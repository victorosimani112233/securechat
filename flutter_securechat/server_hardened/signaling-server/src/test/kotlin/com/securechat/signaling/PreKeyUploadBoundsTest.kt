package com.securechat.signaling

import java.util.Base64
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Prekey yuklemesinin alan sinirlari.
 *
 * Onceki akista one-time prekey sayisi ve anahtar boyutlari sinirsizdi:
 * tek bir istek binlerce satir yazdirabiliyor ya da cok buyuk alanlarla
 * depolamayi sisirebiliyordu. Ayni keyId'nin tekrari da engellenmiyordu.
 */
class PreKeyUploadBoundsTest {

    private fun b64(size: Int): String =
        Base64.getEncoder().encodeToString(ByteArray(size) { 7 })

    private fun request(
        identity: String = b64(33),
        registrationId: Int = 1234,
        signedPreKeyId: Int = 7,
        signedPreKey: String = b64(33),
        signature: String = b64(64),
        oneTimePreKeys: List<PreKeyEntry> = listOf(PreKeyEntry(1, b64(33))),
    ) = PreKeyUploadRequest(
        identityPublicKey = identity,
        registrationId = registrationId,
        signedPreKeyId = signedPreKeyId,
        signedPreKey = signedPreKey,
        signedPreKeySignature = signature,
        oneTimePreKeys = oneTimePreKeys,
    )

    @Test
    fun `a well formed bundle is accepted`() {
        assertTrue(request().hasSaneKeyMaterial())
    }

    @Test
    fun `the one time prekey count is capped`() {
        val atCap = (1..MAX_ONE_TIME_PREKEYS).map { PreKeyEntry(it, b64(33)) }
        val overCap = (1..MAX_ONE_TIME_PREKEYS + 1).map { PreKeyEntry(it, b64(33)) }

        assertTrue(request(oneTimePreKeys = atCap).hasSaneKeyMaterial())
        assertFalse(request(oneTimePreKeys = overCap).hasSaneKeyMaterial())
    }

    @Test
    fun `duplicate key ids are refused`() {
        val duplicated = listOf(PreKeyEntry(5, b64(33)), PreKeyEntry(5, b64(33)))

        assertFalse(request(oneTimePreKeys = duplicated).hasSaneKeyMaterial())
    }

    @Test
    fun `oversized key material is refused`() {
        assertFalse(request(identity = b64(MAX_KEY_MATERIAL_BYTES + 1)).hasSaneKeyMaterial())
        assertFalse(request(signedPreKey = b64(MAX_KEY_MATERIAL_BYTES + 1)).hasSaneKeyMaterial())
        assertFalse(request(signature = b64(MAX_KEY_MATERIAL_BYTES + 1)).hasSaneKeyMaterial())
        assertFalse(
            request(oneTimePreKeys = listOf(PreKeyEntry(1, b64(MAX_KEY_MATERIAL_BYTES + 1))))
                .hasSaneKeyMaterial(),
        )
    }

    @Test
    fun `empty key material is refused`() {
        assertFalse(request(identity = "").hasSaneKeyMaterial())
        assertFalse(request(signedPreKey = "").hasSaneKeyMaterial())
        assertFalse(request(signature = "").hasSaneKeyMaterial())
    }

    @Test
    fun `non base64 key material is refused instead of throwing`() {
        assertFalse(request(identity = "!!!not base64!!!").hasSaneKeyMaterial())
        assertFalse(
            request(oneTimePreKeys = listOf(PreKeyEntry(1, "%%%"))).hasSaneKeyMaterial(),
        )
    }

    @Test
    fun `registration id stays inside the signal protocol range`() {
        assertFalse(request(registrationId = 0).hasSaneKeyMaterial())
        assertFalse(request(registrationId = -1).hasSaneKeyMaterial())
        assertFalse(request(registrationId = 16_384).hasSaneKeyMaterial())
        assertTrue(request(registrationId = 16_383).hasSaneKeyMaterial())
    }

    @Test
    fun `key ids stay inside the declared range`() {
        assertFalse(request(signedPreKeyId = -1).hasSaneKeyMaterial())
        assertFalse(request(signedPreKeyId = 0x1_000_000).hasSaneKeyMaterial())
        assertFalse(
            request(oneTimePreKeys = listOf(PreKeyEntry(-1, b64(33)))).hasSaneKeyMaterial(),
        )
    }

    @Test
    fun `an empty one time prekey list is still a valid upload`() {
        // Yalniz identity/signed prekey yenileyen bir istemci gecerlidir.
        assertTrue(request(oneTimePreKeys = emptyList()).hasSaneKeyMaterial())
    }
}
