package com.securechat.botapi.send

import com.securechat.botapi.audit.BotAuditLog
import com.securechat.botapi.auth.ClientKeyCache
import com.securechat.botapi.auth.EdDsaJwtVerifier
import com.securechat.botapi.delivery.SignalingWsClient
import com.securechat.botapi.health.BotMetrics
import com.securechat.botapi.signal.BotIdentity
import com.securechat.botapi.signal.BotJwtMinter
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
    private val bundleFetcher = PreKeyBundleFetcher { BotJwtMinter.issueAccessToken(BotIdentity.get().botUserId) }

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
            BotAuditLog.log("BOT_API_EMERGENCY_STOP_TRIPPED",
                metadata = mapOf("kid" to authed.kid))
            call.respond(HttpStatusCode.ServiceUnavailable, mapOf("error" to "emergency_stop"))
            return
        }

        // 4) Body parse
        val payload = try {
            json.decodeFromString<SendRequest>(bodyBytes.toString(Charsets.UTF_8))
        } catch (e: Exception) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "json_parse: ${e.message}"))
            return
        }
        if (payload.recipientRef.isBlank() || payload.plaintextBase64.isBlank()) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "recipientRef + plaintextBase64 zorunlu"))
            return
        }

        val idemKey = call.request.header("X-Idempotency-Key")
        if (idemKey.isNullOrBlank()) {
            call.respond(HttpStatusCode.BadRequest, mapOf("error" to "X-Idempotency-Key header zorunlu"))
            return
        }

        // 5) Allow-list
        if (!AllowListChecker.isAllowed(authed, payload.recipientRef)) {
            log.info("[Send] DENIED — kid={}, recipient={}", authed.kid, payload.recipientRef)
            BotAuditLog.log("BOT_API_ALLOWLIST_DENIED",
                metadata = mapOf("kid" to authed.kid, "recipient" to payload.recipientRef))
            call.respond(HttpStatusCode.Forbidden, mapOf("error" to "recipient_not_allowed"))
            return
        }

        // 6) Rate limit
        val rl = RateLimitGuard.check(authed, payload.recipientRef)
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
            val sent = dispatchEncryptedSend(payload.recipientRef, plaintext, messageId, payload.messageType ?: "text")
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
            BotAuditLog.log("BOT_API_SEND_ACCEPTED",
                metadata = mapOf("kid" to authed.kid, "recipient" to payload.recipientRef, "messageId" to messageId))
            log.info("[Send] OK — kid={}, recipient={}, messageId={}", authed.kid, payload.recipientRef, messageId)
            call.respondText(responseJson, ContentType.Application.Json, HttpStatusCode.Accepted)
        } catch (e: Exception) {
            IdempotencyStore.release(authed.clientId, idemKey)
            BotMetrics.sendFailed.increment()
            BotAuditLog.log("BOT_API_SEND_FAILED",
                metadata = mapOf("kid" to authed.kid, "recipient" to payload.recipientRef,
                    "error" to (e.message ?: "unknown")))
            log.warn("[Send] HATA — kid={}, recipient={}", authed.kid, payload.recipientRef, e)
            call.respond(HttpStatusCode.InternalServerError, mapOf("error" to "send_error", "detail" to (e.message ?: "")))
        }
    }

    /**
     * recipientRef: "user:<uuid>" veya "group:<groupId>"
     * Group ise grup uyelerini cek (GroupMemberStore signaling-server'da — bot bu DB'ye direkt erisemez,
     * v1 icin: signaling-server'a kucuk bir internal endpoint eklemek gerekiyor VEYA postgres'e direkt
     * SELECT atilir — bot ayni DB user'i kullaniyor. v1: direkt SELECT.
     */
    private fun dispatchEncryptedSend(
        recipientRef: String,
        plaintext: ByteArray,
        messageId: String,
        messageType: String
    ): Boolean {
        return when {
            recipientRef.startsWith("user:") -> {
                val userId = recipientRef.removePrefix("user:")
                encryptAndSend(userId, plaintext, messageId, messageType)
            }
            recipientRef.startsWith("group:") -> {
                val groupId = recipientRef.removePrefix("group:")
                val members = fetchGroupMembers(groupId).filter { it != BotIdentity.get().botUserId }
                if (members.isEmpty()) {
                    log.warn("[Send] Grup uye yok: {}", groupId)
                    return false
                }
                var allOk = true
                for (member in members) {
                    val ok = try {
                        encryptAndSend(member, plaintext, messageId, messageType, groupId = groupId)
                    } catch (e: Exception) {
                        log.warn("[Send] Uye {} icin hata: {}", member, e.message)
                        false
                    }
                    if (!ok) allOk = false
                }
                allOk
            }
            else -> false
        }
    }

    private fun encryptAndSend(
        recipientUserId: String,
        plaintext: ByteArray,
        messageId: String,
        messageType: String,
        groupId: String? = null
    ): Boolean {
        val address = org.whispersystems.libsignal.SignalProtocolAddress(
            recipientUserId, PreKeyBundleFetcher.DEFAULT_DEVICE_ID
        )
        if (!store.containsSession(address)) {
            val bundle = bundleFetcher.fetch(recipientUserId) ?: run {
                log.warn("[Send] Recipient {} icin prekey bundle alinamadi", recipientUserId)
                return false
            }
            encryptor.ensureSession(recipientUserId, PreKeyBundleFetcher.DEFAULT_DEVICE_ID, bundle)
        }
        val envelope = encryptor.encrypt(recipientUserId, PreKeyBundleFetcher.DEFAULT_DEVICE_ID, plaintext)
        val wsPayload = buildEncryptedMessageJson(
            recipient = recipientUserId,
            messageId = messageId,
            messageType = messageType,
            envelope = envelope,
            groupId = groupId
        )
        return SignalingWsClient.send(wsPayload)
    }

    private fun buildEncryptedMessageJson(
        recipient: String,
        messageId: String,
        messageType: String,
        envelope: SignalEncryptor.EncryptedEnvelope,
        groupId: String?
    ): String {
        val ctB64 = Base64.getEncoder().encodeToString(envelope.ciphertext)
        val sender = BotIdentity.get().botUserId
        val ts = System.currentTimeMillis()
        val groupField = if (groupId != null) ""","groupId":"$groupId"""" else ""
        return """{"type":"encrypted_message","senderId":"$sender","recipientId":"$recipient",""" +
            """"messageId":"$messageId","messageType":"$messageType","timestamp":$ts,""" +
            """"signalType":${envelope.type},"ciphertext":"$ctB64"$groupField}"""
    }

    /**
     * Group uyelerini cek — signaling-server'in group_members tablosundan.
     * Bot ayni DB user'i ile baglandigi icin direkt SELECT mumkun.
     */
    private fun fetchGroupMembers(groupId: String): List<String> {
        val out = mutableListOf<String>()
        com.securechat.botapi.db.BotDatabase.getConnection().use { conn ->
            conn.prepareStatement("SELECT user_id FROM group_members WHERE group_id = ?").use { stmt ->
                stmt.setString(1, groupId)
                stmt.executeQuery().use { rs ->
                    while (rs.next()) {
                        out += rs.getObject("user_id", UUID::class.java).toString()
                    }
                }
            }
        }
        return out
    }

    @Serializable
    private data class SendRequest(
        val recipientRef: String,         // "user:<uuid>" or "group:<id>"
        val plaintextBase64: String,      // base64-encoded plaintext bytes
        val messageType: String? = null   // "text" (default), "image", ...
    )

    @Serializable
    private data class SendResponse(val messageId: String, val status: String)
}
