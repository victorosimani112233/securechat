package com.securechat.botapi.signal

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import org.junit.jupiter.api.Test
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * Operator formatinin sabitlenmesi.
 *
 * Deployment anahtarlari `openssl genpkey -algorithm ed25519 -outform DER |
 * base64` ile uretilir. Asagidaki cift gercek openssl ciktisidir; JVM'in bu
 * bicimi okuyabildigi ve uretilen assertion'in karsilik gelen X.509 public
 * key ile dogrulandigi burada kanitlanir. Bu anahtar yalniz test icindir ve
 * hicbir ortamda kullanilmaz.
 */
class ServiceKeyFormatTest {

    private val privateKeyBase64 =
        "MC4CAQAwBQYDK2VwBCIEIHrd2qa8dTkNh0LP8lRTUFow4R902qTUlXQOAxKG2lWo"
    private val publicKeyBase64 =
        "MCowBQYDK2VwAyEA1DxUafOsZjhLghjqA7cxL6NjlrYqQMYb3oVqYTHUYb8="

    @Test
    fun `an openssl generated key pair drives the service assertion end to end`() {
        val privateKey = KeyFactory.getInstance("Ed25519").generatePrivate(
            PKCS8EncodedKeySpec(Base64.getDecoder().decode(privateKeyBase64)),
        )
        val publicKey = KeyFactory.getInstance("Ed25519").generatePublic(
            X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)),
        )
        BotApiConfig.serviceSigningKey = privateKey

        val assertion = BotServiceTokenMinter.issue(
            "123e4567-e89b-42d3-a456-426614174000",
            BotServiceTokenMinter.Scope.WS_CONNECT,
        )

        val parts = assertion.split('.')
        val verified = Signature.getInstance("Ed25519").run {
            initVerify(publicKey)
            update("${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII))
            verify(Base64.getUrlDecoder().decode(parts[2]))
        }
        assertThat(verified).isTrue()
    }
}
