package com.securechat.signaling

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.plugins.*
import kotlinx.serialization.Serializable
import com.securechat.signaling.db.Database
import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory

private val logger = LoggerFactory.getLogger("HttpRoutes")

/** Server baslangic zamani — uptime hesabi icin */
private val serverStartTime = System.currentTimeMillis()

@Serializable
data class CheckUsersRequest(val hashes: List<String>)

@Serializable
data class CheckUsersResponse(val users: List<ServerUser>)

@Serializable
data class ServerUser(val userId: String, val phoneHash: String)

@Serializable
data class RegisterRequest(
    val userId: String,
    val phoneHash: String,
    val encryptedPhone: String? = null,
    /** OTP dogrulama sonrasi alinan kisa omurlu registration token. */
    val registrationToken: String? = null
)

@Serializable
data class RegisterResponse(
    val userId: String,
    val phoneHash: String,
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
data class PhoneLookupResponse(val userId: String, val encryptedPhone: String?)

@Serializable
data class StatusResponse(
    val status: String,
    val onlineUsers: Int,
    val registeredUsers: Int
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
        // Sunucu durumu
        get("/") {
            call.respond(
                StatusResponse(
                    status = "ok",
                    onlineUsers = connectionManager.getOnlineCount(),
                    registeredUsers = userRegistry.getUserCount()
                )
            )
        }

        // Prometheus metrics — kimsiz acik (sadece internal network'tan erisilebilir)
        // Production'da Nginx ile IP whitelist veya basic auth ile koruyun.
        get("/metrics") {
            val accept = call.request.headers["Accept"] ?: "text/plain"
            call.respondText(
                Metrics.registry.scrape(),
                io.ktor.http.ContentType.parse("text/plain; version=0.0.4; charset=utf-8")
            )
        }

        // Health check — kritik bagimliliklar (DB + Redis); Janus ve FCM opsiyonel
        get("/health") {
            val dbOk = Database.isHealthy()
            val redisOk = RedisManager.isHealthy()
            val criticalOk = dbOk && redisOk
            val janusEnabled = !System.getenv("JANUS_WS_URL").isNullOrBlank()
            val fcmEnabled = !System.getenv("FIREBASE_SERVICE_ACCOUNT_PATH").isNullOrBlank()
            call.respond(
                if (criticalOk) HttpStatusCode.OK else HttpStatusCode.ServiceUnavailable,
                HealthResponse(
                    status = if (criticalOk) "ok" else "degraded",
                    database = if (dbOk) "ok" else "fail",
                    redis = if (redisOk) "ok" else "fail",
                    janus = if (janusEnabled) "enabled" else "disabled",
                    fcm = if (fcmEnabled) "enabled" else "disabled",
                    uptime_sec = (System.currentTimeMillis() - serverStartTime) / 1000
                )
            )
        }

        // Kullanici kesfi API — rate limited + AUTH GEREKLI
        post("/api/v1/users/check") {
            val authedUserId = requireAuth(call) ?: return@post
            val ip = call.request.origin.remoteAddress
            if (!RateLimiter.allow("users_check", authedUserId)) {
                val retry = RateLimiter.retryAfter("users_check", authedUserId)
                AuditLog.log(eventType = "RATE_LIMIT_HIT", userId = authedUserId,
                    metadata = mapOf("endpoint" to "users_check"), ipAddress = ip)
                call.response.header("Retry-After", retry.toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()))
                return@post
            }
            val request = call.receive<CheckUsersRequest>()
            val matched = userRegistry.checkRegisteredHashes(request.hashes)
            val response = CheckUsersResponse(
                users = matched.map { ServerUser(it.userId, it.phoneHash) }
            )
            logger.info("[API] Kullanici sorgusu: ${request.hashes.size} hash, ${matched.size} eslesme")
            call.respond(response)
        }

        // ========================================================
        // OTP — E-posta tabanli kayit dogrulamasi
        // ========================================================

        // OTP kodu iste — e-posta ile gonderilir
        post("/api/v1/otp/request") {
            val ip = call.request.origin.remoteAddress
            if (!RateLimiter.allow("otp_request", ip)) {
                call.response.header("Retry-After", RateLimiter.retryAfter("otp_request", ip).toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Cok fazla istek"))
                return@post
            }
            val body = call.receive<OtpRequestBody>()
            val email = body.email.trim().lowercase()
            // E-posta format kontrolu
            if (!email.matches(Regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"))) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz e-posta"))
                return@post
            }
            // Cooldown kontrolu — dakikada en fazla 1 OTP/email
            val lastAt = OtpService.lastOtpAt(email)
            if (System.currentTimeMillis() - lastAt < 60_000) {
                val wait = 60 - (System.currentTimeMillis() - lastAt) / 1000
                call.respond(HttpStatusCode.TooManyRequests,
                    mapOf("error" to "Lutfen bekleyin", "retryAfter" to wait.toString()))
                return@post
            }

            val otp = try {
                OtpService.generateOtp(email)
            } catch (e: Exception) {
                logger.error("[OTP] Generate hatasi: {}", e.message)
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
            AuditLog.log(eventType = "OTP_REQUESTED",
                metadata = mapOf("email_domain" to email.substringAfter('@')),
                ipAddress = ip)
            if (sent) {
                call.respond(OtpRequestResponse(true, "OTP gonderildi"))
            } else {
                call.respond(HttpStatusCode.ServiceUnavailable,
                    OtpRequestResponse(false, "E-posta gonderilemedi"))
            }
        }

        // OTP dogrula — basariliysa kisa omurlu registration token doner
        post("/api/v1/otp/verify") {
            val ip = call.request.origin.remoteAddress
            if (!RateLimiter.allow("otp_verify", ip)) {
                call.response.header("Retry-After", RateLimiter.retryAfter("otp_verify", ip).toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Cok fazla istek"))
                return@post
            }
            val body = call.receive<OtpVerifyBody>()
            val email = body.email.trim().lowercase()
            val ok = OtpService.verifyOtp(email, body.otp.trim())
            if (!ok) {
                AuditLog.log(eventType = "OTP_VERIFY_FAILED",
                    metadata = mapOf("email_domain" to email.substringAfter('@')),
                    ipAddress = ip)
                call.respond(HttpStatusCode.Unauthorized, OtpVerifyResponse(false))
                return@post
            }
            val regToken = AuthService.issueRegistrationToken(email)
            AuditLog.log(eventType = "OTP_VERIFIED",
                metadata = mapOf("email_domain" to email.substringAfter('@')),
                ipAddress = ip)
            call.respond(OtpVerifyResponse(true, regToken))
        }

        // Kullanici kaydi — rate limited + OTP registration token gerekli
        post("/api/v1/users/register") {
            val ip = call.request.origin.remoteAddress
            if (!RateLimiter.allow("users_register", ip)) {
                val retry = RateLimiter.retryAfter("users_register", ip)
                AuditLog.log(eventType = "RATE_LIMIT_HIT", metadata = mapOf("endpoint" to "users_register", "ip" to ip), ipAddress = ip)
                call.response.header("Retry-After", retry.toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()))
                return@post
            }
            val request = call.receive<RegisterRequest>()

            // GUVENLIK: OTP registration token zorunlu (e-posta dogrulanmis olmali)
            // Geriye uyumluluk: SMTP yapilandirilmamissa OTP zorunlu degil (geliştirme modu)
            val requireOtp = EmailService.isConfigured
            if (requireOtp) {
                val regToken = request.registrationToken
                if (regToken.isNullOrBlank()) {
                    call.respond(HttpStatusCode.Forbidden,
                        mapOf("error" to "registrationToken gerekli (once /otp/verify cagirin)"))
                    return@post
                }
                val verifiedEmail = AuthService.verifyRegistrationToken(regToken)
                if (verifiedEmail == null) {
                    AuditLog.log(eventType = "REGISTER_INVALID_TOKEN", ipAddress = ip)
                    call.respond(HttpStatusCode.Forbidden,
                        mapOf("error" to "Gecersiz veya expired registration token"))
                    return@post
                }
                logger.info("[Register] OTP-verified email={}", verifiedEmail.substringAfter('@'))
            }

            val (user, isNew) = userRegistry.registerUserByHash(request.userId, request.phoneHash, request.encryptedPhone)
            if (isNew) {
                AuditLog.log(userId = user.userId, eventType = "USER_REGISTERED", ipAddress = ip)
            }
            val accessToken = AuthService.issueToken(user.userId)
            val refreshToken = AuthService.issueRefreshToken(user.userId)
            call.respond(RegisterResponse(user.userId, user.phoneHash, isNew, accessToken, refreshToken))
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
            val ip = call.request.origin.remoteAddress
            // Access token'i revoke et
            if (accessToken != null) AuthService.revokeToken(accessToken)
            // Body'de refresh token varsa onu da revoke et
            try {
                val body = call.receive<RefreshTokenRequest>()
                AuthService.revokeToken(body.refreshToken)
            } catch (_: Exception) { /* body opsiyonel */ }
            AuditLog.log(userId = authedUserId, eventType = "USER_LOGOUT", ipAddress = ip)
            fcmTokenStore?.removeToken(authedUserId)
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }

        // Hesap silme — kullanici verisini PII'siz sekilde temizler
        post("/api/v1/account/delete") {
            val authedUserId = requireAuth(call) ?: return@post
            val ip = call.request.origin.remoteAddress
            try {
                Database.getConnection().use { conn ->
                    conn.autoCommit = false
                    try {
                        // FCM token sil
                        conn.prepareStatement("DELETE FROM fcm_tokens WHERE user_id = ?::uuid").use { s ->
                            s.setString(1, authedUserId); s.executeUpdate()
                        }
                        // Grup uyeliklerinden sil
                        conn.prepareStatement("DELETE FROM group_members WHERE user_id = ?::uuid").use { s ->
                            s.setString(1, authedUserId); s.executeUpdate()
                        }
                        // Kullaniciyi sil
                        conn.prepareStatement("DELETE FROM users WHERE user_id = ?::uuid").use { s ->
                            s.setString(1, authedUserId); s.executeUpdate()
                        }
                        conn.commit()
                    } catch (e: Exception) {
                        conn.rollback(); throw e
                    } finally {
                        conn.autoCommit = true
                    }
                }
                // In-memory cache'lerden de sil
                fcmTokenStore?.removeToken(authedUserId)
                // Redis offline queue temizle
                com.securechat.signaling.db.RedisManager.use { jedis ->
                    jedis.del("offline_queue:$authedUserId")
                }
                AuditLog.log(userId = authedUserId, eventType = "ACCOUNT_DELETED", ipAddress = ip)
                logger.info("[ACCOUNT] Hesap silindi: {}", authedUserId)
                call.respond(HttpStatusCode.OK, mapOf("status" to "deleted"))
            } catch (e: Exception) {
                logger.warn("[!] Hesap silme hatasi: {}", e.message)
                call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "Silme basarisiz"))
            }
        }

        // Token yenileme — refresh token ile yeni access + refresh ciftti uretir
        // (token rotation: eski refresh token blacklist'e alinir)
        post("/api/v1/auth/refresh") {
            val ip = call.request.origin.remoteAddress
            val body = try { call.receive<RefreshTokenRequest>() }
                catch (_: Exception) {
                    call.respond(HttpStatusCode.BadRequest, mapOf("error" to "refreshToken gerekli"))
                    return@post
                }
            val userId = AuthService.verifyRefreshToken(body.refreshToken)
            if (userId == null) {
                AuditLog.log(eventType = "AUTH_REFRESH_INVALID", ipAddress = ip)
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz refresh token"))
                return@post
            }
            // Token rotation: eski refresh'i revoke et
            AuthService.revokeToken(body.refreshToken)
            val newAccess = AuthService.issueToken(userId)
            val newRefresh = AuthService.issueRefreshToken(userId)
            AuditLog.log(userId = userId, eventType = "AUTH_TOKEN_REFRESHED", ipAddress = ip)
            call.respond(RefreshTokenResponse(newAccess, newRefresh))
        }

        // Kullanici sifreli telefon numarasi sorgulama — AUTH GEREKLI
        get("/api/v1/users/{userId}/phone") {
            requireAuth(call) ?: return@get
            val userId = call.parameters["userId"] ?: run {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "userId gerekli"))
                return@get
            }
            val user = userRegistry.getUserByUserId(userId)
            if (user == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Kullanici bulunamadi"))
            } else {
                call.respond(PhoneLookupResponse(userId = user.userId, encryptedPhone = user.encryptedPhone))
            }
        }

        // Online kullanici listesi — AUTH GEREKLI (admin/debug, prod'da kaldirilmali)
        get("/api/v1/users/online") {
            requireAuth(call) ?: return@get
            val online = connectionManager.getOnlineUsers()
            call.respond(mapOf("users" to online.joinToString(","), "count" to online.size.toString()))
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
            val authedUserId = requireAuth(call) ?: return@post
            val req = call.receive<PreKeyUploadRequest>()
            val decoder = java.util.Base64.getDecoder()
            try {
                PreKeyStore.setIdentityKey(
                    authedUserId,
                    decoder.decode(req.identityPublicKey),
                    req.registrationId
                )
                PreKeyStore.setSignedPreKey(
                    authedUserId,
                    PreKeyStore.SignedPreKey(
                        req.signedPreKeyId,
                        decoder.decode(req.signedPreKey),
                        decoder.decode(req.signedPreKeySignature)
                    )
                )
                PreKeyStore.addOneTimePreKeys(
                    authedUserId,
                    req.oneTimePreKeys.map {
                        PreKeyStore.OneTimePreKey(it.keyId, decoder.decode(it.publicKey))
                    }
                )
                call.respond(HttpStatusCode.OK, mapOf("status" to "ok",
                    "remaining" to PreKeyStore.unconsumedCount(authedUserId).toString()))
            } catch (e: Exception) {
                logger.warn("[PreKey] Upload hatasi: {}", e.message)
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz prekey verisi"))
            }
        }

        // One-time prekey havuzunu yenile (rotation)
        post("/api/v1/prekeys/refresh") {
            val authedUserId = requireAuth(call) ?: return@post
            val keys = call.receive<List<PreKeyEntry>>()
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
            requireAuth(call) ?: return@get
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
            val request = call.receive<FcmRegisterRequest>()
            // userId mutlaka token'in sub'i ile eslesmeli
            if (request.userId != authedUserId) {
                call.respond(HttpStatusCode.Forbidden, mapOf("error" to "userId token ile eslesmiyor"))
                return@post
            }
            fcmTokenStore.registerToken(authedUserId, request.fcmToken)
            logger.info("[API] FCM token kaydedildi: {}", authedUserId)
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }

        post("/api/v1/fcm/unregister") {
            val authedUserId = requireAuth(call) ?: return@post
            if (fcmTokenStore == null) {
                call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "FCM devre disi"))
                return@post
            }
            val request = call.receive<FcmUnregisterRequest>()
            if (request.userId != authedUserId) {
                call.respond(HttpStatusCode.Forbidden, mapOf("error" to "userId token ile eslesmiyor"))
                return@post
            }
            fcmTokenStore.removeToken(authedUserId)
            logger.info("[API] FCM token silindi: {}", authedUserId)
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }
    }
}

/**
 * Authorization header'dan JWT token'i ayiklar ve dogrular.
 * Gecerliyse userId (sub) doner; degilse 401 yanit verir ve null doner.
 */
private suspend fun requireAuth(call: io.ktor.server.application.ApplicationCall): String? {
    val authHeader = call.request.headers["Authorization"]
    val token = authHeader?.removePrefix("Bearer ")?.trim()
    if (token.isNullOrBlank()) {
        call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Authorization header gerekli"))
        return null
    }
    val userId = AuthService.verifyToken(token)
    if (userId == null) {
        call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz veya expired token"))
        return null
    }
    return userId
}
