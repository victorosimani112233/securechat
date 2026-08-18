package com.securechat.botapi.signal

import com.securechat.botapi.BotApiConfig
import java.security.Signature
import java.util.Base64
import java.util.UUID

/**
 * Bot'un signaling'e karsi kimligi.
 *
 * Onceki `BotJwtMinter` signaling ile ayni HS256 secret'ini tasiyor ve
 * istedigi `sub` icin gecerli bir kullanici access token'i uretebiliyordu.
 * Burada imza materyali botun kendi Ed25519 private key'idir; signaling
 * yalniz karsilik gelen public key'i tutar. Bot ihlali artik yalniz botun
 * kendi kimligini ve yalniz asagidaki dar kapsamlari verir.
 *
 * Bicim `sc1.<b64url(payload)>.<b64url(imza)>`; signaling tarafindaki
 * `ServiceAssertion` ile birebir aynidir.
 */
object BotServiceTokenMinter {

    private const val PREFIX = "sc1"
    private const val LIFETIME_SECONDS = 60L

    private val encoder: Base64.Encoder = Base64.getUrlEncoder().withoutPadding()

    enum class Scope(val wire: String) {
        PREKEY_UPLOAD("prekey.upload"),
        PREKEY_FETCH("prekey.fetch"),
        WS_CONNECT("ws.connect"),
    }

    fun issue(subject: String, scope: Scope): String {
        val issuedAt = System.currentTimeMillis() / 1000
        val payload = buildString {
            append("{\"sub\":\"").append(subject)
            append("\",\"scp\":\"").append(scope.wire)
            append("\",\"iat\":").append(issuedAt)
            append(",\"exp\":").append(issuedAt + LIFETIME_SECONDS)
            append(",\"jti\":\"").append(UUID.randomUUID())
            append("\"}")
        }
        val signingInput = "$PREFIX.${encoder.encodeToString(payload.toByteArray(Charsets.UTF_8))}"
        val signature = Signature.getInstance("Ed25519").run {
            initSign(BotApiConfig.serviceSigningKey)
            update(signingInput.toByteArray(Charsets.US_ASCII))
            sign()
        }
        return "$signingInput.${encoder.encodeToString(signature)}"
    }
}
