package com.securechat.signaling

import com.securechat.signaling.db.Database
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.call
import io.ktor.server.response.header
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.micrometer.core.instrument.Counter
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.sql.Connection
import java.util.UUID
import kotlinx.serialization.Serializable
import org.slf4j.LoggerFactory

/**
 * Kotuye kullanim bildirimleri.
 *
 * Bildirim mesaj icerigi tasimaz (bkz. V25 migration). Istemci yalniz hedef
 * hesaplari, sebebi ve kisa bir notu yollar; sunucu bilinmeyen alanlari
 * reddeder ki ileride biri icerik eklemeye kalkarsa sessizce saklanmasin.
 *
 * Inceleme `REPORTS_ADMIN_TOKEN` ile korunan admin uclarindan yapilir. Token
 * tanimli degilse admin uclari hic yokmus gibi 404 doner.
 */
object AbuseReports {
    private val log = LoggerFactory.getLogger("AbuseReports")

    const val MAX_TARGETS = 32
    const val MAX_NOTE_CHARS = 500
    const val CLOSED_RETENTION_DAYS = 30
    const val MAX_RETENTION_DAYS = 180
    const val SUBMIT_RATE_BUCKET = "abuse_report"
    const val SUBMIT_BODY_LIMIT = 4_096
    private const val REPORTER_NAMESPACE = "abuse-reporter"

    val REASONS = setOf(
        "spam", "harassment", "inappropriate", "child_safety", "impersonation", "other",
    )
    val KINDS = setOf("user", "group")
    val RESOLUTIONS = setOf("no_action", "account_removed")

    private val submitted: Counter = Counter.builder("securechat_abuse_reports_total")
        .description("Alinan kotuye kullanim bildirimi sayisi (kimliksiz)")
        .register(Metrics.registry)

    fun initialize() {
        val enabled = AdminAccess.isEnabled()
        log.info("[REPORTS] Inceleme uclari {}", if (enabled) "acik" else "kapali (REPORTS_ADMIN_TOKEN yok)")
    }

    /** Sayac /metrics'te ilk bildirimden once de gorunsun (alarm kurali icin). */
    fun registerMetrics() {
        submitted
    }

    @Serializable
    data class SubmitRequest(
        val kind: String,
        val targetUserIds: List<String>,
        val reason: String,
        val note: String? = null,
    )

    @Serializable
    data class CloseRequest(val resolution: String)

    @Serializable
    data class ReportView(
        val reportId: String,
        val kind: String,
        val reason: String,
        val note: String?,
        val createdAt: String,
        val closedAt: String?,
        val resolution: String?,
        val targetUserIds: List<String>,
    )

    sealed interface Validation {
        data class Valid(
            val kind: String,
            val reason: String,
            val note: String?,
            val targets: List<String>,
        ) : Validation
        data class Invalid(val error: String) : Validation
    }

    /**
     * Govdeyi dogrular. Bilinmeyen hedefler sessizce elenir (hesap silinmis
     * olabilir); kendini bildirmek ve gecerli hedefi kalmayan bildirim
     * reddedilir.
     */
    fun validate(
        request: SubmitRequest,
        reporterId: String,
        exists: (String) -> Boolean,
    ): Validation {
        if (request.kind !in KINDS) return Validation.Invalid("invalid_kind")
        if (request.reason !in REASONS) return Validation.Invalid("invalid_reason")
        if (request.targetUserIds.isEmpty() || request.targetUserIds.size > MAX_TARGETS) {
            return Validation.Invalid("invalid_targets")
        }
        val parsed = request.targetUserIds.map { id ->
            runCatching { UUID.fromString(id).toString() }.getOrNull()
                ?: return Validation.Invalid("invalid_targets")
        }.distinct()
        val targets = parsed.filter { it != reporterId && exists(it) }
        if (targets.isEmpty()) return Validation.Invalid("unknown_targets")
        val note = request.note
            ?.replace(Regex("[\\p{Cc}&&[^\\n]]"), "")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (note != null && note.length > MAX_NOTE_CHARS) return Validation.Invalid("note_too_long")
        return Validation.Valid(request.kind, request.reason, note, targets)
    }

    fun store(report: Validation.Valid, reporterId: String): String {
        val reportId = UUID.randomUUID().toString()
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                connection.prepareStatement(
                    """INSERT INTO abuse_reports (report_id, reporter_index, kind, reason, note)
                       VALUES (?::uuid, ?, ?, ?, ?)""",
                ).use { statement ->
                    statement.setString(1, reportId)
                    statement.setString(2, ServerPrivacy.blindIndex(REPORTER_NAMESPACE, reporterId))
                    statement.setString(3, report.kind)
                    statement.setString(4, report.reason)
                    statement.setString(5, report.note)
                    statement.executeUpdate()
                }
                connection.prepareStatement(
                    "INSERT INTO abuse_report_targets (report_id, target_user_id) VALUES (?::uuid, ?::uuid)",
                ).use { statement ->
                    for (target in report.targets) {
                        statement.setString(1, reportId)
                        statement.setString(2, target)
                        statement.addBatch()
                    }
                    statement.executeBatch()
                }
                connection.commit()
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }
        submitted.increment()
        return reportId
    }

    fun list(openOnly: Boolean, limit: Int = 200): List<ReportView> =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT r.report_id, r.kind, r.reason, r.note, r.created_at, r.closed_at,
                          r.resolution,
                          COALESCE(array_agg(t.target_user_id::text ORDER BY t.target_user_id)
                                   FILTER (WHERE t.target_user_id IS NOT NULL), '{}')
                     FROM abuse_reports r
                     LEFT JOIN abuse_report_targets t ON t.report_id = r.report_id
                    WHERE (? = FALSE OR r.closed_at IS NULL)
                    GROUP BY r.report_id
                    ORDER BY r.created_at ASC
                    LIMIT ?""",
            ).use { statement ->
                statement.setBoolean(1, openOnly)
                statement.setInt(2, limit.coerceIn(1, 500))
                statement.executeQuery().use { rows ->
                    buildList {
                        while (rows.next()) {
                            @Suppress("UNCHECKED_CAST")
                            val targets = (rows.getArray(8).array as Array<String>).toList()
                            add(
                                ReportView(
                                    reportId = rows.getString(1),
                                    kind = rows.getString(2),
                                    reason = rows.getString(3),
                                    note = rows.getString(4),
                                    createdAt = rows.getTimestamp(5).toInstant().toString(),
                                    closedAt = rows.getTimestamp(6)?.toInstant()?.toString(),
                                    resolution = rows.getString(7),
                                    targetUserIds = targets,
                                ),
                            )
                        }
                    }
                }
            }
        }

    /** @return false: rapor yok veya zaten kapali. */
    fun close(reportId: String, resolution: String): Boolean {
        require(resolution in RESOLUTIONS) { "invalid resolution" }
        val id = runCatching { UUID.fromString(reportId).toString() }.getOrNull() ?: return false
        return Database.getConnection().use { connection ->
            connection.prepareStatement(
                """UPDATE abuse_reports SET closed_at = NOW(), resolution = ?
                    WHERE report_id = ?::uuid AND closed_at IS NULL""",
            ).use { statement ->
                statement.setString(1, resolution)
                statement.setString(2, id)
                statement.executeUpdate() == 1
            }
        }
    }

    /**
     * Hesap silmede cagrilir (ayni transaction). Hesabin hedef oldugu satirlar
     * gider; islem yapilacak hesap kalmamistir. Bildiren olarak actigi
     * bildirimler kalir ama bildiren baglantisi koparilir: baska bir hesaba
     * dair inceleme bildirenin ayrilmasiyla kaybolmamali.
     */
    fun deleteAccount(connection: Connection, userId: String) {
        connection.prepareStatement(
            "DELETE FROM abuse_report_targets WHERE target_user_id = ?::uuid",
        ).use { statement ->
            statement.setString(1, userId)
            statement.executeUpdate()
        }
        connection.prepareStatement(
            "UPDATE abuse_reports SET reporter_index = NULL WHERE reporter_index = ?",
        ).use { statement ->
            statement.setString(1, ServerPrivacy.blindIndex(REPORTER_NAMESPACE, userId))
            statement.executeUpdate()
        }
    }

    /** Kapanmis bildirimler 30 gunde, hicbiri 180 gunden uzun tutulmaz. */
    fun purgeExpired(connection: Connection): Int =
        connection.prepareStatement(
            """DELETE FROM abuse_reports
                WHERE (closed_at IS NOT NULL AND closed_at < NOW() - (? * INTERVAL '1 day'))
                   OR created_at < NOW() - (? * INTERVAL '1 day')""",
        ).use { statement ->
            statement.setInt(1, CLOSED_RETENTION_DAYS)
            statement.setInt(2, MAX_RETENTION_DAYS)
            statement.executeUpdate()
        }

    internal object AdminAccess {
        private val token: ByteArray? by lazy {
            SecretSource.optional("REPORTS_ADMIN_TOKEN")?.let { value ->
                require(value.length >= 32) { "REPORTS_ADMIN_TOKEN en az 32 karakter olmali" }
                value.toByteArray(StandardCharsets.UTF_8)
            }
        }

        fun isEnabled(): Boolean = token != null

        fun isAuthorized(authorization: String?): Boolean {
            val expected = token ?: return false
            val candidate = authorization
                ?.takeIf { it.startsWith("Bearer ") }
                ?.removePrefix("Bearer ")
                ?.toByteArray(StandardCharsets.UTF_8)
                ?: return false
            return MessageDigest.isEqual(expected, candidate)
        }
    }

    /** Admin ucu: yetkisizse 404 ile varligini bile acik etmez. */
    suspend fun requireAdmin(call: ApplicationCall): Boolean {
        if (AdminAccess.isAuthorized(call.request.headers["Authorization"])) return true
        if (AdminAccess.isEnabled()) AuditLog.log(eventType = "REPORTS_ADMIN_REJECTED")
        call.respond(HttpStatusCode.NotFound)
        return false
    }

    internal fun logClosed(resolution: String) {
        log.info("[REPORTS] Bildirim kapatildi: {}", resolution)
    }
}

/**
 * Bildirim uclari. `requireAuth` HttpRoutes'taki kullanici token
 * dogrulamasidir; servis assertion'i burada kabul edilmez. Adi bilerek
 * aynidir: sozlesme denetimi guard'i route govdesindeki cagridan okur.
 */
fun Route.abuseReportRoutes(
    requireAuth: suspend (ApplicationCall) -> String?,
    userRegistry: UserRegistry,
    removeAccount: suspend (String) -> Unit,
) {
    AbuseReports.registerMetrics()
    post("/api/v1/reports") {
        val reporterId = requireAuth(call) ?: return@post
        if (!RateLimiter.allow(AbuseReports.SUBMIT_RATE_BUCKET, reporterId)) {
            val retry = RateLimiter.retryAfter(AbuseReports.SUBMIT_RATE_BUCKET, reporterId)
            call.response.header("Retry-After", retry.toString())
            call.respond(HttpStatusCode.TooManyRequests, mapOf("error" to "Rate limit asildi"))
            return@post
        }
        val request = call.receiveBounded<AbuseReports.SubmitRequest>(
            maximumBytes = AbuseReports.SUBMIT_BODY_LIMIT,
            ignoreUnknownKeys = false,
        ) ?: return@post
        when (val result = AbuseReports.validate(request, reporterId, userRegistry::exists)) {
            is AbuseReports.Validation.Invalid ->
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to result.error))
            is AbuseReports.Validation.Valid -> {
                AbuseReports.store(result, reporterId)
                AuditLog.log(eventType = "ABUSE_REPORT_RECEIVED")
                call.respond(HttpStatusCode.Accepted, mapOf("status" to "received"))
            }
        }
    }

    get("/api/v1/admin/reports") {
        if (!AbuseReports.requireAdmin(call)) return@get
        val openOnly = call.request.queryParameters["status"] != "all"
        call.respond(HttpStatusCode.OK, AbuseReports.list(openOnly))
    }

    post("/api/v1/admin/reports/{reportId}/close") {
        if (!AbuseReports.requireAdmin(call)) return@post
        val body = call.receiveBounded<AbuseReports.CloseRequest>(maximumBytes = 256) ?: return@post
        if (body.resolution !in AbuseReports.RESOLUTIONS) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_resolution"))
            return@post
        }
        val closed = AbuseReports.close(call.parameters["reportId"].orEmpty(), body.resolution)
        if (!closed) {
            call.respond(HttpStatusCode.NotFound, mapOf("error" to "report_not_open"))
            return@post
        }
        AbuseReports.logClosed(body.resolution)
        call.respond(HttpStatusCode.OK, mapOf("status" to "closed"))
    }

    // Moderasyon karari: hesabi kullanicinin kendi silme yoluyla ayni sekilde
    // kaldirir (kalici kayit + gecici kopyalar).
    post("/api/v1/admin/accounts/{userId}/remove") {
        if (!AbuseReports.requireAdmin(call)) return@post
        val userId = runCatching { UUID.fromString(call.parameters["userId"]).toString() }.getOrNull()
        if (userId == null) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_user"))
            return@post
        }
        removeAccount(userId)
        AuditLog.log(eventType = "ACCOUNT_REMOVED_BY_MODERATION")
        call.respond(HttpStatusCode.OK, mapOf("status" to "removed"))
    }
}
