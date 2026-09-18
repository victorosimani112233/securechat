package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.charset.StandardCharsets
import java.util.Base64
import com.securechat.signaling.db.RedisEphemeralPolicy
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class ServerPrivacyTest {
    private val environment = mapOf(
        "PRIVACY_INDEX_KEY" to Base64.getEncoder().encodeToString(ByteArray(32) { (it + 1).toByte() }),
        "OFFLINE_QUEUE_ENCRYPTION_KEY" to Base64.getEncoder().encodeToString(ByteArray(32) { (it + 71).toByte() })
    )

    @Test
    fun `service delivery acknowledgement is a server-only frame`() {
        assertTrue(isServerOnlyFrameType("message_ack"))
        assertFalse(isServerOnlyFrameType("delivery_transport_ack"))
        assertFalse(isServerOnlyFrameType("encrypted_message"))
        assertFalse(isServerOnlyFrameType(null))
    }

    @Test
    fun `safe retention defaults and hard upper bounds`() {
        val defaults = PrivacyConfig.fromEnvironment(environment)
        assertEquals(900, defaults.offlineQueueTtlSeconds)
        assertEquals(300, defaults.offlineFileTtlSeconds)
        assertEquals(1, defaults.consumedPreKeyRetentionHours)
        assertEquals(30, defaults.pushTokenRetentionDays)
        assertEquals(30, defaults.apiClientRetentionDays)
        assertEquals(600, defaults.turnCredentialTtlSeconds)
        assertFalse(defaults.allowLegacyPlaintextQueue)

        assertThrows(IllegalArgumentException::class.java) {
            PrivacyConfig.fromEnvironment(environment + ("OFFLINE_QUEUE_TTL_SECONDS" to "3601"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            PrivacyConfig.fromEnvironment(environment + ("OFFLINE_FILE_TTL_SECONDS" to "901"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            PrivacyConfig.fromEnvironment(environment + ("TURN_CREDENTIAL_TTL_SECONDS" to "3601"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            PrivacyConfig.fromEnvironment(environment + ("API_CLIENT_RETENTION_DAYS" to "91"))
        }
    }

    @Test
    fun `redis transient state rejects both disk persistence modes`() {
        RedisEphemeralPolicy.requireMemoryOnly(
            mapOf("appendonly" to "no", "save" to "")
        )
        assertThrows(IllegalArgumentException::class.java) {
            RedisEphemeralPolicy.requireMemoryOnly(
                mapOf("appendonly" to "yes", "save" to "")
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            RedisEphemeralPolicy.requireMemoryOnly(
                mapOf("appendonly" to "no", "save" to "3600 1")
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            RedisEphemeralPolicy.requireMemoryOnly(
                mapOf("appendonly" to "no")
            )
        }
    }

    @Test
    fun `redis must not silently evict live keys`() {
        // `allkeys-*` altinda bellek baskisinda TTL'i dolmamis key'ler atilir.
        // Bunun iki sessiz sonucu vardir: teslim edilmemis ciphertext kaybolur
        // ve rate limit pencereleri sifirlanir. Ikincisi saldirganin
        // kuyruklari doldurarak tetikleyebilecegi bir bypass'tir.
        for (policy in listOf("allkeys-lru", "allkeys-lfu", "allkeys-random")) {
            assertThrows(IllegalArgumentException::class.java) {
                RedisEphemeralPolicy.requireMemoryOnly(
                    mapOf("appendonly" to "no", "save" to "", "maxmemory-policy" to policy),
                )
            }
        }
        // TTL'e saygi duyan ve yazmayi reddeden politikalar kabul edilir.
        for (policy in listOf("noeviction", "volatile-ttl", "volatile-lru")) {
            RedisEphemeralPolicy.requireMemoryOnly(
                mapOf("appendonly" to "no", "save" to "", "maxmemory-policy" to policy),
            )
        }
    }

    @Test
    fun `security audit keeps only identity free process counters`() {
        val before = AuditLog.count("WS_AUTH_INVALID")
        AuditLog.log(
            userId = "123e4567-e89b-42d3-a456-426614174000",
            eventType = "WS_AUTH_INVALID",
            metadata = mapOf("reason" to "secret detail"),
            ipAddress = "192.0.2.1",
        )
        assertEquals(before + 1, AuditLog.count("WS_AUTH_INVALID"))
        AuditLog.log(eventType = "invalid event")
        assertEquals(0, AuditLog.count("invalid event"))
    }

    @Test
    fun `behavioral chat controls must travel only inside e2ee envelopes`() {
        assertTrue(isPlaintextChatControlType("delivery_receipt"))
        assertTrue(isPlaintextChatControlType("message_edit"))
        assertTrue(isPlaintextChatControlType("message_reaction"))
        assertTrue(isPlaintextChatControlType("typing_indicator"))
        assertTrue(isPlaintextChatControlType("disappearing_timer"))
        assertTrue(isPlaintextChatControlType("session_reset_request"))
        assertFalse(isPlaintextChatControlType("encrypted_message"))
        assertFalse(isPlaintextChatControlType(null))
    }

    @Test
    fun `queue and blind index keys are mandatory separate 256 bit values`() {
        assertThrows(IllegalStateException::class.java) {
            PrivacyConfig.fromEnvironment(emptyMap())
        }
        assertThrows(IllegalArgumentException::class.java) {
            PrivacyConfig.fromEnvironment(
                environment + ("OFFLINE_QUEUE_ENCRYPTION_KEY" to environment.getValue("PRIVACY_INDEX_KEY"))
            )
        }
    }

    @Test
    fun `offline values are randomized authenticated and recipient bound`() {
        val primitives = PrivacyPrimitives(PrivacyConfig.fromEnvironment(environment))
        val plaintext = "{\"type\":\"encrypted_message\",\"envelope\":\"ciphertext\"}"
        val first = primitives.sealQueue("recipient-a", plaintext)
        val second = primitives.sealQueue("recipient-a", plaintext)

        assertTrue(first.startsWith("OQ2:"))
        assertNotEquals(first, second)
        assertFalse(first.contains("encrypted_message"))
        assertEquals(plaintext, primitives.openQueue("recipient-a", first))
        assertThrows(Exception::class.java) {
            primitives.openQueue("recipient-b", first)
        }
        assertThrows(IllegalArgumentException::class.java) {
            primitives.openQueue("recipient-a", plaintext)
        }

        val parts = first.split(':', limit = 3)
        val unknownKey = "OQ2:${"A".repeat(parts[1].length)}:${parts[2]}"
        assertThrows(IllegalArgumentException::class.java) {
            primitives.openQueue("recipient-a", unknownKey)
        }
    }

    @Test
    fun `offline queue reads v1 during migration and enforces nonce budget`() {
        val config = PrivacyConfig.fromEnvironment(environment)
        val primitives = PrivacyPrimitives(config, nonceBudget = 2)
        val plaintext = "legacy-ciphertext-envelope"
        val nonce = ByteArray(12) { (it + 9).toByte() }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.ENCRYPT_MODE,
            SecretKeySpec(config.offlineQueueEncryptionKey, "AES"),
            GCMParameterSpec(128, nonce),
        )
        cipher.updateAAD(
            "securechat-offline-queue-v1\u0000recipient-a"
                .toByteArray(StandardCharsets.UTF_8),
        )
        val legacy = "OQ1:" + Base64.getUrlEncoder().withoutPadding()
            .encodeToString(nonce + cipher.doFinal(plaintext.toByteArray()))

        assertEquals(plaintext, primitives.openQueue("recipient-a", legacy))
        primitives.sealQueue("recipient-a", "one")
        primitives.sealQueue("recipient-a", "two")
        assertThrows(IllegalStateException::class.java) {
            primitives.sealQueue("recipient-a", "three")
        }
    }

    @Test
    fun `redis keys and logs do not expose direct identifiers`() {
        val primitives = PrivacyPrimitives(PrivacyConfig.fromEnvironment(environment))
        val userId = "123e4567-e89b-42d3-a456-426614174000"
        val key = primitives.queueKey("message", userId)
        assertFalse(key.contains(userId))
        assertEquals(key, primitives.queueKey("message", userId))
        assertFalse(primitives.queuePayloadKey("delivery", userId).contains(userId))
        assertFalse(primitives.queueOrderKey("delivery", userId).contains(userId))

        val deliveryId = "A".repeat(43)
        val deliveryToken = primitives.deliveryToken(userId, "sender-a", deliveryId)
        assertFalse(primitives.queueItemKey("delivery", userId, deliveryToken).contains(userId))
        assertFalse(primitives.queueItemKey("delivery", userId, deliveryToken).contains(deliveryToken))
        assertEquals(deliveryToken, primitives.deliveryToken(userId, "sender-a", deliveryId))
        assertNotEquals(deliveryToken, primitives.deliveryToken(userId, "sender-b", deliveryId))
        assertNotEquals(
            deliveryToken,
            primitives.deliveryToken("123e4567-e89b-42d3-a456-426614174099", "sender-a", deliveryId),
        )
        assertFalse(deliveryToken.contains(deliveryId))

        val peerId = "123e4567-e89b-42d3-a456-426614174001"
        val callKey = primitives.activeCallKey(userId, peerId)
        assertFalse(callKey.contains(userId))
        assertFalse(callKey.contains(peerId))
        assertEquals(callKey, primitives.activeCallKey(peerId, userId))
        assertFalse(primitives.activeCallIndexKey(userId).contains(userId))
        assertFalse(primitives.rateLimitKey("otp_request", "192.168.1.20").contains("192.168.1.20"))
        val redacted = primitives.redactLogMessage(
            "user=$userId email=alice@example.com ip=192.168.1.20 " +
                "phone=+90 555 111 22 33 Bearer secret-token"
        )
        assertFalse(redacted.contains(userId))
        assertFalse(redacted.contains("alice@example.com"))
        assertFalse(redacted.contains("192.168.1.20"))
        assertFalse(redacted.contains("555 111"))
        assertFalse(redacted.contains("secret-token"))
    }

    @Test
    fun `account deletion bot-session index matches the cross-service vector`() {
        val vectorEnvironment = environment + (
            "PRIVACY_INDEX_KEY" to Base64.getEncoder().encodeToString(
                ByteArray(32) { (it + 81).toByte() },
            )
        )
        val primitives = PrivacyPrimitives(PrivacyConfig.fromEnvironment(vectorEnvironment))
        assertEquals(
            "Q9yhE-3QYfEAfTg_j5L8la0Z-eZjWvSv7suBOSCzb0Y",
            primitives.blindIndex(
                "bot-signal-peer",
                "123e4567-e89b-42d3-a456-426614174000",
            ),
        )
    }
}
