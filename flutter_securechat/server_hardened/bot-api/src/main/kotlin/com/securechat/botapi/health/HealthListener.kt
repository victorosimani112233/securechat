package com.securechat.botapi.health

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.signal.BotIdentity
import com.securechat.botapi.delivery.SignalingWsClient
import com.securechat.botapi.delivery.OutboundQueue
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.db.BotRedisManager
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import org.slf4j.LoggerFactory
import java.nio.charset.StandardCharsets
import java.security.MessageDigest

private val log = LoggerFactory.getLogger("HealthListener")

/**
 * 127.0.0.1:<healthPort> uzerinde calisan TCP listener.
 *  - GET /health   — basit canlilik kontrolu (DB + Redis ping)
 *  - GET /metrics  — Prometheus scrape endpoint
 *
 * Sadece localhost'a bind edilir — Prometheus container'i ayni Docker
 * network uzerinden eriste de, host disindan ulasilamaz (compose
 * "ports:" alaninda expose EDILMEZ).
 */
object HealthListener {

    /** Bu derinligin ustunde bot teslimatta geride kalmis sayilir. */
    private const val MAX_READY_QUEUE_DEPTH = 500L

    fun start(): NettyApplicationEngine {
        val server = embeddedServer(Netty, host = "0.0.0.0", port = BotApiConfig.healthPort) {
            routing {
                // Liveness: process ayakta mi. Bagimliliklara bakmaz ki gecici
                // bir Redis kesintisi container'i yeniden baslatmasin.
                get("/health") {
                    call.respondText(
                        """{"status":"ok"}""",
                        ContentType.Application.Json,
                    )
                }

                /**
                 * Readiness: bot gercekten gonderim yapabilir mi.
                 *
                 * Onceki `/health` yalniz DB ve Redis'e bakiyordu; identity
                 * saglanmamis, signaling baglantisi kopmus veya kuyruk
                 * birikmis bir bot da "ok" gorunuyordu.
                 */
                get("/ready") {
                    val dbOk = BotDatabase.isHealthy()
                    val redisOk = BotRedisManager.isHealthy()
                    val identityOk = BotIdentity.isReady()
                    val signalingOk = SignalingWsClient.isConnected()
                    val queueDepth = if (identityOk && redisOk) {
                        runCatching { OutboundQueue.size(BotIdentity.get().botUserId) }
                            .getOrDefault(-1L)
                    } else {
                        -1L
                    }
                    val ready = isReady(dbOk, redisOk, identityOk, signalingOk, queueDepth)
                    val body = buildJsonObject {
                        put("status", if (ready) "ready" else "not_ready")
                        put("db", dbOk)
                        put("redis", redisOk)
                        put("identity", identityOk)
                        put("signaling", signalingOk)
                        put("queueDepth", queueDepth)
                    }.toString()
                    call.respondText(
                        body,
                        ContentType.Application.Json,
                        if (ready) HttpStatusCode.OK else HttpStatusCode.ServiceUnavailable,
                    )
                }
                get("/metrics") {
                    if (!metricsAuthorized(call.request.headers["Authorization"])) {
                        call.respondText(
                            """{"error":"unauthorized"}""",
                            ContentType.Application.Json,
                            HttpStatusCode.Unauthorized
                        )
                        return@get
                    }
                    call.respondText(BotMetrics.registry.scrape(), ContentType.Text.Plain)
                }
            }
        }.start(wait = false)
        log.info("[HealthListener] http://0.0.0.0:{}/health,/metrics", BotApiConfig.healthPort)
        return server
    }

    /**
     * Readiness karari.
     *
     * Onceki `/health` yalniz DB ve Redis'e bakiyordu: identity saglanmamis,
     * signaling baglantisi kopmus ya da kuyrugu birikmis bir bot da "ok"
     * gorunuyordu — yani gonderim yapamayan bir process trafige aciliyordu.
     * `queueDepth < 0` "olculemedi" demektir ve hazir sayilmaz.
     */
    internal fun isReady(
        dbOk: Boolean,
        redisOk: Boolean,
        identityOk: Boolean,
        signalingOk: Boolean,
        queueDepth: Long,
    ): Boolean = dbOk && redisOk && identityOk && signalingOk &&
        queueDepth in 0..MAX_READY_QUEUE_DEPTH

    internal const val READY_QUEUE_DEPTH_LIMIT = MAX_READY_QUEUE_DEPTH

    internal fun metricsAuthorized(authorization: String?): Boolean {
        val candidate = authorization
            ?.takeIf { it.startsWith("Bearer ") }
            ?.removePrefix("Bearer ")
            ?.toByteArray(StandardCharsets.UTF_8)
            ?: return false
        return MessageDigest.isEqual(BotApiConfig.metricsBearerToken, candidate)
    }
}
