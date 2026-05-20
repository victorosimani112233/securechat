package com.securechat.botapi.auth

import com.nimbusds.jose.JWSAlgorithm
import com.nimbusds.jose.JWSObject
import com.nimbusds.jose.crypto.Ed25519Verifier
import com.nimbusds.jose.jwk.Curve
import com.nimbusds.jose.jwk.OctetKeyPair
import com.nimbusds.jwt.JWTClaimsSet
import org.slf4j.LoggerFactory
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
 * Pipeline:
 *  1. Header parse + alg=EdDSA + kid varligi
 *  2. ClientKeyCache.get(kid) → revoked/expired filter
 *  3. Ed25519 signature verify
 *  4. iat/exp window check (±60s past, +5s forward skew)
 *  5. NonceStore.tryConsume(jti) — replay
 *  6. BodyHashValidator.check(bh, body) — body integrity
 */
class EdDsaJwtVerifier(private val clientLookup: (kid: String) -> AuthenticatedClient?) {

    /** Verify sonucu. */
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

        // 2. Client lookup (cache + DB)
        val client = clientLookup(kid)
            ?: return Result.Fail(Reason.UNKNOWN_OR_REVOKED_CLIENT, "kid bilinmiyor veya revoked: $kid")

        // 3. Imza dogrulama — Nimbus Ed25519Verifier raw 32 byte public key bekler (base64url, OKP JWK)
        val verifier = try {
            buildEd25519Verifier(client.publicKey)
        } catch (e: Exception) {
            log.warn("[JWT] Ed25519 verifier olusturulamadi (kid={}): {}", kid, e.message)
            return Result.Fail(Reason.BAD_SIGNATURE, "Verifier insa edilemedi")
        }

        val sigOk = try { jws.verify(verifier) } catch (e: Exception) { false }
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

        // iat ±5s forward skew, -60s past tolerans
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

    /** Raw 32 byte Ed25519 public key → Nimbus Ed25519Verifier */
    private fun buildEd25519Verifier(rawPublicKey: ByteArray): Ed25519Verifier {
        require(rawPublicKey.size == 32) { "Ed25519 public key 32 byte olmali (${rawPublicKey.size})" }
        val xB64Url = Base64.getUrlEncoder().withoutPadding().encodeToString(rawPublicKey)
        val okp = OctetKeyPair.parse(
            """{"kty":"OKP","crv":"Ed25519","x":"$xB64Url"}"""
        )
        return Ed25519Verifier(okp)
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
