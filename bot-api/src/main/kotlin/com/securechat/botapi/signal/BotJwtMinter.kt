package com.securechat.botapi.signal

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.securechat.botapi.BotApiConfig
import java.util.Date
import java.util.UUID

/**
 * Signaling-server'in HS256 access token formatini birebir taklit eder.
 * Bot kendi adina (botUserId) JWT mintler ve /api/v1/prekeys/upload + WS
 * baglantisi icin Authorization Bearer header'inda kullanir.
 *
 * GUVENLIK: JWT_SECRET bot-api ve signaling-server arasinda paylasilan secret.
 * Bu nin blast radius'u arttirdigini biliyoruz (Plan.md Karar #1, Option A).
 * v2'de internal HMAC endpoint'e gecilebilir.
 */
object BotJwtMinter {

    private const val ACCESS_TOKEN_TTL_MS = 3600_000L  // 1 saat (signaling-server ile ayni)

    private val algorithm by lazy {
        Algorithm.HMAC256(BotApiConfig.jwtSecret)
    }

    fun issueAccessToken(userId: String): String {
        val now = System.currentTimeMillis()
        return JWT.create()
            .withIssuer("securechat")
            .withSubject(userId)
            .withClaim("typ", "access")
            .withIssuedAt(Date(now))
            .withExpiresAt(Date(now + ACCESS_TOKEN_TTL_MS))
            .withJWTId(UUID.randomUUID().toString())
            .sign(algorithm)
    }
}
