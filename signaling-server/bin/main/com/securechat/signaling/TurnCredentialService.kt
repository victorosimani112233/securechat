package com.securechat.signaling

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.Base64

/**
 * TURN sunucusu icin dinamik HMAC-SHA1 credential uretir (RFC 8489).
 * coturn'de use-auth-secret + static-auth-secret ile uyumlu.
 *
 * username = "{expiry}:{userId}"
 * password = base64(hmac_sha1(TURN_SECRET, username))
 */
object TurnCredentialService {

    private val turnSecret: String = System.getenv("TURN_SECRET") ?: ""
    private val turnHost: String = System.getenv("TURN_HOST") ?: "185.48.182.124"
    private val turnPort: Int = System.getenv("TURN_PORT")?.toIntOrNull() ?: 3478
    private const val TTL_SECONDS = 86400L // 24 saat

    data class IceConfig(
        val iceServers: List<IceServer>,
        val ttl: Long
    )

    data class IceServer(
        val urls: String,
        val username: String? = null,
        val credential: String? = null
    )

    fun generateConfig(userId: String): IceConfig {
        val expiry = (System.currentTimeMillis() / 1000) + TTL_SECONDS
        val username = "$expiry:$userId"
        val credential = hmacSha1(turnSecret, username)

        return IceConfig(
            iceServers = listOf(
                IceServer(urls = "stun:$turnHost:$turnPort"),
                IceServer(
                    urls = "turn:$turnHost:$turnPort",
                    username = username,
                    credential = credential
                )
            ),
            ttl = TTL_SECONDS
        )
    }

    private fun hmacSha1(secret: String, data: String): String {
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA1"))
        val hash = mac.doFinal(data.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(hash)
    }
}
