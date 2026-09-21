package com.securechat.signaling

import java.security.SecureRandom
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class PushHintCipherTest {
    private val key = ByteArray(32) { (it + 19).toByte() }

    @Test
    fun `call and message hints are fixed width and authenticated`() {
        val cipher = PushHintCipher(SecureRandom())
        val call = cipher.seal(key, PushHintCipher.CALL_KIND)
        val message = cipher.seal(key, PushHintCipher.MESSAGE_KIND)

        assertEquals(PushHintCipher.WIRE_LENGTH, call.length)
        assertEquals(PushHintCipher.WIRE_LENGTH, message.length)
        assertEquals(PushHintCipher.CALL_KIND, cipher.open(key, call))
        assertEquals(PushHintCipher.MESSAGE_KIND, cipher.open(key, message))
        assertNotEquals(call, cipher.seal(key, PushHintCipher.CALL_KIND))
        assertNull(cipher.open(ByteArray(32) { 7 }, call))
        val tamperIndex = 10
        val replacement = if (call[tamperIndex] == 'A') 'B' else 'A'
        val tampered = call.replaceRange(tamperIndex, tamperIndex + 1, replacement.toString())
        assertNull(cipher.open(key, tampered))
    }

    @Test
    fun `only incoming call setup signals receive a call hint`() {
        assertEquals('c', FcmPushSender.pushHintKind("sdp_offer"))
        assertEquals('c', FcmPushSender.pushHintKind("group_call_invite"))
        assertEquals('m', FcmPushSender.pushHintKind("call_control"))
        assertEquals('m', FcmPushSender.pushHintKind("encrypted_message"))
    }
}
