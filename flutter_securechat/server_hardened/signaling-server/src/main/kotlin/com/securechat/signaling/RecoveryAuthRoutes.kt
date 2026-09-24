package com.securechat.signaling

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.post
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal object AccountRecovery {
    // Bounded in-memory mail dispatch keeps SMTP latency/failure out of preauth responses.
    private val mail = ThreadPoolExecutor(2, 2, 0, TimeUnit.SECONDS, ArrayBlockingQueue(64),
        { task -> Thread(task, "recovery-mail").apply { isDaemon = true } }, ThreadPoolExecutor.DiscardPolicy())
    val service: RecoveryAuthService? by lazy {
        RecoveryRecordCipher.configured()?.let { cipher ->
            RecoveryAuthService(cipher) { email, otp, purpose ->
                mail.execute {
                    val label = if (purpose == "enroll") "recovery email enrollment" else "account recovery"
                    EmailService.sendMail(email, "SecureChat $label", "<p>Your $label code: <b>$otp</b></p><p>Expires in 10 minutes.</p>",
                        "Your $label code: $otp. Expires in 10 minutes.")
                }
            }
        }
    }

    fun deleteAccount(connection: java.sql.Connection, userId: String) {
        val configured = service
        if (configured != null) configured.deleteAccount(connection, userId)
        else connection.createStatement().use { statement ->
            statement.executeQuery("SELECT EXISTS(SELECT 1 FROM account_recovery_bindings UNION ALL SELECT 1 FROM account_recovery_challenges UNION ALL SELECT 1 FROM account_recovery_receipts)").use {
                check(it.next() && !it.getBoolean(1)) { "Recovery secrets required to delete protected account data" }
            }
        }
    }

    fun purgeExpired(connection: java.sql.Connection) {
        for (table in listOf("account_recovery_challenges", "account_recovery_quotas", "account_recovery_receipts")) {
            connection.createStatement().use { it.executeUpdate("DELETE FROM $table WHERE expires_at <= NOW()") }
        }
    }
}

internal fun Route.recoveryAuthRoutes() {
    post("/api/v1/account/recovery-email/status") {
        call.recoveryEndpoint("recovery_verify") { service ->
            val principal = call.recoveryPrincipal() ?: return@recoveryEndpoint
            call.receiveBounded<kotlinx.serialization.json.JsonObject>(4096, false) ?: return@recoveryEndpoint
            call.respond(mapOf("bound" to withContext(Dispatchers.IO) { service.enrolled(principal.first, principal.second) }))
        }
    }
    post("/api/v1/account/recovery-email/request") {
        call.recoveryEndpoint("recovery_request") { service ->
            val principal = call.recoveryPrincipal() ?: return@recoveryEndpoint
            val request = call.receiveBounded<RecoveryRequest>(4096, false) ?: return@recoveryEndpoint
            val result = withContext(Dispatchers.IO) { service.requestEnrollment(principal.first, principal.second, request.email) }
            if (result == null) call.recoveryRejected() else call.respond(result)
        }
    }
    post("/api/v1/account/recovery-email/verify") {
        call.recoveryEndpoint("recovery_verify") { service ->
            val principal = call.recoveryPrincipal() ?: return@recoveryEndpoint
            val request = call.receiveBounded<RecoveryVerify>(4096, false) ?: return@recoveryEndpoint
            val success = withContext(Dispatchers.IO) { service.verifyEnrollment(principal.first, principal.second, request) }
            if (!success) call.recoveryRejected() else call.respond(mapOf("status" to "ok"))
        }
    }
    post("/api/v1/auth/login/request") {
        call.recoveryEndpoint("recovery_request") { service ->
            val request = call.receiveBounded<RecoveryRequest>(4096, false) ?: return@recoveryEndpoint
            val result = recoveryPreauth { service.requestLogin(request.email) }
            call.respond(result)
        }
    }
    post("/api/v1/auth/login/verify") {
        call.recoveryEndpoint("recovery_verify") { service ->
            val request = call.receiveBounded<RecoveryVerify>(4096, false) ?: return@recoveryEndpoint
            val result = recoveryPreauth { service.verifyLogin(request) }
            if (result == null) call.recoveryRejected() else call.respond(result)
        }
    }
    post("/api/v1/auth/login/complete") {
        call.recoveryEndpoint("recovery_complete") { service ->
            val request = call.receiveBounded<RecoveryComplete>(4096, false) ?: return@recoveryEndpoint
            val result = recoveryPreauth { service.complete(request) }
            if (result == null) call.recoveryRejected() else call.respond(result)
        }
    }
}

private suspend fun <T> recoveryPreauth(action: () -> T): T {
    val started = System.nanoTime()
    try {
        return withContext(Dispatchers.IO) { action() }
    } finally {
        // Mask normal bound/decoy lookup differences; SMTP never runs on this path.
        val floor = 300L + java.util.concurrent.ThreadLocalRandom.current().nextLong(100)
        val remaining = floor - (System.nanoTime() - started) / 1_000_000
        if (remaining > 0) kotlinx.coroutines.delay(remaining)
    }
}

private suspend fun ApplicationCall.recoveryPrincipal(): Pair<String, String>? {
    val token = request.headers["Authorization"]?.removePrefix("Bearer ")?.trim().orEmpty()
    val claims = AuthService.accessClaims(token)
    if (claims == null) {
        respond(HttpStatusCode.Unauthorized, mapOf("error" to "unauthorized"))
        return null
    }
    return claims.userId to claims.epoch
}

private suspend fun ApplicationCall.recoveryRejected() =
    respond(HttpStatusCode.BadRequest, mapOf("error" to "recovery_rejected"))

private suspend fun ApplicationCall.recoveryEndpoint(limit: String, action: suspend (RecoveryAuthService) -> Unit) {
    response.headers.append("Cache-Control", "no-store")
    val service = try { AccountRecovery.service } catch (_: Exception) { null }
    if (service == null) {
        respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "recovery_unavailable"))
        return
    }
    try {
        if (!RateLimiter.allow(limit, clientAddress())) {
            respond(HttpStatusCode.TooManyRequests, mapOf("error" to "rate_limited"))
        } else action(service)
    } catch (_: IllegalArgumentException) {
        recoveryRejected()
    } catch (cancelled: kotlinx.coroutines.CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "recovery_unavailable"))
    }
}
