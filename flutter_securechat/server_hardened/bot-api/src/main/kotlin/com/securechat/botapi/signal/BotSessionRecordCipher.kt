package com.securechat.botapi.signal

import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

/**
 * Versioned at-rest envelope for libsignal SessionRecord bytes. Session
 * records contain ratchet private keys and must never be stored as raw
 * protobuf. AAD binds a row to its opaque recipient index and device.
 */
object BotSessionRecordCipher {
    private val magic = byteArrayOf(0x42, 0x53, 0x52, 0x31) // BSR1
    private const val nonceLength = 12

    fun seal(recipientIndex: String, deviceId: Int, plaintext: ByteArray): ByteArray {
        val wrapped = KeyEncryptor.wrap(plaintext, aad(recipientIndex, deviceId))
        return ByteBuffer.allocate(magic.size + nonceLength + wrapped.ciphertext.size)
            .put(magic)
            .put(wrapped.nonce)
            .put(wrapped.ciphertext)
            .array()
    }

    fun open(recipientIndex: String, deviceId: Int, envelope: ByteArray): ByteArray {
        require(isSealed(envelope)) { "Legacy plaintext bot session record rejected" }
        require(envelope.size >= magic.size + nonceLength + 16) {
            "Bot session envelope is too short"
        }
        val nonceStart = magic.size
        val ciphertextStart = nonceStart + nonceLength
        return KeyEncryptor.unwrap(
            envelope.copyOfRange(ciphertextStart, envelope.size),
            envelope.copyOfRange(nonceStart, ciphertextStart),
            aad(recipientIndex, deviceId)
        )
    }

    fun isSealed(value: ByteArray): Boolean =
        value.size >= magic.size && value.copyOfRange(0, magic.size).contentEquals(magic)

    private fun aad(recipientIndex: String, deviceId: Int): ByteArray =
        "securechat-bot-session-v1\u0000$recipientIndex\u0000$deviceId"
            .toByteArray(StandardCharsets.UTF_8)
}
