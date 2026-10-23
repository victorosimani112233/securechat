package com.securechat.signaling

import java.util.Base64
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Olm prekey yuklemesinin alan sinirlari.
 *
 * Onceki akista one-time key sayisi ve anahtar boyutlari sinirsizdi: tek bir
 * istek binlerce satir yazdirabiliyor ya da cok buyuk alanlarla depolamayi
 * sisirebiliyordu. Ayni keyId'nin tekrari da engellenmiyordu.
 */
class PreKeyUploadBoundsTest {

    private fun b64(size: Int): String =
        Base64.getEncoder().encodeToString(ByteArray(size) { 7 })

    private fun request(
        identity: String? = b64(32),
        signing: String? = b64(32),
        oneTimeKeys: List<OlmPreKeyEntry> = listOf(OlmPreKeyEntry("k1", b64(32))),
        fallback: String? = b64(32),
        fallbackSignature: String? = b64(64),
    ) = PreKeyUploadRequest(
        olmIdentityKey = identity,
        olmSigningKey = signing,
        olmOneTimeKeys = oneTimeKeys,
        olmFallbackKey = fallback,
        olmFallbackKeySignature = fallbackSignature,
    )

    @Test
    fun `a well formed bundle is accepted`() {
        assertTrue(request().hasSaneKeyMaterial())
    }

    @Test
    fun `an upload without an olm identity is refused`() {
        // libsignal alanlari kaldirildi; eski govde artik kimliksiz sayilir.
        assertFalse(request(identity = null, oneTimeKeys = emptyList(), fallback = null, fallbackSignature = null).hasSaneKeyMaterial())
        assertFalse(request(signing = null).hasSaneKeyMaterial())
    }

    @Test
    fun `the one time key count is capped`() {
        val atCap = (1..MAX_ONE_TIME_PREKEYS).map { OlmPreKeyEntry("k$it", b64(32)) }
        val overCap = (1..MAX_ONE_TIME_PREKEYS + 1).map { OlmPreKeyEntry("k$it", b64(32)) }

        assertTrue(request(oneTimeKeys = atCap).hasSaneKeyMaterial())
        assertFalse(request(oneTimeKeys = overCap).hasSaneKeyMaterial())
    }

    @Test
    fun `duplicate key ids are refused`() {
        val duplicated = listOf(OlmPreKeyEntry("k5", b64(32)), OlmPreKeyEntry("k5", b64(32)))

        assertFalse(request(oneTimeKeys = duplicated).hasSaneKeyMaterial())
    }

    @Test
    fun `keys must be exactly 32 bytes`() {
        assertFalse(request(identity = b64(33)).hasSaneKeyMaterial())
        assertFalse(request(signing = b64(31)).hasSaneKeyMaterial())
        assertFalse(request(fallback = b64(33)).hasSaneKeyMaterial())
        assertFalse(request(fallbackSignature = b64(63)).hasSaneKeyMaterial())
        assertFalse(request(oneTimeKeys = listOf(OlmPreKeyEntry("k1", b64(33)))).hasSaneKeyMaterial())
    }

    @Test
    fun `non base64 key material is refused instead of throwing`() {
        assertFalse(request(identity = "!!!not base64!!!").hasSaneKeyMaterial())
        assertFalse(request(oneTimeKeys = listOf(OlmPreKeyEntry("k1", "%%%"))).hasSaneKeyMaterial())
    }

    @Test
    fun `key ids stay inside the declared length`() {
        assertFalse(request(oneTimeKeys = listOf(OlmPreKeyEntry("", b64(32)))).hasSaneKeyMaterial())
        assertFalse(request(oneTimeKeys = listOf(OlmPreKeyEntry("k".repeat(65), b64(32)))).hasSaneKeyMaterial())
    }

    @Test
    fun `fallback key and signature come together`() {
        assertFalse(request(fallbackSignature = null).hasSaneKeyMaterial())
        assertFalse(request(fallback = null).hasSaneKeyMaterial())
        assertTrue(request(fallback = null, fallbackSignature = null).hasSaneKeyMaterial())
    }

    @Test
    fun `an empty one time key list is still a valid upload`() {
        assertTrue(request(oneTimeKeys = emptyList()).hasSaneKeyMaterial())
    }
}
