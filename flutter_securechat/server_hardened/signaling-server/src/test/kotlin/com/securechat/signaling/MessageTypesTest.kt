package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Cerceve turu siniflandirmasi.
 *
 * Siniflandirma kuyruk kovasini, TTL'i ve gecici sinyallerin hic
 * yazilmamasini belirler; push tasiyicisindan bagimsiz olmalidir.
 */
class MessageTypesTest {

    @Test
    fun `the type field is read from a frame`() {
        assertEquals(
            "encrypted_message",
            MessageTypes.extract("""{"type":"encrypted_message","messageId":"m"}"""),
        )
        assertEquals(
            "sdp_offer",
            MessageTypes.extract("""{"messageId":"m", "type" : "sdp_offer" }"""),
        )
    }

    @Test
    fun `a frame without a readable type yields null`() {
        assertNull(MessageTypes.extract("""{"messageId":"m"}"""))
        assertNull(MessageTypes.extract(""))
        assertNull(MessageTypes.extract("not json"))
        assertNull(MessageTypes.extract("""{"type":123}"""))
    }

    @Test
    fun `transient signals are recognised`() {
        for (type in MessageTypes.TRANSIENT) {
            assertTrue(MessageTypes.isTransient("""{"type":"$type"}"""), type)
        }
        assertFalse(MessageTypes.isTransient("""{"type":"encrypted_message"}"""))
        // Tur okunamiyorsa gecici sayilmaz: mesaj dusurulmemelidir.
        assertFalse(MessageTypes.isTransient("""{"messageId":"m"}"""))
    }

    @Test
    fun `file transfers are recognised`() {
        assertTrue(MessageTypes.isFileTransfer("""{"type":"file_transfer"}"""))
        assertFalse(MessageTypes.isFileTransfer("""{"type":"encrypted_message"}"""))
    }

    @Test
    fun `pending call signals are the ones a caller can withdraw`() {
        assertEquals(setOf("sdp_offer", "sdp_answer", "ice_candidate", "call_control"), MessageTypes.PENDING_CALL)
        assertEquals(MessageTypes.PENDING_CALL + "group_call_invite", MessageTypes.REQUIRES_CALL_HANDLER)
    }
}
