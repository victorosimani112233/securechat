package com.securechat.signaling

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.plugins.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import io.ktor.utils.io.core.readBytes
import io.ktor.utils.io.readRemaining
import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("HttpRoutes")
private val strictPrivateDirectoryJson = Json { ignoreUnknownKeys = false }
private const val DIRECTORY_EVALUATE_BODY_LIMIT = 160 * 1024
private const val DIRECTORY_SELF_UPDATE_BODY_LIMIT = 2 * 1024

/**
 * Kucuk JSON govdeleri icin ust sinir.
 *
 * Onceki akista OTP, kayit, refresh ve FCM route'lari `call.receive()` ile
 * sinirsiz govde okuyordu: tek bir istek istedigi kadar bellek tuketebilirdi.
 */
private const val SMALL_BODY_LIMIT = 8 * 1024

/**
 * Prekey bundle govdesi. 100 one-time prekey * ~44 byte base64 + identity ve
 * signed prekey alanlari rahatlikla sigar; bunun otesi protokol disidir.
 */
private const val PREKEY_BODY_LIMIT = 64 * 1024

/** Tek yuklemede kabul edilen en fazla one-time prekey sayisi. */
private const val MAX_ONE_TIME_PREKEYS = 200

/** Curve25519 public key 33, imza 64 byte; ust sinir bunun uzerinde tutuldu. */
private const val MAX_KEY_MATERIAL_BYTES = 128

/** Server baslangic zamani — uptime hesabi icin */
private val serverStartTime = System.currentTimeMillis()

@Serializable
data class DirectoryConfigResponse(
    val version: String,
    val keyId: String,
    val modulus: String,
    val exponent: String,
    val batchSize: Int,
)

@Serializable
data class DirectoryEvaluateRequest(val keyId: String, val blinded: List<String>)

@Serializable
data class DirectoryEvaluateResponse(val keyId: String, val evaluated: List<String>)

@Serializable
data class DirectorySnapshotEntryResponse(val label: String, val sealedUserId: String)

@Serializable
data class DirectorySnapshotResponse(
    val keyId: String,
    val entries: List<DirectorySnapshotEntryResponse>,
)

@Serializable
data class OwnDirectoryUpdateRequest(val phoneHash: String)

@Serializable
data class RegisterRequest(
    val userId: String,
    val phoneHash: String,
    /** OTP dogrulama sonrasi alinan kisa omurlu registration token. */
    val registrationToken: String? = null
)

@Serializable
data class RegisterResponse(
    val userId: String,
    val isNew: Boolean,
    val accessToken: String,
    val refreshToken: String
)

@Serializable
data class OtpRequestBody(val email: String)

@Serializable
data class OtpRequestResponse(val sent: Boolean, val message: String)

@Serializable
data class OtpVerifyBody(val email: String, val otp: String)

@Serializable
data class OtpVerifyResponse(val verified: Boolean, val registrationToken: String? = null)

@Serializable
data class RefreshTokenRequest(val refreshToken: String)

@Serializable
data class RefreshTokenResponse(val accessToken: String, val refreshToken: String)

// PreKey bundle — Signal Protocol
@Serializable
data class PreKeyUploadRequest(
    val identityPublicKey: String, // base64
    val registrationId: Int,
    val signedPreKeyId: Int,
    val signedPreKey: String,       // base64
    val signedPreKeySignature: String, // base64
    val oneTimePreKeys: List<PreKeyEntry>
)

@Serializable
data class PreKeyEntry(val keyId: Int, val publicKey: String) // publicKey base64

/**
 * Prekey yuklemesinin alan bazinda makul olup olmadigi.
 *
 * Onceki akista one-time prekey sayisi ve anahtar boyutlari sinirsizdi;
 * tek bir istek binlerce satir veya cok buyuk alanlar yazdirabiliyordu.
 */
private fun PreKeyUploadRequest.hasSaneKeyMaterial(): Boolean {
    fun decoded(value: String): Int? = try {
        java.util.Base64.getDecoder().decode(value).size
    } catch (_: Exception) {
        null
    }
    if (registrationId !in 1..16_383) return false
    if (signedPreKeyId !in 0..0xFFFFFF) return false
    if (oneTimePreKeys.size > MAX_ONE_TIME_PREKEYS) return false
    if (oneTimePreKeys.distinctBy { it.keyId }.size != oneTimePreKeys.size) return false
    val identityBytes = decoded(identityPublicKey) ?: return false
    if (identityBytes !in 1..MAX_KEY_MATERIAL_BYTES) return false
    val signedBytes = decoded(signedPreKey) ?: return false
    if (signedBytes !in 1..MAX_KEY_MATERIAL_BYTES) return false
    val signatureBytes = decoded(signedPreKeySignature) ?: return false
    if (signatureBytes !in 1..MAX_KEY_MATERIAL_BYTES) return false
    return oneTimePreKeys.all { entry ->
        entry.keyId in 0..0xFFFFFF &&
            (decoded(entry.publicKey) ?: 0) in 1..MAX_KEY_MATERIAL_BYTES
    }
}

@Serializable
data class PreKeyBundleResponse(
    val userId: String,
    val identityPublicKey: String,
    val registrationId: Int,
    val signedPreKeyId: Int,
    val signedPreKey: String,
    val signedPreKeySignature: String,
    val oneTimePreKey: PreKeyEntry? = null
)

@Serializable
data class StatusResponse(
    val status: String
)

@Serializable
data class FcmRegisterRequest(val userId: String, val fcmToken: String)

@Serializable
data class FcmUnregisterRequest(val userId: String)

@Serializable
data class IceServerResponse(
    val urls: String,
    val username: String? = null,
    val credential: String? = null
)

@Serializable
data class IceConfigResponse(
    val iceServers: List<IceServerResponse>,
    val ttl: Long
)

@Serializable
data class HealthResponse(
    val status: String,
    val database: String,
    val redis: String,
    val privacy: String,
    val janus: String = "disabled",
    val fcm: String = "disabled",
    val uptime_sec: Long = 0
)

fun Application.configureRoutes(
    connectionManager: ConnectionManager,
    userRegistry: UserRegistry,
    fcmTokenStore: FcmTokenStore? = null
) {
    routing {
        intercept(ApplicationCallPipeline.Plugins) {
            if (!PrivacyRetentionWorker.isHealthy() && call.request.path() != "/health") {
                call.respond(
                    HttpStatusCode.ServiceUnavailable,
                    mapOf("error" to "privacy_retention_unavailable")
                )
                finish()
            }
        }

        // Sunucu durumu
        get("/") {
            call.respond(
                StatusResponse(status = "ok")
            )
        }

        // Aggregate operational metrics still reveal activity/timing and are
        // therefore authenticated even on an internal network.
        get("/metrics") {
            if (!MetricsAccess.isAuthorized(call.request.headers["Authorization"])) {
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "unauthorized"))
                return@get
            }
            call.respondText(
                Metrics.registry.scrape(),
                io.ktor.http.ContentType.parse("text/plain; version=0.0.4; charset=utf-8")
            )
        }

        // Health check — kritik bagimliliklar (DB + Redis); Janus ve FCM opsiyonel
        get("/health") {
            val dbOk = Database.isHealthy()
            val redisOk = RedisManager.isHealthy()
            val privacyOk = PrivacyRetentionWorker.isHealthy()
            val criticalOk = dbOk && redisOk && privacyOk
            val janusEnabled = !System.getenv("JANUS_WS_URL").isNullOrBlank()
            val fcmEnabled = !System.getenv("FIREBASE_SERVICE_ACCOUNT_PATH").isNullOrBlank()
            call.respond(
                if (criticalOk) HttpStatusCode.OK else HttpStatusCode.ServiceUnavailable,
                HealthResponse(
                    status = if (criticalOk) "ok" else "degraded",
                    database = if (dbOk) "ok" else "fail",
                    redis = if (redisOk) "ok" else "fail",
                    privacy = if (privacyOk) "ok" else "fail",
                    janus = if (janusEnabled) "enabled" else "disabled",
                    fcm = if (fcmEnabled) "enabled" else "disabled",
                    uptime_sec = (System.currentTimeMillis() - serverStartTime) / 1000
                )
            )
        }

        // Calisan artefaktin kimligi — operator'a ozel. Canli ucun hangi
        // commit ve hangi migration hedefiyle calistigi deploy kaydiyla
        // burada karsilastirilir. Secret icermez, fakat anonim istemciye
        // acilmaz: tam commit saldirgana kaynak esleme kolayligi verir.
        get("/api/v1/version") {
            if (!MetricsAccess.isAuthorized(call.request.headers["Authorization"])) {
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "unauthorized"))
                return@get
            }
            call.respond(BuildManifest.asMap())
        }

        // Mevcut prod APK versiyon bilgisi — client "guncelleme var mi" kontrolu icin.
        // Default'lar boş (env yoksa "guncel" yaniti) — server admin LATEST_APK_VERSION_CODE
        // ve LATEST_APK_VERSION_NAME env'lerini set ederek production'da gercek deger doner.
        // Manuel APK dagitimi icin Settings > Hakkinda ekraninda "Guncelleme var" rozeti
        // bu endpoint'e bakar.
        get("/api/v1/latest-version") {
            val versionCode = System.getenv("LATEST_APK_VERSION_CODE")?.toIntOrNull()
            val versionName = System.getenv("LATEST_APK_VERSION_NAME") ?: ""
            val downloadUrl = System.getenv("LATEST_APK_DOWNLOAD_URL") ?: ""
            call.respond(
                mapOf(
                    "versionCode" to (versionCode ?: 0),
                    "versionName" to versionName,
                    "downloadUrl" to downloadUrl,
                    "mandatory" to (System.getenv("LATEST_APK_MANDATORY") == "true")
                )
            )
        }

        // Private directory public key contains no secret and is pinned by
        // HTTPS. Address-book inputs are never accepted by this endpoint.
        get("/api/v1/directory/config") {
            val config = PrivateDirectory.oprf.publicConfig()
            call.respond(
                DirectoryConfigResponse(
                    version = config.version,
                    keyId = config.keyId,
                    modulus = config.modulus,
                    exponent = config.exponent,
                    batchSize = config.batchSize,
                ),
            )
        }

        // Fixed-size blind-RSA OPRF evaluation. The server sees 256 random
        // group elements regardless of the real contact count in this batch.
        post("/api/v1/directory/evaluate") {
            val authedUserId = requireAuth(call) ?: return@post
            if (!RateLimiter.allow("directory_evaluate", authedUserId)) {
                val retry = RateLimiter.retryAfter("directory_evaluate", authedUserId)
                call.response.header("Retry-After", retry.toString())
                call.respond(
                    HttpStatusCode.TooManyRequests,
                    mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()),
                )
                return@post
            }
            val request = call.receivePrivateDirectoryJson<DirectoryEvaluateRequest>(
                DIRECTORY_EVALUATE_BODY_LIMIT,
            ) ?: return@post
            if (request.keyId != PrivateDirectory.oprf.keyId) {
                call.respond(HttpStatusCode.Conflict, mapOf("error" to "directory_key_changed"))
                return@post
            }
            val evaluated = try {
                PrivateDirectory.oprf.evaluateBatch(request.blinded)
            } catch (_: IllegalArgumentException) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_directory_batch"))
                return@post
            }
            call.respond(DirectoryEvaluateResponse(request.keyId, evaluated))
        }

        // Every account receives the same opaque snapshot. Labels and user IDs
        // are independently protected by each OPRF token; only a client that
        // evaluated a matching phone can locate and open that entry.
        get("/api/v1/directory/snapshot") {
            val authedUserId = requireAuth(call) ?: return@get
            if (!RateLimiter.allow("directory_snapshot", authedUserId)) {
                val retry = RateLimiter.retryAfter("directory_snapshot", authedUserId)
                call.response.header("Retry-After", retry.toString())
                call.respond(
                    HttpStatusCode.TooManyRequests,
                    mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()),
                )
                return@get
            }
            val entries = userRegistry.privateDirectorySnapshot().map { user ->
                val sealed = PrivateDirectory.oprf.sealUserId(
                    user.directoryToken,
                    user.userId,
                )
                DirectorySnapshotEntryResponse(sealed.label, sealed.sealedUserId)
            }
            call.respond(DirectorySnapshotResponse(PrivateDirectory.oprf.keyId, entries))
        }

        // Upgrade path for an already authenticated device. Only the account's
        // own declared phone hash is transiently processed; it is never logged,
        // cached or persisted and cannot expose the device address book.
        post("/api/v1/users/directory-token") {
            val authedUserId = requireAuth(call) ?: return@post
            if (!RateLimiter.allow("directory_self_update", authedUserId)) {
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi"))
                return@post
            }
            val request = call.receivePrivateDirectoryJson<OwnDirectoryUpdateRequest>(
                DIRECTORY_SELF_UPDATE_BODY_LIMIT,
            ) ?: return@post
            val updated = try {
                userRegistry.updateOwnDirectoryToken(authedUserId, request.phoneHash)
            } catch (_: IllegalArgumentException) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_phone_hash"))
                return@post
            }
            call.respond(mapOf("status" to "ok", "keyId" to updated.directoryKeyId))
        }

        // ========================================================
        // OTP — E-posta tabanli kayit dogrulamasi
        // ========================================================

        // OTP kodu iste — e-posta ile gonderilir
        post("/api/v1/otp/request") {
            val ip = call.clientAddress()
            if (!RateLimiter.allow("otp_request", ip)) {
                call.response.header("Retry-After", RateLimiter.retryAfter("otp_request", ip).toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Cok fazla istek"))
                return@post
            }
            val body = call.receiveBounded<OtpRequestBody>(SMALL_BODY_LIMIT) ?: return@post
            val email = body.email.trim().lowercase()
            // E-posta format kontrolu
            if (!email.matches(Regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"))) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz e-posta"))
                return@post
            }
            // Cooldown kontrolu OTP uretimiyle ayni atomik adimdadir; ayri bir
            // okuma iki paralel istegin ayni "gecti" sonucunu paylasmasina
            // izin veriyordu.
            val otp = try {
                OtpService.generateOtp(email)
            } catch (e: OtpService.OtpCooldownException) {
                val wait = (e.remainingMillis + 999) / 1000
                call.respond(
                    HttpStatusCode.TooManyRequests,
                    mapOf("error" to "Lutfen bekleyin", "retryAfter" to wait.toString()),
                )
                return@post
            } catch (e: Exception) {
                logger.error("[OTP] Generate hatasi: {}", e.javaClass.simpleName)
                call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "OTP olusturulamadi"))
                return@post
            }

            // E-postayi async gonder (response'u bekletme)
            val sent = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                EmailService.sendMail(
                    to = email,
                    subject = "SecureChat — Doğrulama Kodu",
                    htmlBody = """
                        <html><body style="font-family:Arial,sans-serif">
                          <h2 style="color:#1a73e8">SecureChat Doğrulama</h2>
                          <p>Hesabınızı doğrulamak için aşağıdaki kodu kullanın:</p>
                          <h1 style="font-size:32px;letter-spacing:4px;color:#1a73e8">$otp</h1>
                          <p style="color:#666;font-size:13px">Bu kod 10 dakika içinde sona erer. Bu isteği siz yapmadıysanız bu e-postayı görmezden gelin.</p>
                        </body></html>
                    """.trimIndent(),
                    textBody = "SecureChat doğrulama kodunuz: $otp\n\nBu kod 10 dakika içinde sona erer."
                )
            }
            AuditLog.log(eventType = "OTP_REQUESTED", ipAddress = ip)
            if (sent) {
                call.respond(OtpRequestResponse(true, "OTP gonderildi"))
            } else {
                call.respond(HttpStatusCode.ServiceUnavailable,
                    OtpRequestResponse(false, "E-posta gonderilemedi"))
            }
        }

        // OTP dogrula — basariliysa kisa omurlu registration token doner
        post("/api/v1/otp/verify") {
            val ip = call.clientAddress()
            if (!RateLimiter.allow("otp_verify", ip)) {
                call.response.header("Retry-After", RateLimiter.retryAfter("otp_verify", ip).toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Cok fazla istek"))
                return@post
            }
            val body = call.receiveBounded<OtpVerifyBody>(SMALL_BODY_LIMIT) ?: return@post
            val email = body.email.trim().lowercase()
            val ok = OtpService.verifyOtp(email, body.otp.trim())
            if (!ok) {
                AuditLog.log(eventType = "OTP_VERIFY_FAILED", ipAddress = ip)
                call.respond(HttpStatusCode.Unauthorized, OtpVerifyResponse(false))
                return@post
            }
            val regToken = AuthService.issueRegistrationToken()
            AuditLog.log(eventType = "OTP_VERIFIED", ipAddress = ip)
            call.respond(OtpVerifyResponse(true, regToken))
        }

        // Kullanici kaydi — rate limited + OTP registration token gerekli
        post("/api/v1/users/register") {
            val ip = call.clientAddress()
            if (!RateLimiter.allow("users_register", ip)) {
                val retry = RateLimiter.retryAfter("users_register", ip)
                AuditLog.log(eventType = "RATE_LIMIT_HIT", metadata = mapOf("endpoint" to "users_register"), ipAddress = ip)
                call.response.header("Retry-After", retry.toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()))
                return@post
            }
            val request = call.receiveBounded<RegisterRequest>(SMALL_BODY_LIMIT) ?: return@post

            // OTP registration token is mandatory and single-use in every
            // environment. Test behavior belongs in test source sets, not a
            // production runtime switch.
            val regToken = request.registrationToken
            if (regToken.isNullOrBlank()) {
                call.respond(HttpStatusCode.Forbidden,
                    mapOf("error" to "registrationToken gerekli (once /otp/verify cagirin)"))
                return@post
            }
            val grant = AuthService.registrationGrantClaim(regToken)
            if (grant == null) {
                AuditLog.log(eventType = "REGISTER_INVALID_TOKEN", ipAddress = ip)
                call.respond(HttpStatusCode.Forbidden,
                    mapOf("error" to "Gecersiz, kullanilmis veya expired registration token"))
                return@post
            }

            val user = try {
                // Grant tuketimi ile hesap kaydi tek transaction'dadir: kayit
                // geri alinirsa grant yanmaz, kayit basarili olursa grant
                // kalici olarak tukenmis sayilir.
                val candidate = userRegistry.prepareRegistration(request.userId, request.phoneHash)
                RegistrationGrants.claimAccount(grant, candidate, userRegistry)
                    ?: run {
                        AuditLog.log(eventType = "REGISTER_GRANT_REPLAY", ipAddress = ip)
                        call.respond(
                            HttpStatusCode.Forbidden,
                            mapOf("error" to "Gecersiz, kullanilmis veya expired registration token"),
                        )
                        return@post
                    }
            } catch (_: DirectoryIdentityAlreadyRegisteredException) {
                // Never return the existing UUID or issue credentials: the
                // e-mail OTP does not prove ownership of the claimed phone.
                call.respond(
                    HttpStatusCode.Conflict,
                    mapOf("error" to "directory_identity_already_registered"),
                )
                return@post
            } catch (_: IllegalArgumentException) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_registration"))
                return@post
            }
            AuditLog.log(userId = user.userId, eventType = "USER_REGISTERED", ipAddress = ip)
            val accessToken = AuthService.issueToken(user.userId)
            val refreshToken = AuthService.issueRefreshToken(user.userId)
            call.respond(RegisterResponse(user.userId, true, accessToken, refreshToken))
        }

        // Logout — access token blacklist'e alinir (revocation)
        // Body'de opsiyonel refresh token da revoke edilir.
        post("/api/v1/auth/logout") {
            val authHeader = call.request.headers["Authorization"]
            val accessToken = authHeader?.removePrefix("Bearer ")?.trim()
            val authedUserId = AuthService.verifyToken(accessToken ?: "")
            if (authedUserId == null) {
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz token"))
                return@post
            }
            val ip = call.clientAddress()
            // Tek adimda hesabin butun access/refresh token'lari gecersizlesir.
            // Kayit PostgreSQL'de oldugu icin Redis restart'i veya eviction'i
            // iptal edilmis bir token'i geri getiremez.
            if (!AuthService.revokeAllTokens(authedUserId)) {
                AuditLog.log(eventType = "USER_LOGOUT_FAILED", ipAddress = ip)
                call.respond(
                    HttpStatusCode.ServiceUnavailable,
                    mapOf("error" to "logout_unavailable"),
                )
                return@post
            }
            AuditLog.log(userId = authedUserId, eventType = "USER_LOGOUT", ipAddress = ip)
            fcmTokenStore?.removeToken(authedUserId)
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }

        // Hesap silme — idempotent; kalici kayit tek transaction'da gider,
        // gecici kopyalar yalitilmis adimlarla temizlenir.
        post("/api/v1/account/delete") {
            val authedUserId = requireAuth(call) ?: return@post
            val ip = call.clientAddress()
            try {
                val result = AccountDeletion.execute(
                    userId = authedUserId,
                    connectionManager = connectionManager,
                    userRegistry = userRegistry,
                    fcmTokenStore = fcmTokenStore,
                )
                // Deletion audit is intentionally unlinkable to the deleted UUID.
                AuditLog.log(eventType = "ACCOUNT_DELETED", ipAddress = ip)
                if (result.residualSteps.isNotEmpty()) {
                    AuditLog.log(eventType = "ACCOUNT_DELETE_RESIDUAL", ipAddress = ip)
                }
                logger.info("[ACCOUNT] Hesap silme tamamlandi: {}", result.outcome)
                // Kalici kayit gittigi anda hesap authenticate edilemez.
                // Tekrarlanan istek de basarilidir; istemci yeniden deneyebilir.
                call.respond(
                    HttpStatusCode.OK,
                    mapOf(
                        "status" to "deleted",
                        "alreadyAbsent" to
                            (result.outcome == AccountDeletion.Outcome.ALREADY_ABSENT).toString(),
                    ),
                )
            } catch (e: Exception) {
                // Kalici silme basarisiz: istemci lokal hesabini silmemeli.
                logger.warn("[!] Hesap silme hatasi: {}", e.javaClass.simpleName)
                AuditLog.log(eventType = "ACCOUNT_DELETE_FAILED", ipAddress = ip)
                call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Silme basarisiz"))
            }
        }

        // Token yenileme — refresh token ile yeni access + refresh ciftti uretir
        // (token rotation: eski refresh token blacklist'e alinir)
        post("/api/v1/auth/refresh") {
            val ip = call.clientAddress()
            val body = call.receiveBounded<RefreshTokenRequest>(SMALL_BODY_LIMIT) ?: return@post
            val claims = AuthService.refreshClaims(body.refreshToken)
            if (claims == null) {
                AuditLog.log(eventType = "AUTH_REFRESH_INVALID", ipAddress = ip)
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz refresh token"))
                return@post
            }
            // Rotasyon tek atomik compare-and-set'tir: ayni eski token ile
            // paralel iki istek gelirse yalniz biri yeni kusak uretebilir.
            // Supersede edilmis bir token'in yeniden kullanilmasi burada
            // fail-closed olur.
            val rotated = try {
                CredentialState.rotateRefreshGeneration(
                    claims.userId,
                    claims.refreshGeneration,
                )
            } catch (_: Exception) {
                null
            }
            if (rotated == null) {
                AuditLog.log(eventType = "AUTH_REFRESH_REUSE", ipAddress = ip)
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz refresh token"))
                return@post
            }
            val newAccess = AuthService.issueToken(claims.userId, rotated.credentialEpoch)
            val newRefresh = AuthService.issueRefreshToken(
                claims.userId,
                rotated.credentialEpoch,
                rotated.refreshGeneration,
            )
            AuditLog.log(userId = claims.userId, eventType = "AUTH_TOKEN_REFRESHED", ipAddress = ip)
            call.respond(RefreshTokenResponse(newAccess, newRefresh))
        }

        // --- Dinamik TURN Credential — AUTH GEREKLI ---
        get("/api/v1/ice/config") {
            val authedUserId = requireAuth(call) ?: return@get
            if (!RateLimiter.allow("ice_config", authedUserId)) {
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi"))
                return@get
            }
            val config = TurnCredentialService.generateConfig(authedUserId)
            AuditLog.log(userId = authedUserId, eventType = "TURN_CREDENTIAL_ISSUED")
            call.respond(IceConfigResponse(
                iceServers = config.iceServers.map { IceServerResponse(it.urls, it.username, it.credential) },
                ttl = config.ttl
            ))
        }

        // ========================================================
        // Signal Protocol PreKey Bundle endpoint'leri — AUTH GEREKLI
        // ========================================================

        // Client kayit sonrasi identity_key + signed_prekey + one_time_prekeys upload eder
        post("/api/v1/prekeys/upload") {
            val authedUserId = requirePrincipal(
                call,
                serviceScope = ServiceAssertion.Scope.PREKEY_UPLOAD,
            ) ?: return@post
            val req = call.receiveBounded<PreKeyUploadRequest>(PREKEY_BODY_LIMIT) ?: return@post
            val decoder = java.util.Base64.getDecoder()
            // Alan bazinda sinirlar: govde limiti tek basina yetmez, cunku
            // az sayida ama cok buyuk alan da kabul edilirdi.
            if (!req.hasSaneKeyMaterial()) {
                AuditLog.log(eventType = "PREKEY_UPLOAD_REJECTED", ipAddress = call.clientAddress())
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_prekey_material"))
                return@post
            }
            try {
                // Identity, signed prekey ve one-time prekey'ler tek
                // transaction'da yazilir; yarim bir bundle olusamaz.
                PreKeyStore.uploadBundle(
                    userId = authedUserId,
                    identityPublicKey = decoder.decode(req.identityPublicKey),
                    registrationId = req.registrationId,
                    signedPreKey = PreKeyStore.SignedPreKey(
                        req.signedPreKeyId,
                        decoder.decode(req.signedPreKey),
                        decoder.decode(req.signedPreKeySignature)
                    ),
                    oneTimePreKeys = req.oneTimePreKeys.map {
                        PreKeyStore.OneTimePreKey(it.keyId, decoder.decode(it.publicKey))
                    },
                )
                call.respond(HttpStatusCode.OK, mapOf("status" to "ok",
                    "remaining" to PreKeyStore.unconsumedCount(authedUserId).toString()))
            } catch (e: Exception) {
                logger.warn("[PreKey] Upload hatasi: {}", e.javaClass.simpleName)
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz prekey verisi"))
            }
        }

        // One-time prekey havuzunu yenile (rotation)
        post("/api/v1/prekeys/refresh") {
            val authedUserId = requireAuth(call) ?: return@post
            val keys = call.receiveBounded<List<PreKeyEntry>>(PREKEY_BODY_LIMIT) ?: return@post
            val decoder = java.util.Base64.getDecoder()
            try {
                PreKeyStore.addOneTimePreKeys(
                    authedUserId,
                    keys.map { PreKeyStore.OneTimePreKey(it.keyId, decoder.decode(it.publicKey)) }
                )
                call.respond(HttpStatusCode.OK, mapOf("status" to "ok",
                    "remaining" to PreKeyStore.unconsumedCount(authedUserId).toString()))
            } catch (e: Exception) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz prekey"))
            }
        }

        // Diger client baska bir kullanicinin prekey bundle'ini ister
        get("/api/v1/users/{userId}/prekeys") {
            requirePrincipal(
                call,
                serviceScope = ServiceAssertion.Scope.PREKEY_FETCH,
            ) ?: return@get
            val targetUserId = call.parameters["userId"] ?: run {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "userId gerekli"))
                return@get
            }
            val bundle = PreKeyStore.fetchBundle(targetUserId)
            if (bundle == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Bundle bulunamadi (kullanici prekey upload etmemis olabilir)"))
                return@get
            }
            val encoder = java.util.Base64.getEncoder()
            call.respond(PreKeyBundleResponse(
                userId = targetUserId,
                identityPublicKey = encoder.encodeToString(bundle.identityKey.publicKey),
                registrationId = bundle.identityKey.registrationId,
                signedPreKeyId = bundle.signedPreKey.keyId,
                signedPreKey = encoder.encodeToString(bundle.signedPreKey.publicKey),
                signedPreKeySignature = encoder.encodeToString(bundle.signedPreKey.signature),
                oneTimePreKey = bundle.oneTimePreKey?.let {
                    PreKeyEntry(it.keyId, encoder.encodeToString(it.publicKey))
                }
            ))
        }

        // --- SFU Room Bilgisi — AUTH GEREKLI ---
        get("/api/v1/sfu/room/{groupId}") {
            requireAuth(call) ?: return@get
            val groupId = call.parameters["groupId"] ?: run {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "groupId gerekli"))
                return@get
            }
            val info = JanusOrchestrator.getRoomInfo(groupId)
            if (info == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Aktif SFU room bulunamadi"))
            } else {
                call.respond(mapOf(
                    "roomId" to info.roomId,
                    "janusWsUrl" to info.janusWsUrl,
                    "status" to "active"
                ))
            }
        }

        // --- FCM Token Yonetimi — AUTH GEREKLI ---
        // GUVENLIK: Body'deki userId DEGIL, token'in sub claim'i kullanilir.
        // Yoksa saldirgan baska userId gonderip kurbanin token'ini silebilir.
        post("/api/v1/fcm/register") {
            val authedUserId = requireAuth(call) ?: return@post
            if (fcmTokenStore == null) {
                call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "FCM devre disi"))
                return@post
            }
            val request = call.receiveBounded<FcmRegisterRequest>(SMALL_BODY_LIMIT) ?: return@post
            // userId mutlaka token'in sub'i ile eslesmeli
            if (request.userId != authedUserId) {
                call.respond(HttpStatusCode.Forbidden, mapOf("error" to "userId token ile eslesmiyor"))
                return@post
            }
            fcmTokenStore.registerToken(authedUserId, request.fcmToken)
            logger.info("[API] FCM token kaydedildi")
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }

        post("/api/v1/fcm/unregister") {
            val authedUserId = requireAuth(call) ?: return@post
            if (fcmTokenStore == null) {
                call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "FCM devre disi"))
                return@post
            }
            val request = call.receiveBounded<FcmUnregisterRequest>(SMALL_BODY_LIMIT) ?: return@post
            if (request.userId != authedUserId) {
                call.respond(HttpStatusCode.Forbidden, mapOf("error" to "userId token ile eslesmiyor"))
                return@post
            }
            fcmTokenStore.removeToken(authedUserId)
            logger.info("[API] FCM token silindi")
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }
    }
}

/**
 * Reads security-sensitive directory JSON with a hard byte ceiling before
 * deserialization. Content-Length alone is insufficient because a chunked
 * request could otherwise allocate an unbounded list before the fixed-batch
 * validation runs.
 */
/**
 * Govde boyutu sinirli JSON okuma.
 *
 * Bildirilen `Content-Length` ve gercekte okunan byte sayisi ayri ayri
 * kontrol edilir; bildirimi eksik veya yalan olan istekler de sinirlanir.
 */
private suspend inline fun <reified T> ApplicationCall.receiveBounded(
    maximumBytes: Int,
): T? {
    val declaredLength = request.contentLength()
    if (declaredLength != null && declaredLength > maximumBytes) {
        respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "body_too_large"))
        return null
    }
    val bytes = receiveChannel().readRemaining(maximumBytes.toLong() + 1L).readBytes()
    if (bytes.size > maximumBytes) {
        respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "body_too_large"))
        return null
    }
    return try {
        Json { ignoreUnknownKeys = true }.decodeFromString<T>(bytes.toString(Charsets.UTF_8))
    } catch (_: Exception) {
        respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_json"))
        null
    }
}

private suspend inline fun <reified T> ApplicationCall.receivePrivateDirectoryJson(
    maximumBytes: Int,
): T? {
    val declaredLength = request.contentLength()
    if (declaredLength != null && declaredLength > maximumBytes) {
        respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "directory_body_too_large"))
        return null
    }
    val bytes = receiveChannel().readRemaining(maximumBytes.toLong() + 1L).readBytes()
    if (bytes.size > maximumBytes) {
        respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "directory_body_too_large"))
        return null
    }
    return try {
        strictPrivateDirectoryJson.decodeFromString<T>(bytes.toString(Charsets.UTF_8))
    } catch (_: Exception) {
        respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_directory_json"))
        null
    }
}

/**
 * Authorization header'dan JWT token'i ayiklar ve dogrular.
 * Gecerliyse userId (sub) doner; degilse 401 yanit verir ve null doner.
 */
private suspend fun requireAuth(call: io.ktor.server.application.ApplicationCall): String? =
    requirePrincipal(call, serviceScope = null)

/**
 * Kullanici access token'i veya — yalniz `serviceScope` verilmisse — o
 * kapsamla sinirli bir servis assertion'i kabul eder.
 *
 * Servis assertion'i baska hicbir route'ta gecerli degildir: `serviceScope`
 * null oldugunda tek kabul edilen credential normal kullanici token'idir.
 */
private suspend fun requirePrincipal(
    call: io.ktor.server.application.ApplicationCall,
    serviceScope: ServiceAssertion.Scope?,
): String? {
    val authHeader = call.request.headers["Authorization"]
    val token = authHeader?.removePrefix("Bearer ")?.trim()
    if (token.isNullOrBlank()) {
        call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Authorization header gerekli"))
        return null
    }
    AuthService.verifyToken(token)?.let { return it }
    if (serviceScope != null) {
        ServiceAccounts.authenticate(token, serviceScope)?.let { return it }
    }
    call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz veya expired token"))
    return null
}
