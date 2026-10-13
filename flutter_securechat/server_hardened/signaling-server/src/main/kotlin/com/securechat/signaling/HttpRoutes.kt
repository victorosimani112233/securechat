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

/** PQ Kyber public keys make a 100-key v2 upload roughly 220 KiB. */
private const val MODERN_PREKEY_BODY_LIMIT = 512 * 1024

/** Sealed Sender ciphertext plus bounded JSON/Base64 overhead. */

/** Tek yuklemede kabul edilen en fazla one-time prekey sayisi. */
internal const val MAX_ONE_TIME_PREKEYS = 200

/** Curve25519 public key 33, imza 64 byte; ust sinir bunun uzerinde tutuldu. */
internal const val MAX_KEY_MATERIAL_BYTES = 128

/** Hesap basina saklanabilecek tuketilmemis one-time prekey ust siniri. */
internal const val MAX_STORED_ONE_TIME_PREKEYS = 1_000

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

/**
 * Karisik tipli `mapOf(...)` yanitlari calisma zamaninda serialize edilemez:
 * `Map<String, Any>` icin serializer yoktur ve endpoint 500 dondururdu.
 * Tipli yanitlar bunu derleme zamaninda imkansiz kilar.
 */
@Serializable
data class LatestVersionResponse(
    val versionCode: Int,
    val versionName: String,
    val downloadUrl: String,
    val mandatory: Boolean,
)

@Serializable
data class SfuRoomResponse(
    val roomId: Long,
    val janusWsUrl: String,
    val status: String,
)

@Serializable
data class DirectorySnapshotResponse(
    val keyId: String,
    val entries: List<DirectorySnapshotEntryResponse>,
)

@Serializable
data class OwnDirectoryUpdateRequest(val directoryToken: String)

@Serializable
data class RegisterRequest(
    val userId: String,
    /** OTP dogrulama sonrasi alinan kisa omurlu registration token. */
    val registrationToken: String? = null,
    /**
     * Kayit OTP'siyle dogrulanan e-posta kurtarma e-postasi olarak da
     * baglansin mi (QA 2026-10-13 R3). Kullanici kayit ekraninda secer.
     */
    val bindRecoveryEmail: Boolean = false,
)

@Serializable
data class RegisterResponse(
    val userId: String,
    val isNew: Boolean,
    val accessToken: String,
    val refreshToken: String,
    /** Kurtarma e-postasi kayitla birlikte baglandi mi. */
    val recoveryEmailBound: Boolean = false,
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
    // --- libsignal (eski istemci) ---
    //
    // Hepsi opsiyonel oldu. Vodozemac'a gecmis bir istemcide bu alanlarin
    // karsiligi YOK: `registrationId` Olm'da olmayan bir kavram, signed
    // prekey'in yerini imzali fallback anahtari aliyor. Zorunlu
    // birakilsalardi yeni istemci kendi anahtarlarini yukleyebilmek icin
    // uydurma libsignal degerleri gondermek zorunda kalirdi.
    val identityPublicKey: String? = null,
    val registrationId: Int? = null,
    val signedPreKeyId: Int? = null,
    val signedPreKey: String? = null,
    val signedPreKeySignature: String? = null,
    val oneTimePreKeys: List<PreKeyEntry> = emptyList(),

    // --- Olm (vodozemac) ---
    //
    // Kimlik IKI anahtardan olusur ve istemci ikisini birlikte pinler;
    // biri olmadan digeri kabul edilmez.
    val olmIdentityKey: String? = null,
    val olmSigningKey: String? = null,
    val olmOneTimeKeys: List<OlmPreKeyEntry> = emptyList(),
    // Fallback anahtari IMZALI olmak zorunda. Imzasiz fallback bir MITM
    // araci degil (sunucu alicinin kimlik ozel anahtarina sahip degil),
    // ama sessiz ve kalici bir TESLIM REDDI aracidir.
    val olmFallbackKey: String? = null,
    val olmFallbackKeySignature: String? = null,
) {
    /** Tam bir libsignal bundle'i var mi. */
    val hasLibsignalBundle: Boolean
        get() = identityPublicKey != null && registrationId != null &&
            signedPreKeyId != null && signedPreKey != null &&
            signedPreKeySignature != null

    /** Tam bir Olm kimligi var mi. */
    val hasOlmIdentity: Boolean
        get() = olmIdentityKey != null && olmSigningKey != null
}

@Serializable
data class PreKeyEntry(val keyId: Int, val publicKey: String) // publicKey base64

/**
 * Olm tek kullanimlik anahtar girdisi.
 *
 * [PreKeyEntry]'den ayri olmasinin tek sebebi `keyId`'nin dize olmasi:
 * Olm anahtar kimligi vodozemac tarafindan uretilir ve base64'tur,
 * libsignal'daki gibi tamsayi degildir.
 */
@Serializable
data class OlmPreKeyEntry(val keyId: String, val publicKey: String)

/**
 * Prekey yuklemesinin alan bazinda makul olup olmadigi.
 *
 * Onceki akista one-time prekey sayisi ve anahtar boyutlari sinirsizdi;
 * tek bir istek binlerce satir veya cok buyuk alanlar yazdirabiliyordu.
 */
/**
 * Refresh yolundaki one-time prekey listesinin alan bazinda gecerliligi.
 *
 * `/prekeys/refresh` daha once `hasSaneKeyMaterial()`'i atliyordu: keyId
 * araligi, anahtar boyutu, sayi tavani ve tekrar kontrolu yoktu; bir hesap
 * her istekte farkli keyId'lerle sinirsiz satir ekleyebiliyordu.
 */
internal fun List<PreKeyEntry>.hasSaneOneTimeKeys(): Boolean {
    if (size > MAX_ONE_TIME_PREKEYS) return false
    if (distinctBy { it.keyId }.size != size) return false
    return all { entry ->
        entry.keyId in 0..0xFFFFFF &&
            (runCatching { java.util.Base64.getDecoder().decode(entry.publicKey).size }
                .getOrDefault(0)) in 1..MAX_KEY_MATERIAL_BYTES
    }
}

private fun decodedSize(value: String): Int? = try {
    java.util.Base64.getDecoder().decode(value).size
} catch (_: Exception) {
    null
}

/**
 * Yuklemenin alan bazinda makul olup olmadigi.
 *
 * Iki sekil kabul edilir: libsignal bundle'i, Olm bundle'i ya da ikisi
 * birden. Ama **en az biri TAM olmak zorunda**. Yarim bir sekil kabul
 * edilirse, hesap kismi bir kimlikle kayitli kalir ve karsi taraf oturum
 * kuramaz; bos donen bir bundle'dan daha kotu bir durum, cunku hatanin
 * yuklemede oldugu gorunmez.
 */
internal fun PreKeyUploadRequest.hasSaneKeyMaterial(): Boolean {
    if (!hasLibsignalBundle && !hasOlmIdentity) return false
    if (hasLibsignalBundle && !hasSaneLibsignalMaterial()) return false
    if (hasOlmIdentity && !hasSaneOlmMaterial()) return false
    // Olm kimligi olmadan Olm anahtari gondermek anlamsiz: anahtarlarin
    // bagli olacagi bir kimlik yok.
    if (!hasOlmIdentity &&
        (olmOneTimeKeys.isNotEmpty() || olmFallbackKey != null)
    ) {
        return false
    }
    return true
}

private fun PreKeyUploadRequest.hasSaneLibsignalMaterial(): Boolean {
    if (registrationId !in 1..16_383) return false
    if (signedPreKeyId !in 0..0xFFFFFF) return false
    if (oneTimePreKeys.size > MAX_ONE_TIME_PREKEYS) return false
    if (oneTimePreKeys.distinctBy { it.keyId }.size != oneTimePreKeys.size) return false
    for (value in listOf(identityPublicKey, signedPreKey, signedPreKeySignature)) {
        val size = decodedSize(value ?: return false) ?: return false
        if (size !in 1..MAX_KEY_MATERIAL_BYTES) return false
    }
    return oneTimePreKeys.all { entry ->
        entry.keyId in 0..0xFFFFFF &&
            (decodedSize(entry.publicKey) ?: 0) in 1..MAX_KEY_MATERIAL_BYTES
    }
}

private fun PreKeyUploadRequest.hasSaneOlmMaterial(): Boolean {
    // Olm anahtarlari TAM 32 bayt. Ust sinir yerine tam uzunluk
    // kontrolu yapiliyor: 33 bayt gelmesi libsignal'in tur onekli
    // kodlamasi demektir ve oneki kirpip kabul etmek, cozulemeyen mesaj
    // ureten bir oturum kurmakla sonuclanir.
    for (value in listOf(olmIdentityKey, olmSigningKey)) {
        if (decodedSize(value ?: return false) != OlmPreKeyStore.KEY_LENGTH) return false
    }
    if (olmOneTimeKeys.size > MAX_ONE_TIME_PREKEYS) return false
    if (olmOneTimeKeys.distinctBy { it.keyId }.size != olmOneTimeKeys.size) return false
    // Kimlik base64 bir dize; uzunlugu sinirlanmali, aksi halde tek bir
    // istek cok buyuk kimliklerle tabloyu sisirebilir.
    if (olmOneTimeKeys.any {
            it.keyId.isEmpty() || it.keyId.length > 64 ||
                decodedSize(it.publicKey) != OlmPreKeyStore.KEY_LENGTH
        }
    ) {
        return false
    }
    // Fallback anahtari ve imzasi ayrilamaz: biri varsa digeri de olmali.
    if ((olmFallbackKey == null) != (olmFallbackKeySignature == null)) return false
    if (olmFallbackKey != null) {
        if (decodedSize(olmFallbackKey) != OlmPreKeyStore.KEY_LENGTH) return false
        if (decodedSize(olmFallbackKeySignature!!) != OlmPreKeyStore.SIGNATURE_LENGTH) {
            return false
        }
    }
    return true
}

@Serializable
data class PreKeyBundleResponse(
    val userId: String,
    // Istemcinin konustugu bundle surumu. Olm alanlari yoksa yeni istemci
    // bu bundle'i KULLANMAZ ve bu dogru davranis: o peer henuz goc
    // etmemis, onunla Olm oturumu kurulamaz.
    //
    // VARSAYILAN DEGER YOK, bilerek. kotlinx.serialization'da
    // `encodeDefaults` varsayilan olarak false; varsayilanina esit bir alan
    // JSON'a hic yazilmiyor. Bu alan varsayilanli oldugunda surum bilgisi
    // kabloya hic cikmiyordu ve istemci bundle'i "surum yok" diye
    // reddediyordu.
    val protocolVersion: Int,

    // --- libsignal (eski istemci) ---
    val identityPublicKey: String? = null,
    val registrationId: Int? = null,
    val signedPreKeyId: Int? = null,
    val signedPreKey: String? = null,
    val signedPreKeySignature: String? = null,
    val oneTimePreKey: PreKeyEntry? = null,

    // --- Olm (vodozemac) ---
    val identityKey: String? = null,
    val signingKey: String? = null,
    val oneTimeKey: String? = null,
    val fallbackKey: String? = null,
    val fallbackKeySignature: String? = null,
)

/** Istemcinin `expectedProtocolVersion` degeriyle ayni olmali. */
const val OLM_BUNDLE_PROTOCOL_VERSION = 3

@Serializable
data class StatusResponse(
    val status: String
)

@Serializable
data class FcmRegisterRequest(
    val userId: String,
    val fcmToken: String,
    val pushHintKey: String? = null,
)

@Serializable
data class FcmRegisterResponse(
    val status: String,
    val pushHintRegistered: Boolean,
    val pushContract: String,
)

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
    fcmTokenStore: FcmTokenStore? = null,
    fcmPushSender: FcmPushSender? = null,
) {
    routing {
        recoveryAuthRoutes()
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

        // Liveness: process ayakta mi. Bagimlilik ayrintisi tasimaz; anonim
        // bir istemciye stack'in ic yapisini vermek gerekmez.
        get("/health") {
            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
        }

        // Readiness: operator'a ozel ayrintili durum.
        get("/ready") {
            if (!MetricsAccess.isAuthorized(call.request.headers["Authorization"])) {
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "unauthorized"))
                return@get
            }
            val dbOk = Database.isHealthy()
            val redisOk = RedisManager.isHealthy()
            val privacyOk = PrivacyRetentionWorker.isHealthy()
            val criticalOk = dbOk && redisOk && privacyOk
            val janusEnabled = !System.getenv("JANUS_WS_URL").isNullOrBlank()
            // Env path'inin varligi push'in calistigini kanitlamaz; gercek
            // baslatma sonucu raporlanir.
            val fcmEnabled = fcmPushSender?.isOperational == true
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
                LatestVersionResponse(
                    versionCode = versionCode ?: 0,
                    versionName = versionName,
                    downloadUrl = downloadUrl,
                    mandatory = System.getenv("LATEST_APK_MANDATORY") == "true",
                ),
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
            // Redis sliding window kalicisizdir (RDB kapali); restart sonrasi
            // sifirlanan bir kota enumeration'a karsi tekrar denenebilir bir
            // engeldir. Kalici gunluk kota bunun icin ayrica kontrol edilir.
            if (!DirectoryQuota.tryConsume(authedUserId, PrivateDirectoryOprf.AUTHENTICATED_BATCH_SIZE)) {
                call.response.header("Retry-After", "3600")
                call.respond(
                    HttpStatusCode.TooManyRequests,
                    mapOf("error" to "directory_quota_exhausted", "retryAfter" to "3600"),
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
            val entries = DirectorySnapshotCache.entries(userRegistry).map { entry ->
                DirectorySnapshotEntryResponse(entry.label, entry.sealedUserId)
            }
            call.respond(DirectorySnapshotResponse(PrivateDirectory.oprf.keyId, entries))
        }

        // The client sends only a finalized blind-OPRF token. A deterministic
        // phone hash must never cross this API boundary.
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
                userRegistry.updateOwnDirectoryToken(authedUserId, request.directoryToken)
            } catch (_: IllegalArgumentException) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_directory_token"))
                return@post
            }
            // Deger nullable olmamali: `Map<String, String?>` yaniti tip guvenli
            // degil ve yanit sozlesmesini belirsiz birakir.
            call.respond(mapOf("status" to "ok", "keyId" to updated.directoryKeyId.orEmpty()))
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
            val demoCode = ReviewDemo.issueCode(email)
            val otp = try {
                OtpService.generateOtp(email, demoCode)
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

            // Store inceleme demo hesabi: kod operatorce bilinir, e-posta gitmez.
            if (demoCode != null) {
                AuditLog.log(eventType = "OTP_REQUESTED", ipAddress = ip)
                call.respond(OtpRequestResponse(true, "OTP gonderildi"))
                return@post
            }

            // E-postayi async gonder (response'u bekletme)
            val sent = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                val content = EmailTemplates.code(EmailTemplates.Purpose.REGISTRATION, otp)
                EmailService.sendMail(
                    to = email,
                    subject = content.subject,
                    htmlBody = content.html,
                    textBody = content.text,
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
            val regToken = AuthService.issueRegistrationToken(verifiedEmail = email)
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
            val request = call.receiveBounded<RegisterRequest>(
                SMALL_BODY_LIMIT,
                ignoreUnknownKeys = false,
            ) ?: return@post

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

            var recoveryEmailBound = false
            val user = try {
                // Grant tuketimi ile hesap kaydi tek transaction'dadir: kayit
                // geri alinirsa grant yanmaz, kayit basarili olursa grant
                // kalici olarak tukenmis sayilir.
                val candidate = userRegistry.prepareRegistration(request.userId)
                RegistrationGrants.claimAccount(grant, candidate, userRegistry) { connection ->
                    if (request.bindRecoveryEmail) {
                        recoveryEmailBound = bindRegistrationRecoveryEmail(connection, grant, candidate.userId)
                    }
                }
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
            call.respond(RegisterResponse(user.userId, true, accessToken, refreshToken, recoveryEmailBound))
        }

        // Logout — access token blacklist'e alinir (revocation)
        // Body'de opsiyonel refresh token da revoke edilir.
        post("/api/v1/auth/logout") {
            val authedUserId = requireAuth(call) ?: return@post
            val expectedEpoch = call.attributes[authenticatedEpochKey]
            val ip = call.clientAddress()
            // Tek adimda hesabin butun access/refresh token'lari gecersizlesir.
            // Kayit PostgreSQL'de oldugu icin Redis restart'i veya eviction'i
            // iptal edilmis bir token'i geri getiremez.
            if (!AuthService.revokeAllTokens(authedUserId, expectedEpoch)) {
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
                    expectedEpoch = call.attributes[authenticatedEpochKey],
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

        // Kotuye kullanim bildirimi ve moderasyon (Apple 1.2, Play UGC/CSAE).
        abuseReportRoutes(
            requireAuth = ::requireAuth,
            userRegistry = userRegistry,
            removeAccount = { userId ->
                AccountDeletion.execute(
                    userId = userId,
                    connectionManager = connectionManager,
                    userRegistry = userRegistry,
                    fcmTokenStore = fcmTokenStore,
                )
            },
        )

        // Token yenileme — refresh token ile yeni access + refresh ciftti uretir
        // (token rotation: eski refresh token blacklist'e alinir)
        post("/api/v1/auth/refresh") {
            val ip = call.clientAddress()
            if (!RateLimiter.allow("auth_refresh", ip)) {
                val retry = RateLimiter.retryAfter("auth_refresh", ip)
                AuditLog.log(eventType = "RATE_LIMIT_HIT", metadata = mapOf("endpoint" to "auth_refresh"), ipAddress = ip)
                call.response.header("Retry-After", retry.toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()))
                return@post
            }
            val body = call.receiveBounded<RefreshTokenRequest>(SMALL_BODY_LIMIT) ?: return@post
            val claims = try {
                AuthService.refreshClaims(body.refreshToken, throwWhenUnavailable = true)
            } catch (_: AuthService.CredentialStateUnavailable) {
                call.respondCredentialStateUnavailable()
                return@post
            }
            if (claims == null) {
                AuditLog.log(eventType = "AUTH_REFRESH_INVALID", ipAddress = ip)
                call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz refresh token"))
                return@post
            }
            // Rotasyon tek atomik compare-and-set'tir: ayni eski token ile
            // paralel iki istek gelirse yalniz biri yeni kusak uretebilir.
            // Supersede edilmis bir token'in yeniden kullanilmasi burada
            // fail-closed olur.
            // Yanit kaybolduysa (QA 2026-10-12 R1) ayni eski token kisa bir
            // pencerede bir kez daha kabul edilir; yeni kusak uretilmez.
            val rotated = try {
                CredentialState.rotateRefreshGeneration(
                    claims.userId,
                    claims.refreshGeneration,
                ) ?: CredentialState.redeemLostRotation(
                    claims.userId,
                    claims.refreshGeneration,
                )?.also {
                    AuditLog.log(userId = claims.userId, eventType = "AUTH_REFRESH_LOST_RESPONSE_REDEEMED", ipAddress = ip)
                }
            } catch (_: Exception) {
                // Karar verilemedi; 401 istemcide oturumu kapatirdi.
                call.respondCredentialStateUnavailable()
                return@post
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

        // Cihaz anahtariyla yeniden oturum (QA 2026-10-13 R3 madde 3): refresh
        // 401 aldiginda istemci reddedilen token'i ve sunucu sorusunun Olm
        // Ed25519 imzasini sunar. Ayrintilar `DeviceReauth`.
        post("/api/v1/auth/device/challenge") {
            val ip = call.clientAddress()
            if (!RateLimiter.allow("auth_device_reauth", ip)) {
                call.response.header("Retry-After", RateLimiter.retryAfter("auth_device_reauth", ip).toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi"))
                return@post
            }
            call.response.headers.append("Cache-Control", "no-store")
            val challenge = DeviceReauth.issueChallenge()
            if (challenge == null) {
                call.respondCredentialStateUnavailable()
                return@post
            }
            call.respond(challenge)
        }

        post("/api/v1/auth/device/verify") {
            val ip = call.clientAddress()
            if (!RateLimiter.allow("auth_device_reauth", ip)) {
                call.response.header("Retry-After", RateLimiter.retryAfter("auth_device_reauth", ip).toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi"))
                return@post
            }
            call.response.headers.append("Cache-Control", "no-store")
            val body = call.receiveBounded<DeviceReauthRequest>(SMALL_BODY_LIMIT) ?: return@post
            when (val outcome = DeviceReauth.reauthenticate(body)) {
                is DeviceReauth.Outcome.Issued -> {
                    val access = AuthService.issueToken(outcome.userId, outcome.snapshot.credentialEpoch)
                    val refresh = AuthService.issueRefreshToken(
                        outcome.userId,
                        outcome.snapshot.credentialEpoch,
                        outcome.snapshot.refreshGeneration,
                    )
                    AuditLog.log(userId = outcome.userId, eventType = "AUTH_DEVICE_REAUTH", ipAddress = ip)
                    call.respond(RefreshTokenResponse(access, refresh))
                }
                DeviceReauth.Outcome.Rejected -> {
                    AuditLog.log(eventType = "AUTH_DEVICE_REAUTH_REJECTED", ipAddress = ip)
                    call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "device_reauth_rejected"))
                }
                DeviceReauth.Outcome.Unavailable -> call.respondCredentialStateUnavailable()
            }
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
            val expectedEpoch = call.prekeyWriteEpoch()
            if (!RateLimiter.allow("prekey_write", authedUserId)) {
                val retry = RateLimiter.retryAfter("prekey_write", authedUserId)
                call.response.header("Retry-After", retry.toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()))
                return@post
            }
            val req = call.receiveBounded<PreKeyUploadRequest>(PREKEY_BODY_LIMIT) ?: return@post
            val decoder = java.util.Base64.getDecoder()
            // Alan bazinda sinirlar: govde limiti tek basina yetmez, cunku
            // az sayida ama cok buyuk alan da kabul edilirdi.
            if (!req.hasSaneKeyMaterial()) {
                AuditLog.log(eventType = "PREKEY_UPLOAD_REJECTED", ipAddress = call.clientAddress())
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_prekey_material"))
                return@post
            }
            // Hesap basina depolama tavani: identity ayni kalirken gelen
            // one-time prekey'ler mevcut havuza eklenir; sinirsizken tek hesap
            // tabloyu sinirsiz buyutebiliyordu. Iki havuz AYRI sayilir,
            // cunku ayri tablolarda duruyorlar.
            if (PreKeyStore.unconsumedCount(authedUserId) + req.oneTimePreKeys.size >
                MAX_STORED_ONE_TIME_PREKEYS ||
                OlmPreKeyStore.unconsumedCount(authedUserId) + req.olmOneTimeKeys.size >
                MAX_STORED_ONE_TIME_PREKEYS
            ) {
                call.respond(HttpStatusCode.Conflict, mapOf("error" to "prekey_pool_full"))
                return@post
            }
            try {
                if (req.hasLibsignalBundle) {
                    // Identity, signed prekey ve one-time prekey'ler tek
                    // transaction'da yazilir; yarim bir bundle olusamaz.
                    PreKeyStore.uploadBundle(
                        userId = authedUserId,
                        expectedEpoch = expectedEpoch,
                        identityPublicKey = decoder.decode(req.identityPublicKey!!),
                        registrationId = req.registrationId!!,
                        signedPreKey = PreKeyStore.SignedPreKey(
                            req.signedPreKeyId!!,
                            decoder.decode(req.signedPreKey!!),
                            decoder.decode(req.signedPreKeySignature!!)
                        ),
                        oneTimePreKeys = req.oneTimePreKeys.map {
                            PreKeyStore.OneTimePreKey(it.keyId, decoder.decode(it.publicKey))
                        },
                    )
                }
                if (req.hasOlmIdentity) {
                    OlmPreKeyStore.setIdentity(
                        userId = authedUserId,
                        identityKey = decoder.decode(req.olmIdentityKey!!),
                        signingKey = decoder.decode(req.olmSigningKey!!),
                        expectedEpoch = expectedEpoch,
                    )
                    if (req.olmFallbackKey != null) {
                        OlmPreKeyStore.setFallbackKey(
                            userId = authedUserId,
                            key = OlmPreKeyStore.FallbackKey(
                                decoder.decode(req.olmFallbackKey),
                                decoder.decode(req.olmFallbackKeySignature!!),
                            ),
                            expectedEpoch = expectedEpoch,
                        )
                    }
                    if (req.olmOneTimeKeys.isNotEmpty()) {
                        OlmPreKeyStore.addOneTimeKeys(
                            userId = authedUserId,
                            keys = req.olmOneTimeKeys.map {
                                OlmPreKeyStore.OneTimeKey(it.keyId, decoder.decode(it.publicKey))
                            },
                            expectedEpoch = expectedEpoch,
                        )
                    }
                }
                call.respond(HttpStatusCode.OK, mapOf("status" to "ok",
                    "remaining" to PreKeyStore.unconsumedCount(authedUserId).toString(),
                    "olmRemaining" to OlmPreKeyStore.unconsumedCount(authedUserId).toString()))
            } catch (conflict: PreKeyStore.KeyConflictException) {
                // v1 havuzu da Olm ile ayni kurala tabi: ayni keyId farkli
                // materyalle gelirse 409. Eskiden sessizce eskisi tutulup
                // 200 donuyordu.
                logger.warn("[PreKey] v1 key catismasi: keyId={}", conflict.keyId)
                call.respond(
                    HttpStatusCode.Conflict,
                    mapOf("error" to "prekey_conflict", "keyId" to conflict.keyId.toString()),
                )
            } catch (_: OlmPreKeyStore.IdentityRecoveryRequiredException) {
                // Cihazin kimligi hesaptakinden farkli: istemci kullaniciyi
                // e-postayla kurtarmaya yonlendirir. Eskiden genel 400 donuyor
                // ve istemci yalniz teshis satiri yaziyordu.
                logger.warn("[PreKey] Olm kimligi hesaptakiyle uyusmuyor")
                call.respond(
                    HttpStatusCode.Conflict,
                    mapOf("error" to "identity_recovery_required"),
                )
            } catch (conflict: OlmPreKeyStore.KeyConflictException) {
                // Ayni keyId farkli materyalle geldi. 409 donmek sart:
                // sessizce eskisini tutup 200 donmek, istemcinin yuklendigini
                // sandigi anahtarin karsi tarafa hic gitmemesi demektir ve
                // olusan oturum cozulemez.
                logger.warn("[PreKey] Olm key catismasi: keyId={}", conflict.keyId)
                call.respond(
                    HttpStatusCode.Conflict,
                    mapOf("error" to "prekey_conflict", "keyId" to conflict.keyId.toString()),
                )
            } catch (e: Exception) {
                logger.warn("[PreKey] Upload hatasi: {}", e.javaClass.simpleName)
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz prekey verisi"))
            }
        }

        // One-time prekey havuzunu yenile (rotation)
        get("/api/v1/prekeys/status") {
            val authedUserId = requireAuth(call) ?: return@get
            // Iki havuz ayri sayilir. Tek bir sayi dondurmek, goc etmis bir
            // istemcinin bos Olm havuzunu dolu libsignal havuzu arkasinda
            // gizlerdi ve tamamlama hic tetiklenmezdi.
            call.respond(
                mapOf(
                    "remaining" to PreKeyStore.unconsumedCount(authedUserId),
                    "olmRemaining" to OlmPreKeyStore.unconsumedCount(authedUserId),
                ),
            )
        }

        // One-time prekey havuzunu yenile (rotation)
        post("/api/v1/prekeys/refresh") {
            val authedUserId = requireAuth(call) ?: return@post
            val expectedEpoch = call.attributes[authenticatedEpochKey]
            if (!RateLimiter.allow("prekey_write", authedUserId)) {
                val retry = RateLimiter.retryAfter("prekey_write", authedUserId)
                call.response.header("Retry-After", retry.toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()))
                return@post
            }
            val keys = call.receiveBounded<List<PreKeyEntry>>(PREKEY_BODY_LIMIT) ?: return@post
            // Upload ile ayni alan kontrolleri; refresh bunlari atliyordu.
            if (!keys.hasSaneOneTimeKeys()) {
                AuditLog.log(eventType = "PREKEY_UPLOAD_REJECTED", ipAddress = call.clientAddress())
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_prekey_material"))
                return@post
            }
            if (PreKeyStore.unconsumedCount(authedUserId) + keys.size >
                MAX_STORED_ONE_TIME_PREKEYS
            ) {
                call.respond(HttpStatusCode.Conflict, mapOf("error" to "prekey_pool_full"))
                return@post
            }
            val decoder = java.util.Base64.getDecoder()
            try {
                PreKeyStore.addOneTimePreKeys(
                    authedUserId,
                    keys.map { PreKeyStore.OneTimePreKey(it.keyId, decoder.decode(it.publicKey)) },
                    expectedEpoch = expectedEpoch,
                )
                call.respond(HttpStatusCode.OK, mapOf("status" to "ok",
                    "remaining" to PreKeyStore.unconsumedCount(authedUserId).toString()))
            } catch (conflict: PreKeyStore.KeyConflictException) {
                logger.warn("[PreKey] v1 key catismasi: keyId={}", conflict.keyId)
                call.respond(
                    HttpStatusCode.Conflict,
                    mapOf("error" to "prekey_conflict", "keyId" to conflict.keyId.toString()),
                )
            } catch (e: Exception) {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz prekey"))
            }
        }

        // Diger client baska bir kullanicinin prekey bundle'ini ister.
        //
        // Bu yolun ardinda bir zamanlar bir V2 plani vardi (PQXDH + Sealed
        // Sender) ve yorum bu yolu "eski surum" diye tarif ediyordu. O plan
        // artik yok: istemci kripto cekirdegi vodozemac'a tasindi, sealed
        // sender kaldirildi ve vodozemac post-quantum tasimiyor. Yani bu
        // artik bir gecis yolu degil, tek prekey yolu.
        //
        // Kullanici token'i ile acik: mesajlasmanin calismasi icin her
        // istemcinin peer bundle'i cekebilmesi gerekir. Bir zamanlar yalniz
        // servis assertion'i kabul ediyordu ve hicbir istemci oturum
        // kuramiyordu; Bot API kaldirilinca servis principal'i de tumden
        // kalkti. Numaralandirmanin siniri asagidaki rate limit.
        get("/api/v1/users/{userId}/prekeys") {
            val fetcherId = requireAuth(call) ?: return@get
            // Her fetch hedefin bir one-time prekey'ini tuketir; cagiran
            // basina sinir, bilinen bir UUID'nin havuzunun bosaltilmasini
            // yavaslatir (whitebox bulgu).
            if (!RateLimiter.allow("prekey_fetch", fetcherId)) {
                val retry = RateLimiter.retryAfter("prekey_fetch", fetcherId)
                call.response.header("Retry-After", retry.toString())
                call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi", "retryAfter" to retry.toString()))
                return@get
            }
            // UUID olmayan kimlik DB'ye gitmeden reddedilir; eskiden Postgres
            // `invalid input syntax for type uuid` atip 500 donuyordu
            // (QA 2026-10-13 T7: istemci "SYSTEM" icin bundle istiyordu).
            val targetUserId = call.parameters["userId"]
                ?.let { runCatching { java.util.UUID.fromString(it).toString() }.getOrNull() }
                ?: run {
                    call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Gecersiz userId"))
                    return@get
                }
            // IKI sekil de servis edilir. Hangisinin bulunacagi peer'in
            // goc edip etmedigine bagli, ve 404 kosulu bu yuzden
            // "libsignal bundle'i yok" DEGIL "hicbiri yok" olmali: goc
            // etmis bir peer'in libsignal bundle'i hic bulunmaz.
            val legacy = PreKeyStore.fetchBundle(targetUserId)
            val olm = OlmPreKeyStore.fetchBundle(targetUserId)
            if (legacy == null && olm == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Bundle bulunamadi (kullanici prekey upload etmemis olabilir)"))
                return@get
            }
            val encoder = java.util.Base64.getEncoder()
            call.respond(PreKeyBundleResponse(
                userId = targetUserId,
                protocolVersion = OLM_BUNDLE_PROTOCOL_VERSION,
                identityPublicKey = legacy?.let { encoder.encodeToString(it.identityKey.publicKey) },
                registrationId = legacy?.identityKey?.registrationId,
                signedPreKeyId = legacy?.signedPreKey?.keyId,
                signedPreKey = legacy?.let { encoder.encodeToString(it.signedPreKey.publicKey) },
                signedPreKeySignature = legacy?.let {
                    encoder.encodeToString(it.signedPreKey.signature)
                },
                oneTimePreKey = legacy?.oneTimePreKey?.let {
                    PreKeyEntry(it.keyId, encoder.encodeToString(it.publicKey))
                },
                identityKey = olm?.let { encoder.encodeToString(it.identityKey) },
                signingKey = olm?.let { encoder.encodeToString(it.signingKey) },
                oneTimeKey = olm?.oneTimeKey?.let { encoder.encodeToString(it) },
                fallbackKey = olm?.fallbackKey?.let { encoder.encodeToString(it.publicKey) },
                fallbackKeySignature = olm?.fallbackKey?.let {
                    encoder.encodeToString(it.signature)
                },
            ))
        }

        // --- SFU Room Bilgisi — AUTH GEREKLI ---
        get("/api/v1/sfu/room/{groupId}") {
            val authedUserId = requireAuth(call) ?: return@get
            val groupId = call.parameters["groupId"] ?: run {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "groupId gerekli"))
                return@get
            }
            // Kimlik dogrulamasi tek basina yetki degildir: yalniz aktif
            // cagrinin katilimcisi oda bilgisini alabilir.
            val activeCall = GroupCallSessionStore.get(groupId)
            if (activeCall == null || authedUserId !in activeCall.participants) {
                AuditLog.log(eventType = "SFU_ROOM_UNAUTHORIZED", ipAddress = call.clientAddress())
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Aktif SFU room bulunamadi"))
                return@get
            }
            val info = JanusOrchestrator.getRoomInfo(groupId, activeCall.instanceId)
            if (info == null) {
                call.respond(HttpStatusCode.NotFound, mapOf("error" to "Aktif SFU room bulunamadi"))
            } else {
                call.respond(
                    SfuRoomResponse(
                        roomId = info.roomId,
                        janusWsUrl = info.janusWsUrl,
                        status = "active",
                    ),
                )
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
            logger.info(
                "[API] FCM kayit istegi; hint_key_field={}",
                if (request.pushHintKey != null) "present" else "absent",
            )
            val hintRegistered = fcmTokenStore.registerToken(
                authedUserId,
                request.fcmToken,
                request.pushHintKey,
            )
            logger.info("[API] FCM token kaydedildi")
            logger.info("[API] FCM registration acknowledged; hint={}", hintRegistered)
            call.respond(
                HttpStatusCode.OK,
                FcmRegisterResponse("ok", hintRegistered, FcmPushSender.PUSH_CONTRACT),
            )
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
internal suspend inline fun <reified T> ApplicationCall.receiveBounded(
    maximumBytes: Int,
    ignoreUnknownKeys: Boolean = true,
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
        Json { this.ignoreUnknownKeys = ignoreUnknownKeys }
            .decodeFromString<T>(bytes.toString(Charsets.UTF_8))
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
    requirePrincipal(call)

private val authenticatedEpochKey = io.ktor.util.AttributeKey<String>("authenticated-credential-epoch")

private fun ApplicationCall.prekeyWriteEpoch(): String = attributes[authenticatedEpochKey]

/**
 * Yalniz kullanici access token'i kabul eder. Bot servis assertion'lari
 * Bot API ile birlikte kaldirildi; sunucuda baska bir principal turu yok.
 */
private suspend fun requirePrincipal(
    call: io.ktor.server.application.ApplicationCall,
): String? {
    val authHeader = call.request.headers["Authorization"]
    val token = authHeader?.removePrefix("Bearer ")?.trim()
    if (token.isNullOrBlank()) {
        call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Authorization header gerekli"))
        return null
    }
    AuthService.accessClaims(token)?.let {
        call.attributes.put(authenticatedEpochKey, it.epoch)
        return it.userId
    }
    call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Gecersiz veya expired token"))
    return null
}

/** Gecici credential durumu hatasi: istemci oturumu korur, sonra yeniden dener. */
private suspend fun ApplicationCall.respondCredentialStateUnavailable() {
    response.header("Retry-After", "30")
    respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "credential_state_unavailable"))
}

/**
 * Kayit transaction'i icinde kurtarma bagini kurar (QA 2026-10-13 R3).
 *
 * Bag kaydin onkosulu degildir: e-posta baska hesaba bagliysa, kurtarma
 * servisi yapilandirilmamissa ya da grant e-posta tasimiyorsa kayit yine
 * basarili olur ve istemci `recoveryEmailBound=false` gorur. Savepoint, bag
 * adimindaki beklenmedik bir SQL hatasinin kaydi geri almasini engeller.
 */
internal fun bindRegistrationRecoveryEmail(
    connection: java.sql.Connection,
    grant: AuthService.RegistrationGrant,
    userId: String,
): Boolean {
    val sealed = grant.sealedEmail ?: return false
    val service = AccountRecovery.service ?: return false
    val email = service.openRegistrationEmail(grant.grantId, sealed) ?: return false
    val savepoint = connection.setSavepoint()
    return try {
        service.bindAtRegistration(connection, userId, email).also { connection.releaseSavepoint(savepoint) }
    } catch (error: java.sql.SQLException) {
        connection.rollback(savepoint)
        false
    }
}
