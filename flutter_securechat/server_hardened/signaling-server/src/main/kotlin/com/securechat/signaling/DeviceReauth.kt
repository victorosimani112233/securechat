package com.securechat.signaling

import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import java.security.MessageDigest
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("DeviceReauth")

@Serializable
internal data class DeviceReauthChallenge(val challengeId: String, val nonce: String, val expiresIn: Int)

@Serializable
internal data class DeviceReauthRequest(val challengeId: String, val refreshToken: String, val signature: String)

/**
 * Cihaz anahtariyla oturum yenileme (QA 2026-10-13 R3 madde 3).
 *
 * Refresh token tek kullanimlik; yenileme yaniti kaybolur ve telafi
 * penceresi de kacarsa cihazdaki token kalici olarak olur. Cihazda hesabin
 * Olm Ed25519 imzalama anahtari hala durur, sunucu acik anahtari
 * (`users.signing_public_key`) bilir. Istemci reddedilen refresh token'i ve
 * tek kullanimlik bir sunucu sorusunun imzasini birlikte sunarsa yeni token
 * cifti verilir.
 *
 * Iki kanit birlikte istenir:
 *  - Refresh token imzali ve epoch'u guncel olmali. Kusak eski olabilir
 *    (kaybolan rotasyon tam olarak budur), ama logout, kurtarma veya hesap
 *    silme epoch'u dondurdugu icin bu olaylardan sonra yol kapanir.
 *  - Imza hesabin pinli Ed25519 anahtarina uymali. Calinan token tek basina
 *    yetmez; calinan anahtar da tek basina yetmez.
 *
 * Soru Redis'te 120 sn yasar ve tek kullanimliktir (dogrulama denemesi
 * basarisiz olsa da tuketilir). Redis yoksa yol kapali (503).
 */
internal object DeviceReauth {
    const val CHALLENGE_TTL_SECONDS = 120

    sealed interface Outcome {
        data class Issued(val userId: String, val snapshot: CredentialState.Snapshot) : Outcome
        data object Rejected : Outcome
        data object Unavailable : Outcome
    }

    fun preimage(challengeId: String, nonce: String, userId: String, refreshToken: String): String =
        listOf("securechat/device-reauth/v1", challengeId, nonce, userId, sha256Hex(refreshToken)).joinToString("\n")

    /** @return null: soru saklanamadi (Redis yok). */
    fun issueChallenge(): DeviceReauthChallenge? {
        val challengeId = RecoveryRecordCipher.opaque()
        val nonce = RecoveryRecordCipher.opaque()
        return try {
            RedisManager.use { it.setex(challengeKey(challengeId), CHALLENGE_TTL_SECONDS.toLong(), nonce) }
            DeviceReauthChallenge(challengeId, nonce, CHALLENGE_TTL_SECONDS)
        } catch (error: Exception) {
            log.warn("[DeviceReauth] Soru saklanamadi: {}", error.javaClass.simpleName)
            null
        }
    }

    fun reauthenticate(request: DeviceReauthRequest): Outcome {
        if (!request.challengeId.matches(OPAQUE)) return Outcome.Rejected
        val nonce = try {
            RedisManager.use { it.getDel(challengeKey(request.challengeId)) }
        } catch (error: Exception) {
            log.warn("[DeviceReauth] Soru okunamadi: {}", error.javaClass.simpleName)
            return Outcome.Unavailable
        } ?: return Outcome.Rejected
        val claims = try {
            AuthService.refreshClaims(request.refreshToken, throwWhenUnavailable = true)
        } catch (_: AuthService.CredentialStateUnavailable) {
            return Outcome.Unavailable
        } ?: return Outcome.Rejected
        return try {
            val key = signingKey(claims.userId)
            if (key == null || key.size != 32 || !RecoveryRecordCipher.verify(
                    key,
                    preimage(request.challengeId, nonce, claims.userId, request.refreshToken),
                    request.signature,
                )
            ) return Outcome.Rejected
            CredentialState.forget(claims.userId)
            val current = CredentialState.snapshot(claims.userId) ?: return Outcome.Rejected
            // Epoch arada dondurulduyse (paralel logout) yeni token verilmez.
            if (current.credentialEpoch != claimsEpoch(request.refreshToken)) return Outcome.Rejected
            val rotated = CredentialState.rotateRefreshGeneration(claims.userId, current.refreshGeneration)
                ?: return Outcome.Rejected
            Outcome.Issued(claims.userId, rotated)
        } catch (error: Exception) {
            log.error("[DeviceReauth] Karar verilemedi (fail-closed): {}", error.javaClass.simpleName)
            Outcome.Unavailable
        }
    }

    private fun claimsEpoch(refreshToken: String): String? =
        runCatching { com.auth0.jwt.JWT.decode(refreshToken).getClaim("epc").asString() }.getOrNull()

    private fun signingKey(userId: String): ByteArray? = Database.getConnection().use { connection ->
        connection.prepareStatement("SELECT signing_public_key FROM users WHERE user_id = ?::uuid").use {
            it.setString(1, userId)
            it.executeQuery().use { rows -> if (rows.next()) rows.getBytes(1) else null }
        }
    }

    private fun challengeKey(challengeId: String) = "auth:device_reauth:" + sha256Hex(challengeId)

    private fun sha256Hex(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private val OPAQUE = Regex("[A-Za-z0-9_-]{43}")
}
