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
 *  2. Sunucu tek-kullanimlik registration grant ile yalniz yeni UUID kaydi
 *     olusturur. Mevcut directory identity icin bu endpoint JWT issue etmez.
 *  3. Client token'i guvenli bicimde saklar (Android Keystore / EncryptedSharedPreferences).
 *  4. Sonraki tum WS ve HTTP cagrilarinda token dogrulanir.
 *
 * Token claims:
 *  - sub: userId (UUID)
 *  - iat: issued at (epoch sec)
 *  - exp: expiry (default 30 gun)
 *  - typ: "access" (gelecekte refresh token icin "refresh" eklenebilir)
 *
 * Algoritma: HS256 (HMAC-SHA256). Secret `JWT_SECRET_FILE` veya geriye uyumlu
 * `JWT_SECRET` girdisinden alinir.
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
        val s = SecretSource.required("JWT_SECRET")
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
        val state = CredentialState.snapshot(userId)
            ?: error("Unknown account cannot receive tokens")
        return issueToken(userId, state.credentialEpoch)
    }

    /**
     * Epoch, token'in icine gomulur. Logout veya hesap silme epoch'u
     * degistirdigi icin daha once verilmis her token dogrulamada duser;
     * bu kontrol PostgreSQL'de kalicidir, Redis kaybindan etkilenmez.
     */
    fun issueToken(userId: String, credentialEpoch: String): String {
        val now = System.currentTimeMillis()
        return JWT.create()
            .withIssuer("securechat")
            .withSubject(userId)
            .withClaim("typ", "access")
            .withClaim("epc", credentialEpoch)
            .withIssuedAt(Date(now))
            .withExpiresAt(Date(now + ACCESS_TOKEN_TTL_MS))
            .withJWTId(java.util.UUID.randomUUID().toString())
            .sign(algorithm)
    }

    /**
     * Refresh token uretir (60 gun TTL). Sadece /auth/refresh icin kullanilir.
     */
    fun issueRefreshToken(userId: String): String {
        val state = CredentialState.snapshot(userId)
            ?: error("Unknown account cannot receive tokens")
        return issueRefreshToken(userId, state.credentialEpoch, state.refreshGeneration)
    }

    /**
     * Refresh token ayrica icinde bulundugu rotasyon kusagini tasir. Yalniz
     * en yeni kusak kabul edilir; supersede edilmis bir token'in yeniden
     * kullanilmasi reuse olarak ele alinir.
     */
    fun issueRefreshToken(
        userId: String,
        credentialEpoch: String,
        refreshGeneration: String,
    ): String {
        val now = System.currentTimeMillis()
        return JWT.create()
            .withIssuer("securechat")
            .withSubject(userId)
            .withClaim("typ", "refresh")
            .withClaim("epc", credentialEpoch)
            .withClaim("rgn", refreshGeneration)
            .withIssuedAt(Date(now))
            .withExpiresAt(Date(now + REFRESH_TOKEN_TTL_MS))
            .withJWTId(java.util.UUID.randomUUID().toString())
            .sign(algorithm)
    }

    /**
     * Registration token — OTP dogrulama sonrasi 15 dk gecerli, sadece /users/register icin.
     */
    fun issueRegistrationToken(): String {
        val now = System.currentTimeMillis()
        return JWT.create()
            .withIssuer("securechat")
            .withSubject("registration-grant")
            .withClaim("typ", "registration")
            .withIssuedAt(Date(now))
            .withExpiresAt(Date(now + REGISTRATION_TOKEN_TTL_MS))
            .withJWTId(java.util.UUID.randomUUID().toString())
            .sign(algorithm)
    }

    /**
     * Registration token is a one-time credential. The Redis NX claim closes
     * parallel replay; a storage outage fails closed instead of allowing an
     * untracked registration.
     */
    class RegistrationGrant(val grantId: String, val expiresAtMs: Long)

    /**
     * Grant'in imza, tip ve suresini dogrular; **tuketmez**.
     *
     * Tuketim hesap kaydiyla ayni transaction'da yapilir
     * (`RegistrationGrants.claimAccount`). Boylece kayit geri alinirsa grant
     * yanmis olmaz, kayit basarili olursa grant kesin olarak yanar ve bu
     * karar Redis kaybindan etkilenmez.
     */
    fun registrationGrantClaim(token: String): RegistrationGrant? {
        return try {
            val decoded = verifier.verify(token)
            if (decoded.getClaim("typ").asString() != "registration" ||
                decoded.subject != "registration-grant"
            ) return null
            val jti = decoded.id ?: return null
            val expiryMs = decoded.expiresAt?.time ?: return null
            if (expiryMs <= System.currentTimeMillis()) return null
            RegistrationGrant(jti, expiryMs)
        } catch (_: JWTVerificationException) {
            null
        }
    }

    /** Verify a refresh token — returns userId if valid, null otherwise. */
    fun verifyRefreshToken(token: String): String? = refreshClaims(token)?.userId

    class RefreshClaims(val userId: String, val refreshGeneration: String)

    /**
     * Refresh token'in imza, tip ve epoch kontrolunu yapar; rotasyon
     * kusagini cagirana verir. Kusagin gecerli olup olmadigi rotasyonun
     * kendisinde atomik olarak sinanir.
     */
    fun refreshClaims(token: String): RefreshClaims? {
        return try {
            val decoded = verifier.verify(token)
            if (decoded.getClaim("typ").asString() != "refresh") return null
            val subject = decoded.subject ?: return null
            val state = CredentialState.cachedSnapshot(subject) ?: return null
            if (decoded.getClaim("epc").asString() != state.credentialEpoch) {
                log.warn("[Auth] Superseded credential epoch reddedildi")
                return null
            }
            val generation = decoded.getClaim("rgn").asString() ?: return null
            RefreshClaims(subject, generation)
        } catch (e: JWTVerificationException) {
            null
        } catch (e: Exception) {
            log.error("[Auth] Credential state okunamadi (fail-closed)")
            null
        }
    }

    /**
     * Hesabin butun access ve refresh token'larini gecersiz kilar.
     *
     * Per-JTI blacklist kaldirildi: o liste yalniz persistence'siz Redis'te
     * yasiyordu ve restart/eviction sonrasi iptal edilmis token yeniden
     * gecerli hale geliyordu. Epoch rotasyonu ayni sonucu PostgreSQL'de
     * kalici olarak verir.
     */
    fun revokeAllTokens(userId: String): Boolean =
        CredentialState.rotateCredentialEpoch(userId) != null

    /**
     * Access token'i dogrular ve userId'yi (sub claim) doner.
     * Hatali/expired/revoked token icin null doner.
     *
     * GUVENLIK (H4 fix): typ claim'i ZORUNLU olarak "access" olmali.
     * Eski legacy "null typ" kabulu kaldirildi — refresh token'in access olarak
     * kullanilmasini engeller. Eski APK'lar /auth/refresh ile yeni token alir.
     */
    fun verifyToken(token: String): String? {
        return try {
            val decoded = verifier.verify(token)
            // ZORUNLU: typ claim'i "access" olmali. null, "refresh", "registration" REDDEDILIR.
            val typ = decoded.getClaim("typ").asString()
            if (typ != "access") {
                log.warn("[Auth] verifyToken redd: gecersiz token tipi")
                return null
            }
            val subject = decoded.subject ?: return null
            // Durable kontrol: hesap silinmisse satir yoktur, logout sonrasi
            // epoch degismistir. Ikisi de Redis kaybindan etkilenmez.
            val state = CredentialState.cachedSnapshot(subject) ?: return null
            if (decoded.getClaim("epc").asString() != state.credentialEpoch) {
                log.warn("[Auth] Superseded credential epoch reddedildi")
                return null
            }
            subject
        } catch (e: JWTVerificationException) {
            null
        } catch (e: Exception) {
            // Credential state okunamiyorsa authentication fail-closed olur.
            log.error("[Auth] Credential state okunamadi (fail-closed)")
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

    /**
     * Hesap silindiginde ayrica bir "revoked" kaydi tutulmaz: `users` satiri
     * yoksa hicbir token dogrulanamaz. Bu isaret PostgreSQL'de kalicidir ve
     * yeniden baslatmayla geri gelmez.
     */
    fun forgetAccount(userId: String) {
        CredentialState.forget(userId)
    }

    /** AuthService'i baslangicta zorla — secret yoksa fail-fast. */
    fun initialize() {
        secret // lazy init tetikler
        log.info("[Auth] JWT auth service hazir (HS256, TTL=30 gun)")
    }
}
