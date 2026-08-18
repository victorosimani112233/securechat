package com.securechat.signaling

import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class PrivacyConfig(
    val indexKey: ByteArray,
    val offlineQueueEncryptionKey: ByteArray,
    val offlineQueueTtlSeconds: Long,
    val offlineFileTtlSeconds: Long,
    val consumedPreKeyRetentionHours: Int,
    val pushTokenRetentionDays: Int,
    val apiClientRetentionDays: Int,
    val turnCredentialTtlSeconds: Long,
    val allowLegacyPlaintextQueue: Boolean
) {
    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): PrivacyConfig {
            val indexKey = requiredKey(environment, "PRIVACY_INDEX_KEY")
            val queueKey = requiredKey(environment, "OFFLINE_QUEUE_ENCRYPTION_KEY")
            require(!indexKey.contentEquals(queueKey)) {
                "PRIVACY_INDEX_KEY and OFFLINE_QUEUE_ENCRYPTION_KEY must be different"
            }
            return PrivacyConfig(
                indexKey = indexKey,
                offlineQueueEncryptionKey = queueKey,
                offlineQueueTtlSeconds = boundedLong(
                    environment,
                    "OFFLINE_QUEUE_TTL_SECONDS",
                    defaultValue = 900,
                    range = 60L..3_600L
                ),
                offlineFileTtlSeconds = boundedLong(
                    environment,
                    "OFFLINE_FILE_TTL_SECONDS",
                    defaultValue = 300,
                    range = 60L..900L
                ),
                consumedPreKeyRetentionHours = boundedInt(
                    environment,
                    "CONSUMED_PREKEY_RETENTION_HOURS",
                    defaultValue = 1,
                    range = 1..168
                ),
                pushTokenRetentionDays = boundedInt(
                    environment,
                    "PUSH_TOKEN_RETENTION_DAYS",
                    defaultValue = 30,
                    range = 1..90
                ),
                apiClientRetentionDays = boundedInt(
                    environment,
                    "API_CLIENT_RETENTION_DAYS",
                    defaultValue = 30,
                    range = 1..90
                ),
                turnCredentialTtlSeconds = boundedLong(
                    environment,
                    "TURN_CREDENTIAL_TTL_SECONDS",
                    defaultValue = 600,
                    range = 300L..3_600L
                ),
                allowLegacyPlaintextQueue =
                    environment["ALLOW_LEGACY_PLAINTEXT_QUEUE"]?.equals("true", ignoreCase = true) == true
            )
        }

        private fun requiredKey(environment: Map<String, String>, name: String): ByteArray {
            val encoded = SecretSource.required(name, environment)
            val decoded = try {
                Base64.getDecoder().decode(encoded)
            } catch (_: IllegalArgumentException) {
                error("$name must be valid Base64")
            }
            require(decoded.size == 32) { "$name must decode to exactly 32 bytes" }
            return decoded
        }

        private fun boundedLong(
            environment: Map<String, String>,
            name: String,
            defaultValue: Long,
            range: LongRange
        ): Long {
            val raw = environment[name] ?: return defaultValue
            val value = raw.toLongOrNull() ?: error("$name must be an integer")
            require(value in range) { "$name must be in ${range.first}..${range.last}" }
            return value
        }

        private fun boundedInt(
            environment: Map<String, String>,
            name: String,
            defaultValue: Int,
            range: IntRange
        ): Int {
            val raw = environment[name] ?: return defaultValue
            val value = raw.toIntOrNull() ?: error("$name must be an integer")
            require(value in range) { "$name must be in ${range.first}..${range.last}" }
            return value
        }
    }
}

class PrivacyPrimitives(
    val config: PrivacyConfig,
    private val random: SecureRandom = SecureRandom()
) {
    fun blindIndex(namespace: String, value: String): String {
        require(namespace.matches(Regex("[a-z0-9_-]{1,32}"))) { "Invalid blind-index namespace" }
        return Base64.getUrlEncoder().withoutPadding().encodeToString(hmac(namespace, value))
    }

    fun rateLimitKey(endpoint: String, identifier: String): String =
        "ratelimit_v2:${blindIndex("rate-limit", "$endpoint\u0000$identifier")}"

    private fun hmac(namespace: String, value: String): ByteArray {
        require(namespace.matches(Regex("[a-z0-9_-]{1,32}"))) { "Invalid blind-index namespace" }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(config.indexKey, "HmacSHA256"))
        val input = "$namespace\u0000$value".toByteArray(StandardCharsets.UTF_8)
        return mac.doFinal(input)
    }

    fun queueKey(bucket: String, userId: String): String {
        require(bucket == "message" || bucket == "file") { "Unknown queue bucket" }
        return "offline_${bucket}_v2:${blindIndex("queue-$bucket", userId)}"
    }

    fun registrationTokenUseKey(jti: String): String =
        "registration_token_used_v1:${blindIndex("registration-token", jti)}"

    fun activeCallKey(userA: String, userB: String): String {
        val pair = listOf(userA, userB).sorted().joinToString("\u0000")
        return "active_call_v2:${blindIndex("active-call", pair)}"
    }

    fun activeCallIndexKey(userId: String): String =
        "active_call_index_v2:${blindIndex("active-call-user", userId)}"

    fun logToken(value: String): String = blindIndex("log", value).take(16)

    fun sealQueue(recipientId: String, plaintext: String): String {
        val nonce = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(config.offlineQueueEncryptionKey, "AES"),
            GCMParameterSpec(128, nonce)
        )
        cipher.updateAAD(queueAad(recipientId))
        val ciphertext = cipher.doFinal(plaintext.toByteArray(StandardCharsets.UTF_8))
        return "OQ1:" + Base64.getUrlEncoder().withoutPadding().encodeToString(nonce + ciphertext)
    }

    fun openQueue(recipientId: String, envelope: String): String {
        if (!envelope.startsWith("OQ1:")) {
            if (config.allowLegacyPlaintextQueue) return envelope
            throw IllegalArgumentException("Legacy plaintext offline queue entry rejected")
        }
        val payload = try {
            Base64.getUrlDecoder().decode(envelope.removePrefix("OQ1:"))
        } catch (_: IllegalArgumentException) {
            throw IllegalArgumentException("Invalid offline queue envelope")
        }
        require(payload.size >= 12 + 16) { "Offline queue envelope is too short" }
        val nonce = payload.copyOfRange(0, 12)
        val ciphertext = payload.copyOfRange(12, payload.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(config.offlineQueueEncryptionKey, "AES"),
            GCMParameterSpec(128, nonce)
        )
        cipher.updateAAD(queueAad(recipientId))
        return String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
    }

    fun redactLogMessage(message: String): String {
        var redacted = message
        redacted = EMAIL.replace(redacted, "<email:redacted>")
        redacted = UUID.replace(redacted, "<id:redacted>")
        redacted = IPV4.replace(redacted, "<ip:redacted>")
        redacted = PHONE.replace(redacted, "<phone:redacted>")
        redacted = BEARER.replace(redacted, "Bearer <token:redacted>")
        redacted = JWT.replace(redacted, "<jwt:redacted>")
        return redacted
    }

    private fun queueAad(recipientId: String): ByteArray =
        "securechat-offline-queue-v1\u0000$recipientId".toByteArray(StandardCharsets.UTF_8)

    companion object {
        private val EMAIL = Regex("(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}")
        private val UUID = Regex("(?i)\\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\b")
        private val IPV4 = Regex("(?<![0-9])(?:[0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9])")
        private val PHONE = Regex("(?<![A-Za-z0-9])\\+?[0-9][0-9 ()-]{7,}[0-9](?![A-Za-z0-9])")
        private val BEARER = Regex("(?i)Bearer\\s+[^\\s,;]+")
        private val JWT = Regex("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b")
    }
}

object ServerPrivacy {
    val primitives: PrivacyPrimitives by lazy {
        PrivacyPrimitives(PrivacyConfig.fromEnvironment())
    }

    val config: PrivacyConfig get() = primitives.config
    fun blindIndex(namespace: String, value: String): String = primitives.blindIndex(namespace, value)
    fun queueKey(bucket: String, userId: String): String = primitives.queueKey(bucket, userId)
    fun registrationTokenUseKey(jti: String): String = primitives.registrationTokenUseKey(jti)
    fun activeCallKey(userA: String, userB: String): String = primitives.activeCallKey(userA, userB)
    fun activeCallIndexKey(userId: String): String = primitives.activeCallIndexKey(userId)
    fun rateLimitKey(endpoint: String, identifier: String): String =
        primitives.rateLimitKey(endpoint, identifier)
    fun logToken(value: String): String = primitives.logToken(value)
    fun sealQueue(recipientId: String, plaintext: String): String = primitives.sealQueue(recipientId, plaintext)
    fun openQueue(recipientId: String, envelope: String): String = primitives.openQueue(recipientId, envelope)
    fun redactLogMessage(message: String): String = primitives.redactLogMessage(message)

    fun initialize() {
        primitives
    }
}
