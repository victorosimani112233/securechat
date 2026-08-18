package com.securechat.signaling

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.Base64

/**
 * TURN sunucusu icin dinamik HMAC-SHA1 credential uretir (RFC 8489).
 * coturn'de use-auth-secret + static-auth-secret ile uyumlu.
 *
 * username = "{expiry}:{keyed-pseudonym}"
 * password = base64(hmac_sha1(TURN_SECRET, username))
 */
object TurnCredentialService {

    private val turnSecret: String by lazy { SecretSource.required("TURN_SECRET") }
    private val turnHost: String = System.getenv("TURN_HOST") ?: "94.73.180.226"
    private val turnPort: Int = System.getenv("TURN_PORT")?.toIntOrNull() ?: 3478
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
        val ttlSeconds = ServerPrivacy.config.turnCredentialTtlSeconds
        val expiry = (System.currentTimeMillis() / 1000) + ttlSeconds
        val opaqueUser = ServerPrivacy.blindIndex("turn-user", userId)
        val username = "$expiry:$opaqueUser"
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
            ttl = ttlSeconds
        )
    }

    private fun hmacSha1(secret: String, data: String): String {
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA1"))
        val hash = mac.doFinal(data.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(hash)
    }
}
