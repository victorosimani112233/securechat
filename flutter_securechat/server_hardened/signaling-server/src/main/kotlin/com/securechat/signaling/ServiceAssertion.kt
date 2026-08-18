package com.securechat.signaling

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/**
 * Servis hesabi (bot) kimlik dogrulamasi.
 *
 * Onceki tasarimda bot, signaling ile ayni HS256 `JWT_SECRET`'ini tasiyor ve
 * istedigi `sub` icin gecerli bir kullanici access token'i uretebiliyordu. Bu,
 * bot container'inin ihlalini butun kullanicilarin taklit edilebilmesine
 * cevirir. Burada imza materyali asimetriktir: signaling yalniz public key
 * tutar, bir signaling ihlali servis assertion'i uretemez; bot ihlali ise
 * yalniz botun kendi kimligini ve yalniz asagidaki dar scope'lari verir.
 *
 * Bicim (kompakt, JWT degil — kutuphane bagimliligi yok):
 *
 *     sc1.<b64url(payload)>.<b64url(ed25519 imza)>
 *
 * Imza `sc1.<b64url(payload)>` ASCII byte'lari uzerindedir. Payload:
 *
 *     {"sub":"<uuid>","scp":"<scope>","iat":<epoch_sn>,"exp":<epoch_sn>,
 *      "jti":"<uuid>"}
 *
 * Assertion omru [ServiceAssertion.MAX_LIFETIME_SECONDS] ile sinirlidir.
 * Bu, internal ag icinde yakalanmis bir assertion'in kullanim penceresini
 * daraltir; kalici bir credential degildir.
 */
object ServiceAssertion {

    const val PREFIX = "sc1"
    const val MAX_LIFETIME_SECONDS = 120L
    private const val CLOCK_SKEW_SECONDS = 30L

    /** Servis hesabinin erisebilecegi dar yetki kumesi. */
    enum class Scope(val wire: String) {
        PREKEY_UPLOAD("prekey.upload"),
        PREKEY_FETCH("prekey.fetch"),
        WS_CONNECT("ws.connect"),
        ;

        companion object {
            fun fromWire(value: String?): Scope? = entries.firstOrNull { it.wire == value }
        }
    }

    sealed interface Result {
        data class Accepted(val subject: String, val scope: Scope) : Result
        data object Rejected : Result
    }

    private val decoder: Base64.Decoder = Base64.getUrlDecoder()
    private val json = Json { ignoreUnknownKeys = true }
    private val uuidPattern = Regex(
        "(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    )

    fun parsePublicKey(base64X509: String): PublicKey {
        val encoded = Base64.getDecoder().decode(base64X509.trim())
        return KeyFactory.getInstance("Ed25519")
            .generatePublic(X509EncodedKeySpec(encoded))
    }

    /**
     * Assertion'i dogrular. Herhangi bir bicim, imza, sure veya scope hatasi
     * ayrimsiz `Rejected` doner; cagirana hangi kontrolun dustugu sizdirilmaz.
     */
    fun verify(
        assertion: String,
        publicKey: PublicKey,
        requiredScope: Scope,
        nowSeconds: Long = System.currentTimeMillis() / 1000,
    ): Result {
        val parts = assertion.split('.')
        if (parts.size != 3 || parts[0] != PREFIX) return Result.Rejected

        val signedBytes = "${parts[0]}.${parts[1]}".toByteArray(Charsets.US_ASCII)
        val payloadBytes = try {
            decoder.decode(parts[1])
        } catch (_: IllegalArgumentException) {
            return Result.Rejected
        }
        val signatureBytes = try {
            decoder.decode(parts[2])
        } catch (_: IllegalArgumentException) {
            return Result.Rejected
        }

        val signatureValid = try {
            Signature.getInstance("Ed25519").run {
                initVerify(publicKey)
                update(signedBytes)
                verify(signatureBytes)
            }
        } catch (_: Exception) {
            false
        }
        if (!signatureValid) return Result.Rejected

        val payload = try {
            json.parseToJsonElement(payloadBytes.toString(Charsets.UTF_8)).jsonObject
        } catch (_: Exception) {
            return Result.Rejected
        }

        val subject = payload["sub"]?.jsonPrimitive?.contentOrNullSafe() ?: return Result.Rejected
        if (!uuidPattern.matches(subject)) return Result.Rejected
        if (payload["jti"]?.jsonPrimitive?.contentOrNullSafe().isNullOrBlank()) return Result.Rejected

        val scope = Scope.fromWire(payload["scp"]?.jsonPrimitive?.contentOrNullSafe())
            ?: return Result.Rejected
        if (scope != requiredScope) return Result.Rejected

        val issuedAt = payload["iat"]?.jsonPrimitive?.longOrNull ?: return Result.Rejected
        val expiresAt = payload["exp"]?.jsonPrimitive?.longOrNull ?: return Result.Rejected
        if (expiresAt <= issuedAt) return Result.Rejected
        if (expiresAt - issuedAt > MAX_LIFETIME_SECONDS) return Result.Rejected
        if (nowSeconds >= expiresAt) return Result.Rejected
        if (issuedAt > nowSeconds + CLOCK_SKEW_SECONDS) return Result.Rejected

        return Result.Accepted(subject.lowercase(), scope)
    }

    private fun kotlinx.serialization.json.JsonPrimitive.contentOrNullSafe(): String? =
        if (isString) content else null
}
