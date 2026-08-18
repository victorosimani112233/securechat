package com.securechat.botapi.auth

import java.security.MessageDigest
import java.util.Base64

/**
 * JWT payload'undaki "bh" claim'inin (base64url SHA-256 of raw body) gercekten
 * gelen body bytes ile esleshtigini constant-time karsilastirma ile dogrular.
 *
 * Body'i JSON parse ETMEDEN once raw byte hash al — JSON anahtar sirasi
 * farklarinin imzayi bozmamasi icin kritik.
 */
object BodyHashValidator {

    private val urlEncoder = Base64.getUrlEncoder().withoutPadding()

    /** Raw body byte'larinin SHA-256 hash'ini base64url-no-padding olarak dondurur. */
    fun computeBodyHash(body: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(body)
        return urlEncoder.encodeToString(digest)
    }

    /**
     * Constant-time compare — timing attack koruyucu.
     * @return true ise eslesir, aksi halde false.
     */
    fun check(expectedClaim: String, body: ByteArray): Boolean {
        val computed = computeBodyHash(body)
        return MessageDigest.isEqual(
            computed.toByteArray(Charsets.UTF_8),
            expectedClaim.toByteArray(Charsets.UTF_8)
        )
    }
}
