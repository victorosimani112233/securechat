package com.securechat.signaling

import com.auth0.jwt.JWT
import com.auth0.jwt.JWTVerifier
import com.auth0.jwt.algorithms.Algorithm
import com.auth0.jwt.exceptions.JWTVerificationException
import org.slf4j.LoggerFactory
import java.util.Date
import java.util.concurrent.TimeUnit

private val log = LoggerFactory.getLogger("AuthService")

/**
 * JWT tabanli kimlik dogrulama servisi.
 *
 * Token akisi:
 *  1. Client `/api/v1/users/register` ile kayit olur.
 *  2. Sunucu phoneHash + userId dogrulamasini yaptiktan sonra JWT issue eder.
 *  3. Client token'i guvenli bicimde saklar (Android Keystore / EncryptedSharedPreferences).
 *  4. Sonraki tum WS ve HTTP cagrilarinda token dogrulanir.
 *
 * Token claims:
 *  - sub: userId (UUID)
 *  - iat: issued at (epoch sec)
 *  - exp: expiry (default 30 gun)
 *  - typ: "access" (gelecekte refresh token icin "refresh" eklenebilir)
 *
 * Algoritma: HS256 (HMAC-SHA256). Secret env'den (`JWT_SECRET`).
 */
object AuthService {

    /** Access token gecerlilik suresi — 1 saat (refresh ile yenilenir) */
    private val ACCESS_TOKEN_TTL_MS = TimeUnit.HOURS.toMillis(1)
    /** Refresh token gecerlilik suresi — 60 gun */
    private val REFRESH_TOKEN_TTL_MS = TimeUnit.DAYS.toMillis(60)
    /** Registration token (OTP sonrasi) — 15 dk */
    private val REGISTRATION_TOKEN_TTL_MS = TimeUnit.MINUTES.toMillis(15)
    // Geriye uyumluluk icin eski isim
    private val TOKEN_TTL_MS = ACCESS_TOKEN_TTL_MS

    private val secret: String by lazy {
        val s = System.getenv("JWT_SECRET")
        if (s.isNullOrBlank()) {
            log.error("FATAL: JWT_SECRET env variable bos!")
            throw IllegalStateException("JWT_SECRET zorunludur (en az 32 karakter)")
        }
        if (s.length < 32) {
            log.warn("UYARI: JWT_SECRET kisa (${s.length} char). En az 32 karakter onerilir.")
        }
        s
    }

    private val algorithm: Algorithm by lazy { Algorithm.HMAC256(secret) }

    private val verifier: JWTVerifier by lazy {
        JWT.require(algorithm)
            .withIssuer("securechat")
            .build()
    }

    /**
     * Kullanici icin yeni access token uretir (1 saat TTL).
     */
    fun issueToken(userId: String): String {
        val now = System.currentTimeMillis()
        return JWT.create()
            .withIssuer("securechat")
            .withSubject(userId)
            .withClaim("typ", "access")
            .withIssuedAt(Date(now))
            .withExpiresAt(Date(now + ACCESS_TOKEN_TTL_MS))
            .withJWTId(java.util.UUID.randomUUID().toString())
            .sign(algorithm)
    }

    /**
     * Refresh token uretir (60 gun TTL). Sadece /auth/refresh icin kullanilir.
     */
    fun issueRefreshToken(userId: String): String {
        val now = System.currentTimeMillis()
        return JWT.create()
            .withIssuer("securechat")
            .withSubject(userId)
            .withClaim("typ", "refresh")
            .withIssuedAt(Date(now))
            .withExpiresAt(Date(now + REFRESH_TOKEN_TTL_MS))
            .withJWTId(java.util.UUID.randomUUID().toString())
            .sign(algorithm)
    }

    /**
     * Registration token — OTP dogrulama sonrasi 15 dk gecerli, sadece /users/register icin.
     */
    fun issueRegistrationToken(email: String): String {
        val now = System.currentTimeMillis()
        return JWT.create()
            .withIssuer("securechat")
            .withSubject(email.lowercase())
            .withClaim("typ", "registration")
            .withIssuedAt(Date(now))
            .withExpiresAt(Date(now + REGISTRATION_TOKEN_TTL_MS))
            .withJWTId(java.util.UUID.randomUUID().toString())
            .sign(algorithm)
    }

    /** Verify a registration token — returns email if valid, null otherwise. */
    fun verifyRegistrationToken(token: String): String? {
        return try {
            val decoded = verifier.verify(token)
            if (decoded.getClaim("typ").asString() != "registration") return null
            decoded.subject
        } catch (e: JWTVerificationException) { null }
    }

    /** Verify a refresh token — returns userId if valid, null otherwise. */
    fun verifyRefreshToken(token: String): String? {
        return try {
            val decoded = verifier.verify(token)
            if (decoded.getClaim("typ").asString() != "refresh") return null
            // Blacklist kontrolu
            val jti = decoded.id
            if (jti != null && JwtBlacklist.isRevoked(jti)) {
                log.warn("[Auth] Revoked refresh token kullanildi: jti={}", jti)
                return null
            }
            decoded.subject
        } catch (e: JWTVerificationException) { null }
    }

    /** Token JTI'sini blacklist'e ekler — exp'e kadar gecersiz. */
    fun revokeToken(token: String) {
        try {
            val decoded = verifier.verify(token)
            val jti = decoded.id ?: return
            val expiry = decoded.expiresAt?.time ?: return
            JwtBlacklist.revoke(jti, expiry)
        } catch (_: JWTVerificationException) {
            // Zaten gecersiz token, blacklist'e ekleme gereksiz
        }
    }

    /**
     * Access token'i dogrular ve userId'yi (sub claim) doner.
     * Hatali/expired/revoked token icin null doner.
     */
    fun verifyToken(token: String): String? {
        return try {
            val decoded = verifier.verify(token)
            // Sadece access token'lar bu fonksiyonla dogrulanir
            val typ = decoded.getClaim("typ").asString()
            if (typ != "access" && typ != null) return null
            // Blacklist kontrolu
            val jti = decoded.id
            if (jti != null && JwtBlacklist.isRevoked(jti)) {
                log.warn("[Auth] Revoked access token kullanildi: jti={}", jti)
                return null
            }
            decoded.subject
        } catch (e: JWTVerificationException) {
            null
        }
    }

    /**
     * Token'in userId ile eslestigini dogrular.
     * `userId` parametresi taklit edilemesin diye token'in `sub` claim'i ile eslesmeli.
     */
    fun verifyTokenForUser(token: String, claimedUserId: String): Boolean {
        val sub = verifyToken(token) ?: return false
        return sub == claimedUserId
    }

    /** AuthService'i baslangicta zorla — secret yoksa fail-fast. */
    fun initialize() {
        secret // lazy init tetikler
        log.info("[Auth] JWT auth service hazir (HS256, TTL=30 gun)")
    }
}
