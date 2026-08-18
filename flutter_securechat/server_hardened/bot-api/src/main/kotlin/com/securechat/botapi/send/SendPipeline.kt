package com.securechat.botapi.send

import com.securechat.botapi.audit.BotAuditLog
import com.securechat.botapi.auth.ClientKeyCache
import com.securechat.botapi.auth.EdDsaJwtVerifier
import com.securechat.botapi.delivery.SignalingWsClient
import com.securechat.botapi.health.BotMetrics
import com.securechat.botapi.signal.BotIdentity
import com.securechat.botapi.signal.BotServiceTokenMinter
import com.securechat.botapi.signal.PgSignalProtocolStore
import com.securechat.botapi.signal.PreKeyBundleFetcher
import com.securechat.botapi.signal.SignalEncryptor
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.util.toByteArray
import io.ktor.utils.io.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.slf4j.LoggerFactory
import java.util.Base64
import java.util.UUID

private val log = LoggerFactory.getLogger("SendPipeline")

/**
 * POST /v1/send ana orchestration.
 *
 * Adimlar:
 *  1. Body bytes oku (body_hash icin)
 *  2. EdDSA JWT verify (auth + replay + body integrity)
 *  3. EmergencyStop check
 *  4. Body parse + recipient extraction
 *  5. AllowListChecker
 *  6. RateLimitGuard (3 katman)
 *  7. IdempotencyStore checkAndReserve
 *  8. Signal encrypt + WS send (group ise per-member fan-out)
 *  9. Result cache, 202 Accepted
 *
 * Hata yollarinda PENDING release edilir ki script ayni key ile retry edebilsin.
 */
class SendPipeline {

    private val json = Json { ignoreUnknownKeys = true }
    private val verifier = EdDsaJwtVerifier { kid -> ClientKeyCache.get(kid) }
    private val store = PgSignalProtocolStore()
    private val encryptor = SignalEncryptor(store)
    private val bundleFetcher = PreKeyBundleFetcher {
        BotServiceTokenMinter.issue(
            BotIdentity.get().botUserId,
            BotServiceTokenMinter.Scope.PREKEY_FETCH,
        )
    }

    suspend fun handle(call: ApplicationCall) {
        // 1) Body bytes
        val bodyBytes = call.receiveChannel().toByteArray()

        // 2) JWT verify
        val bearer = call.request.header("Authorization")?.removePrefix("Bearer ")?.trim()
        if (bearer.isNullOrBlank()) {
            BotMetrics.authFailed.increment()
            call.respond(HttpStatusCode.Unauthorized, mapOf("error" to "Authorization Bearer zorunlu"))
            return
        }
        val verifyResult = verifier.verify(bearer, bodyBytes)
        if (verifyResult is EdDsaJwtVerifier.Result.Fail) {
            BotMetrics.authFailed.increment()
            BotMetrics.authFailReason(verifyResult.reason.name).increment()
            if (verifyResult.reason == EdDsaJwtVerifier.Reason.REPLAYED_JTI) {
                BotMetrics.replayBlocked.increment()
                BotAuditLog.log("BOT_API_AUTH_REPLAY_REJECTED", metadata = mapOf("reason" to verifyResult.reason.name))
            } else {
                BotAuditLog.log("BOT_API_AUTH_INVALID_JWT", metadata = mapOf("reason" to verifyResult.reason.name))
            }
            call.respond(HttpStatusCode.Unauthorized, mapOf(
                "error" to "auth_failed",
                "reason" to verifyResult.reason.name
            ))
            return
        }
        val authed = (verifyResult as EdDsaJwtVerifier.Result.Ok).client

        // 3) Emergency stop
        if (EmergencyStopFlag.isTripped()) {
            BotMetrics.emergencyStopHit.increment()
            BotAuditLog.log("BOT_API_EMERGENCY_STOP_TRIPPED")
            call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "emergency_stop"))
            return
        }

        // 4) Body parse
        val payload = try {
            json.decodeFromString<SendRequest>(bodyBytes.toString(Charsets.UTF_8))
        } catch (_: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "json_parse_failed"))
            return
        }
        if (payload.recipientRef.isBlank() || payload.plaintextBase64.isBlank()) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "recipientRef + plaintextBase64 zorunlu"))
            return
        }
        val fanoutCost = when {
            payload.recipientRef.startsWith("user:") &&
                payload.recipientUserIds.isEmpty() &&
                runCatching {
                    UUID.fromString(payload.recipientRef.removePrefix("user:"))
                }.isSuccess -> 1
            payload.recipientRef.startsWith("group:") &&
                payload.recipientRef.removePrefix("group:")
                    .matches(Regex("^[A-Za-z0-9_-]{43}=?$")) &&
                payload.recipientUserIds.isNotEmpty() &&
                payload.recipientUserIds.size <= 256 &&
                payload.recipientUserIds.distinct().size == payload.recipientUserIds.size &&
                payload.recipientUserIds.all { runCatching { UUID.fromString(it) }.isSuccess } ->
                payload.recipientUserIds.size
            else -> {
                call.respond(HttpStatusCode.BadRequest, mapOf("error" to "invalid_private_routing"))
                return
            }
        }

        val idemKey = call.request.header("X-Idempotency-Key")
        if (idemKey.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "X-Idempotency-Key header zorunlu"))
            return
        }

        // 5) Allow-list — grup tokeni tek basina yetki degildir.
        if (!AllowListChecker.isAllowed(authed, payload.recipientRef)) {
            log.info("[Send] Allow-list tarafindan reddedildi")
            BotAuditLog.log("BOT_API_ALLOWLIST_DENIED")
            call.respond(HttpStatusCode.Forbidden, mapOf("error" to "recipient_not_allowed"))
            return
        }
        // Grup fanout'unda her alici ayrica izinli olmalidir; aksi halde
        // izinli bir grup tokenini bilen client istedigi UUID'ye mesaj
        // gonderebilirdi.
        if (payload.recipientRef.startsWith("group:") &&
            !AllowListChecker.areRecipientsAllowed(authed, payload.recipientUserIds)
        ) {
            log.info("[Send] Grup alicisi allow-list disinda")
            BotAuditLog.log("BOT_API_ALLOWLIST_DENIED")
            call.respond(HttpStatusCode.Forbidden, mapOf("error" to "recipient_not_allowed"))
            return
        }

        // 6) Rate limit
        val rl = RateLimitGuard.check(authed, payload.recipientRef, fanoutCost)
        if (!rl.allowed) {
            BotMetrics.rateLimitHit.increment()
            BotAuditLog.log("BOT_API_RATE_LIMIT_HIT",
                metadata = mapOf("kid" to authed.kid, "layer" to (rl.reason ?: "unknown")))
            call.response.header("Retry-After", rl.retryAfterSeconds.toString())
            call.respond(HttpStatusCode.TooManyRequests, mapOf(
                "error" to "rate_limit",
                "layer" to (rl.reason ?: "unknown"),
                "retry_after_seconds" to rl.retryAfterSeconds
            ))
            return
        }

        // 7) Idempotency
        when (val cached = IdempotencyStore.checkAndReserve(authed.clientId, idemKey)) {
            is IdempotencyStore.CheckResult.Cached -> {
                call.respondText(cached.responseJson, ContentType.Application.Json, HttpStatusCode.OK)
                return
            }
            IdempotencyStore.CheckResult.Pending -> {
                call.respond(HttpStatusCode.Conflict, mapOf("error" to "idempotency_pending"))
                return
            }
            IdempotencyStore.CheckResult.Fresh -> { /* devam */ }
        }

        // 8) Encrypt + send
        try {
            val plaintext = Base64.getDecoder().decode(payload.plaintextBase64)
            val messageId = UUID.randomUUID().toString()
            val sent = dispatchEncryptedSend(
                payload.recipientRef,
                payload.recipientUserIds,
                plaintext,
                payload.messageType ?: "text"
            )
            if (!sent) {
                IdempotencyStore.release(authed.clientId, idemKey)
                BotMetrics.sendFailed.increment()
                call.respond(HttpStatusCode.BadGateway, mapOf("error" to "delivery_failed"))
                return
            }

            // 9) Cache result + 202
            val responseJson = json.encodeToString(SendResponse(messageId = messageId, status = "queued"))
            IdempotencyStore.storeResult(authed.clientId, idemKey, responseJson)
            BotMetrics.sendAccepted.increment()
            BotAuditLog.log("BOT_API_SEND_ACCEPTED")
            log.info("[Send] Sifreli gonderim kabul edildi")
            call.respondText(responseJson, ContentType.Application.Json, HttpStatusCode.Accepted)
        } catch (e: Exception) {
            IdempotencyStore.release(authed.clientId, idemKey)
            BotMetrics.sendFailed.increment()
            BotAuditLog.log(
                "BOT_API_SEND_FAILED",
                metadata = mapOf("reason" to e.javaClass.simpleName)
            )
            log.warn("[Send] Sifreli gonderim hatasi: {}", e.javaClass.simpleName)
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "send_error"))
        }
    }

    /**
     * recipientRef: "user:<uuid>" veya "group:<opaque-routing-token>".
     * Grup hedefleri yalnizca bu request'te tasinir; log/DB/Redis'e yazilmaz.
     */
    private fun dispatchEncryptedSend(
        recipientRef: String,
        recipientUserIds: List<String>,
        plaintext: ByteArray,
        messageType: String
    ): Boolean {
        return when {
            recipientRef.startsWith("user:") -> {
                if (recipientUserIds.isNotEmpty()) return false
                val userId = recipientRef.removePrefix("user:")
                encryptAndSend(userId, plaintext, messageType)
            }
            recipientRef.startsWith("group:") -> {
                val routingToken = recipientRef.removePrefix("group:")
                val members = recipientUserIds
                    .distinct()
                    .filter { it != BotIdentity.get().botUserId }
                val valid = routingToken.matches(Regex("^[A-Za-z0-9_-]{43}=?$")) &&
                    members.isNotEmpty() &&
                    members.size <= 256 &&
                    members.size == recipientUserIds.size &&
                    members.all { runCatching { UUID.fromString(it) }.isSuccess }
                if (!valid) {
                    log.warn("[Send] Gecersiz ephemeral grup routing paketi")
                    return false
                }
                var allOk = true
                for (member in members) {
                    val ok = try {
                        encryptAndSend(member, plaintext, messageType)
                    } catch (e: Exception) {
                        log.warn("[Send] Grup uye gonderim hatasi: {}", e.javaClass.simpleName)
                        false
                    }
                    if (!ok) allOk = false
                }
                allOk
            }
            else -> false
        }
    }

    /**
     * Alici basina serilestirme kilitleri.
     *
     * Signal ratchet'i yukle-ilerlet-yaz dizisidir. Ayni aliciya es zamanli
     * iki gonderim bu diziyi ic ice calistirirsa bir adim kaybolur ve alici o
     * mesaji hicbir zaman cozemez. Kilit, dizinin tamamini tek parca yapar.
     *
     * Kilit process icidir; birden fazla bot instance'i calistirilirsa
     * korumayi `PgSignalProtocolStore` icindeki compare-and-set saglar ve
     * cakisma sessizce degil hata ile sonuclanir.
     */
    // Sabit boyut social-graph kimliklerini process omru boyunca biriktirmez.
    // Hash cakismasi yalniz ilgisiz iki gonderimi kisa sure serilestirir.
    private val recipientLocks = Array(256) { Any() }

    private fun recipientLock(recipientUserId: String): Any =
        recipientLocks[(recipientUserId.hashCode() and Int.MAX_VALUE) % recipientLocks.size]

    private fun encryptAndSend(
        recipientUserId: String,
        plaintext: ByteArray,
        messageType: String
    ): Boolean = synchronized(recipientLock(recipientUserId)) {
        encryptAndSendLocked(recipientUserId, plaintext, messageType)
    }

    private fun encryptAndSendLocked(
        recipientUserId: String,
        plaintext: ByteArray,
        messageType: String
    ): Boolean {
        val address = org.whispersystems.libsignal.SignalProtocolAddress(
            recipientUserId, PreKeyBundleFetcher.DEFAULT_DEVICE_ID
        )
        if (!store.containsSession(address)) {
            val bundle = bundleFetcher.fetch(recipientUserId) ?: run {
                log.warn("[Send] Recipient icin prekey bundle alinamadi")
                return false
            }
            encryptor.ensureSession(recipientUserId, PreKeyBundleFetcher.DEFAULT_DEVICE_ID, bundle)
        }
        val envelope = encryptor.encrypt(recipientUserId, PreKeyBundleFetcher.DEFAULT_DEVICE_ID, plaintext)
        val wsPayload = buildEncryptedMessageJson(
            recipient = recipientUserId,
            // Her alici icin bagimsiz dis kimlik: ayni messageId tum uyelere
            // gidince fanout signaling katmaninda dogrudan linklenebiliyordu.
            messageId = UUID.randomUUID().toString(),
            messageType = messageType,
            envelope = envelope
        )
        return SignalingWsClient.send(wsPayload)
    }

    /**
     * Wire zarfi typed serializer ile kurulur. Onceki string interpolasyonu
     * istekten gelen `messageType` degerini dogrudan JSON'a gomuyordu ve
     * kacis karakterleriyle frame kurcalanabiliyordu.
     */
    private fun buildEncryptedMessageJson(
        recipient: String,
        messageId: String,
        messageType: String,
        envelope: SignalEncryptor.EncryptedEnvelope
    ): String = buildJsonObject {
        put("type", "encrypted_message")
        put("senderId", BotIdentity.get().botUserId)
        put("recipientId", recipient)
        put("messageId", messageId)
        put("messageType", messageType)
        put("timestamp", System.currentTimeMillis())
        put("signalType", envelope.type)
        put("ciphertext", Base64.getEncoder().encodeToString(envelope.ciphertext))
    }.toString()

    @Serializable
    private data class SendRequest(
        val recipientRef: String,         // "user:<uuid>" or "group:<opaque-token>"
        val plaintextBase64: String,      // base64-encoded plaintext bytes
        val messageType: String? = null,  // "text" (default), "image", ...
        val recipientUserIds: List<String> = emptyList()
    )

    @Serializable
    private data class SendResponse(val messageId: String, val status: String)
}
