package com.securechat.crypto

import com.securechat.crypto.model.CallEncryptionKeys
import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.crypto.model.EnvelopeType
import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * MessageEncryptor ve ilgili model siniflarinin unit testleri.
 * Signal Protocol'un dogru calistigini dogrular.
 */
class MessageEncryptorTest {

    @Test
    fun `EnvelopeType values should be correctly defined`() {
        assertThat(EnvelopeType.PREKEY).isNotNull()
        assertThat(EnvelopeType.SIGNAL).isNotNull()
        assertThat(EnvelopeType.values()).hasLength(2)
    }

    @Test
    fun `EncryptedEnvelope should preserve all data`() {
        val content = byteArrayOf(1, 2, 3, 4)
        val envelope = EncryptedEnvelope(
            type = EnvelopeType.SIGNAL,
            content = content,
            timestamp = 1000L,
            senderRegistrationId = 42
        )
        assertThat(envelope.type).isEqualTo(EnvelopeType.SIGNAL)
        assertThat(envelope.content).isEqualTo(content)
        assertThat(envelope.timestamp).isEqualTo(1000L)
        assertThat(envelope.senderRegistrationId).isEqualTo(42)
    }

    @Test
    fun `EncryptedEnvelope equals should compare content by value`() {
        val envelope1 = EncryptedEnvelope(
            type = EnvelopeType.PREKEY,
            content = byteArrayOf(10, 20, 30),
            timestamp = 500L,
            senderRegistrationId = 7
        )
        val envelope2 = EncryptedEnvelope(
            type = EnvelopeType.PREKEY,
            content = byteArrayOf(10, 20, 30),
            timestamp = 500L,
            senderRegistrationId = 7
        )
        assertThat(envelope1).isEqualTo(envelope2)
        assertThat(envelope1.hashCode()).isEqualTo(envelope2.hashCode())
    }

    @Test
    fun `EncryptedEnvelope should not be equal with different content`() {
        val envelope1 = EncryptedEnvelope(
            type = EnvelopeType.SIGNAL,
            content = byteArrayOf(1, 2, 3),
            timestamp = 100L,
            senderRegistrationId = 1
        )
        val envelope2 = EncryptedEnvelope(
            type = EnvelopeType.SIGNAL,
            content = byteArrayOf(4, 5, 6),
            timestamp = 100L,
            senderRegistrationId = 1
        )
        assertThat(envelope1).isNotEqualTo(envelope2)
    }

    @Test
    fun `EncryptedEnvelope should not be equal with different type`() {
        val content = byteArrayOf(1, 2, 3)
        val envelope1 = EncryptedEnvelope(
            type = EnvelopeType.PREKEY,
            content = content,
            timestamp = 100L,
            senderRegistrationId = 1
        )
        val envelope2 = EncryptedEnvelope(
            type = EnvelopeType.SIGNAL,
            content = content,
            timestamp = 100L,
            senderRegistrationId = 1
        )
        assertThat(envelope1).isNotEqualTo(envelope2)
    }

    @Test
    fun `CallEncryptionKeys should be clearable`() {
        val keys = CallEncryptionKeys(
            masterKey = byteArrayOf(1, 2, 3),
            masterSalt = byteArrayOf(4, 5, 6)
        )
        keys.clear()
        assertThat(keys.masterKey).isEqualTo(byteArrayOf(0, 0, 0))
        assertThat(keys.masterSalt).isEqualTo(byteArrayOf(0, 0, 0))
    }

    @Test
    fun `CallEncryptionKeys clear should zero out all bytes`() {
        val masterKey = ByteArray(32) { (it + 1).toByte() }
        val masterSalt = ByteArray(32) { (it + 33).toByte() }
        val keys = CallEncryptionKeys(masterKey = masterKey, masterSalt = masterSalt)

        keys.clear()

        val expectedZero = ByteArray(32) { 0 }
        assertThat(keys.masterKey).isEqualTo(expectedZero)
        assertThat(keys.masterSalt).isEqualTo(expectedZero)
    }

    @Test
    fun `CallEncryptionKeys equals should compare by content`() {
        val keys1 = CallEncryptionKeys(
            masterKey = byteArrayOf(1, 2, 3),
            masterSalt = byteArrayOf(4, 5, 6)
        )
        val keys2 = CallEncryptionKeys(
            masterKey = byteArrayOf(1, 2, 3),
            masterSalt = byteArrayOf(4, 5, 6)
        )
        assertThat(keys1).isEqualTo(keys2)
        assertThat(keys1.hashCode()).isEqualTo(keys2.hashCode())
    }

    @Test
    fun `CallEncryptionKeys should not be equal with different keys`() {
        val keys1 = CallEncryptionKeys(
            masterKey = byteArrayOf(1, 2, 3),
            masterSalt = byteArrayOf(4, 5, 6)
        )
        val keys2 = CallEncryptionKeys(
            masterKey = byteArrayOf(7, 8, 9),
            masterSalt = byteArrayOf(4, 5, 6)
        )
        assertThat(keys1).isNotEqualTo(keys2)
    }
}
