package com.securechat.botapi.delivery

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class BotQueuePrivacyTest {
    private val primitives = BotQueuePrimitives(
        indexKey = ByteArray(32) { (it + 3).toByte() },
        encryptionKey = ByteArray(32) { (it + 93).toByte() }
    )

    @Test
    fun `queue key and value hide bot and message metadata`() {
        val botId = "123e4567-e89b-42d3-a456-426614174000"
        val plaintext = "{\"recipientId\":\"peer-secret\",\"envelope\":\"ciphertext\"}"
        val first = primitives.seal(botId, plaintext)
        val second = primitives.seal(botId, plaintext)

        assertFalse(primitives.key(botId).contains(botId))
        assertFalse(first.contains("peer-secret"))
        assertNotEquals(first, second)
        assertEquals(plaintext, primitives.open(botId, first))
        assertThrows(Exception::class.java) { primitives.open("another-bot", first) }
        assertThrows(IllegalArgumentException::class.java) { primitives.open(botId, plaintext) }
    }

    @Test
    fun `private indexes and values are purpose and binding separated`() {
        val clientId = "client-private-id"
        val idempotencyKey = "request-private-key"
        val binding = "$clientId\u0000$idempotencyKey"
        val response = "{\"messageId\":\"private-message-id\",\"status\":\"queued\"}"

        val index = primitives.blindIndex("idempotency", binding)
        val sealed = primitives.sealPrivate("idempotency", binding, response)

        assertFalse(index.contains(clientId))
        assertFalse(index.contains(idempotencyKey))
        assertFalse(sealed.contains("private-message-id"))
        assertEquals(response, primitives.openPrivate("idempotency", binding, sealed))
        assertThrows(Exception::class.java) {
            primitives.openPrivate("idempotency", "different-binding", sealed)
        }
        assertThrows(Exception::class.java) {
            primitives.openPrivate("different-purpose", binding, sealed)
        }
    }
}
