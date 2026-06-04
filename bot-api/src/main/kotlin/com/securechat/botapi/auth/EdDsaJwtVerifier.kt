package com.securechat.botapi.auth

import com.nimbusds.jose.JWSAlgorithm
import com.nimbusds.jose.JWSObject
import com.nimbusds.jwt.JWTClaimsSet
import org.slf4j.LoggerFactory
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

private val log = LoggerFactory.getLogger("EdDsaJwtVerifier")

/**
 * Bot-api JWT dogrulama pipeline'i — RFC 8037 EdDSA imzali kisa omurlu JWT.
 *
 * Beklenen format:
 *   Header:  { "alg": "EdDSA", "typ": "JWT", "kid": "<opaque>" }
 *   Claims:  { "aud": "securechat-bot-api",
 *              "iat": <unix>, "exp": <unix> (en fazla iat+60s),
 *              "jti": "<uuid>",
 *              "bh":  "<base64url SHA-256 of raw body>" }
 *
 * Imza dogrulama: JDK 17 native Signature("Ed25519") — Tink/BouncyCastle gerekmez.
 *
 * Pipeline:
 *  1. Header parse + alg=EdDSA + kid varligi
 *  2. ClientKeyCache.get(kid) -> revoked/expired filter
 *  3. Ed25519 signature verify (JDK native)
 *  4. iat/exp window check (±60s past, +5s forward skew)
 *  5. NonceStore.tryConsume(jti) — replay
 *  6. BodyHashValidator.check(bh, body) — body integrity
 */
class EdDsaJwtVerifier(private val clientLookup: (kid: String) -> AuthenticatedClient?) {

    sealed class Result {
        data class Ok(val client: AuthenticatedClient, val jti: String) : Result()
        data class Fail(val reason: Reason, val message: String) : Result()
    }

    enum class Reason {
        MALFORMED_TOKEN,
        WRONG_ALG,
        MISSING_KID,
        UNKNOWN_OR_REVOKED_CLIENT,
        BAD_SIGNATURE,
        EXPIRED,
        IAT_OUT_OF_WINDOW,
        WRONG_AUDIENCE,
        REPLAYED_JTI,
        BODY_HASH_MISMATCH
    }

    private val keyFactory = KeyFactory.getInstance("Ed25519")

    // X.509 prefix for Ed25519 SubjectPublicKeyInfo (12 byte) — raw 32 byte pubkey'in onune eklenir
    private val X509_ED25519_PREFIX = byteArrayOf(
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
    )

    fun verify(bearerToken: String, requestBody: ByteArray): Result {
        // 1. Parse
        val jws = try {
            JWSObject.parse(bearerToken)
        } catch (e: Exception) {
            return Result.Fail(Reason.MALFORMED_TOKEN, "JWT parse hatasi: ${e.message}")
        }

        if (jws.header.algorithm != JWSAlgorithm.EdDSA) {
            return Result.Fail(Reason.WRONG_ALG, "Yalnizca EdDSA kabul edilir (gelen: ${jws.header.algorithm})")
        }

        val kid = jws.header.keyID
            ?: return Result.Fail(Reason.MISSING_KID, "kid header zorunlu")

        // 2. Client lookup
        val client = clientLookup(kid)
            ?: return Result.Fail(Reason.UNKNOWN_OR_REVOKED_CLIENT, "kid bilinmiyor veya revoked: $kid")

        // 3. JDK native Ed25519 verify
        val sigOk = try {
            verifyEd25519(client.publicKey, jws)
        } catch (e: Exception) {
            log.warn("[JWT] Ed25519 verify exception (kid={}): {}", kid, e.message)
            false
        }
        if (!sigOk) {
            return Result.Fail(Reason.BAD_SIGNATURE, "Imza dogrulanamadi")
        }

        // 4. Claims
        val claims: JWTClaimsSet = try {
            JWTClaimsSet.parse(jws.payload.toJSONObject())
        } catch (e: Exception) {
            return Result.Fail(Reason.MALFORMED_TOKEN, "Claims parse hatasi: ${e.message}")
        }

        if (claims.audience == null || EXPECTED_AUDIENCE !in claims.audience) {
            return Result.Fail(Reason.WRONG_AUDIENCE, "aud=securechat-bot-api olmali")
        }

        val now = System.currentTimeMillis() / 1000
        val iat = claims.issueTime?.time?.div(1000)
            ?: return Result.Fail(Reason.IAT_OUT_OF_WINDOW, "iat zorunlu")
        val exp = claims.expirationTime?.time?.div(1000)
            ?: return Result.Fail(Reason.EXPIRED, "exp zorunlu")

        if (iat > now + 5) {
            return Result.Fail(Reason.IAT_OUT_OF_WINDOW, "iat gelecekte (skew>5s)")
        }
        if (iat < now - 60) {
            return Result.Fail(Reason.IAT_OUT_OF_WINDOW, "iat 60sn'den eski")
        }
        if (exp <= now) {
            return Result.Fail(Reason.EXPIRED, "Token suresi dolmus")
        }
        if (exp > iat + 60) {
            return Result.Fail(Reason.EXPIRED, "exp iat+60s'den uzun olamaz")
        }

        val jti = claims.jwtid
            ?: return Result.Fail(Reason.MALFORMED_TOKEN, "jti zorunlu")

        // 5. Replay
        if (!NonceStore.tryConsume(jti)) {
            return Result.Fail(Reason.REPLAYED_JTI, "jti tekrari (replay)")
        }

        // 6. Body hash
        val bhClaim = claims.getStringClaim("bh")
            ?: return Result.Fail(Reason.MALFORMED_TOKEN, "bh claim zorunlu")
        if (!BodyHashValidator.check(bhClaim, requestBody)) {
            return Result.Fail(Reason.BODY_HASH_MISMATCH, "Body hash claim'i body ile uyusmuyor")
        }

        return Result.Ok(client, jti)
    }

    /** Raw 32 byte Ed25519 pubkey ile JWS'in Ed25519 imzasini JDK native ile dogrula. */
    private fun verifyEd25519(rawPublicKey: ByteArray, jws: JWSObject): Boolean {
        require(rawPublicKey.size == 32) { "Ed25519 public key 32 byte olmali" }
        // X.509 wrap → PublicKey
        val x509 = X509_ED25519_PREFIX + rawPublicKey
        val publicKey = keyFactory.generatePublic(X509EncodedKeySpec(x509))
        // JWS signing input = base64url(header) + "." + base64url(payload)
        val signingInput = jws.signingInput
        val sigBytes = jws.signature.decode()
        val sig = Signature.getInstance("Ed25519")
        sig.initVerify(publicKey)
        sig.update(signingInput)
        return sig.verify(sigBytes)
    }

    companion object {
        const val EXPECTED_AUDIENCE = "securechat-bot-api"
    }
}

/** Cache'lenen client metadata'si — JWT verify oncesi lookup ile gelir. */
data class AuthenticatedClient(
    val clientId: String,
    val kid: String,
    val name: String,
    val publicKey: ByteArray,
    val allowList: List<String>,
    val ratePerHour: Int,
    val perRecipientPerDay: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AuthenticatedClient) return false
        return clientId == other.clientId
    }
    override fun hashCode(): Int = clientId.hashCode()
}
