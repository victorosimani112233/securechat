package com.securechat.botapi.auth

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test

/**
 * Dogrulama sirasi.
 *
 * Nonce, body hash kontrolunden **once** tuketilirse yakalanmis bir token
 * yanlis bir body ile oynatildiginda mesru istegin nonce'u yanar ve gercek
 * istek replay sayilip reddedilir. Bu, mesru istemciye karsi bir hizmet
 * engelidir.
 */
class VerificationOrderTest {

    /** Yorum satirlari haric kaynak; sira gercek cagri yerlerine gore olculur. */
    private val source = java.io.File(
        "src/main/kotlin/com/securechat/botapi/auth/EdDsaJwtVerifier.kt",
    ).readLines()
        .filterNot { it.trimStart().startsWith("*") || it.trimStart().startsWith("//") }
        .joinToString("\n")

    @Test
    fun `body hash is validated before the nonce is consumed`() {
        val bodyHashIndex = source.indexOf("BodyHashValidator.check")
        val nonceIndex = source.indexOf("NonceStore.tryConsume")

        assertThat(bodyHashIndex).isGreaterThan(0)
        assertThat(nonceIndex).isGreaterThan(0)
        assertThat(bodyHashIndex).isLessThan(nonceIndex)
    }

    @Test
    fun `both checks remain mandatory`() {
        // Herhangi biri kaldirilirsa token yeniden oynatilabilir ya da
        // istegin govdesi degistirilebilir hale gelir.
        assertThat(source).contains("Reason.BODY_HASH_MISMATCH")
        assertThat(source).contains("Reason.REPLAYED_JTI")
    }
}
