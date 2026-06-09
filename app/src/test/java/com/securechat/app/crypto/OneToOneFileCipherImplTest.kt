package com.securechat.app.crypto

import com.google.common.truth.Truth.assertThat
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.crypto.model.EnvelopeType
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test
import org.whispersystems.libsignal.protocol.CiphertextMessage
import java.nio.ByteBuffer

/**
 * OneToOneFileCipherImpl pure logic testleri — wire format pack/unpack
 * davranisi ve hata yollari.
 */
class OneToOneFileCipherImplTest {

    private lateinit var sessionEnsurer: SessionEnsurer
    private lateinit var messageEncryptor: MessageEncryptor
    private lateinit var cipher: OneToOneFileCipherImpl

    @Before
    fun setup() {
        sessionEnsurer = mockk(relaxed = true)
        messageEncryptor = mockk(relaxed = true)
        cipher = OneToOneFileCipherImpl(sessionEnsurer, messageEncryptor)
    }

    @Test
    fun `ensureSession delegates to SessionEnsurer`() = runTest {
        coEvery { sessionEnsurer.ensureSession("alice") } returns true

        assertThat(cipher.ensureSession("alice")).isTrue()
    }

    @Test
    fun `encrypt - PREKEY type basariyla pack edilir`() = runTest {
        val plaintext = byteArrayOf(1, 2, 3, 4)
        val envelopeContent = byteArrayOf(10, 20, 30)
        every { messageEncryptor.encrypt("alice", plaintext) } returns EncryptedEnvelope(
            type = EnvelopeType.PREKEY,
            content = envelopeContent,
            timestamp = 0L,
            senderRegistrationId = 14411
        )

        val packed = cipher.encrypt("alice", plaintext)!!

        // Header (5 byte) + content (3 byte) = 8
        assertThat(packed.size).isEqualTo(8)
        assertThat(packed[0]).isEqualTo(CiphertextMessage.PREKEY_TYPE.toByte())
        // regId big-endian
        val regId = ByteBuffer.wrap(packed, 1, 4).int
        assertThat(regId).isEqualTo(14411)
        // Content tail
        assertThat(packed.copyOfRange(5, 8)).isEqualTo(envelopeContent)
    }

    @Test
    fun `encrypt - SIGNAL type basariyla pack edilir`() = runTest {
        every { messageEncryptor.encrypt(any(), any()) } returns EncryptedEnvelope(
            type = EnvelopeType.SIGNAL,
            content = byteArrayOf(99),
            timestamp = 0L,
            senderRegistrationId = 7
        )

        val packed = cipher.encrypt("bob", byteArrayOf(1))!!

        assertThat(packed[0]).isEqualTo(CiphertextMessage.WHISPER_TYPE.toByte())
    }

    @Test
    fun `encrypt - exception null doner`() = runTest {
        every { messageEncryptor.encrypt(any(), any()) } throws RuntimeException("boom")

        val packed = cipher.encrypt("alice", byteArrayOf(1, 2))

        assertThat(packed).isNull()
    }

    @Test
    fun `decrypt - dogru paketten plaintext cikartir`() = runTest {
        val plaintext = byteArrayOf(7, 8, 9)
        val ciphertextContent = byteArrayOf(50, 60)
        every { messageEncryptor.decrypt(eq("alice"), any()) } returns plaintext

        // Pack: [PREKEY_TYPE, regId=42 BE, content]
        val packed = ByteArray(5 + ciphertextContent.size)
        packed[0] = CiphertextMessage.PREKEY_TYPE.toByte()
        ByteBuffer.wrap(packed, 1, 4).putInt(42)
        System.arraycopy(ciphertextContent, 0, packed, 5, ciphertextContent.size)

        val result = cipher.decrypt("alice", packed)

        assertThat(result).isEqualTo(plaintext)
    }

    @Test
    fun `decrypt - kisa paket null doner (header eksik)`() = runTest {
        val tooShort = byteArrayOf(1, 2, 3) // 5 byte header altinda

        val result = cipher.decrypt("alice", tooShort)

        assertThat(result).isNull()
    }

    @Test
    fun `decrypt - bilinmeyen type magic null doner`() = runTest {
        val packed = byteArrayOf(99.toByte(), 0, 0, 0, 0, 1, 2)

        val result = cipher.decrypt("alice", packed)

        assertThat(result).isNull()
    }

    @Test
    fun `decrypt - NoSessionException null doner ve crash etmez`() = runTest {
        every { messageEncryptor.decrypt(any(), any()) } throws
            org.whispersystems.libsignal.NoSessionException("session yok")

        val packed = ByteArray(5 + 2)
        packed[0] = CiphertextMessage.WHISPER_TYPE.toByte()

        val result = cipher.decrypt("alice", packed)

        assertThat(result).isNull()
    }

    @Test
    fun `roundtrip - encrypt sonrasi unpack ayni plaintext'i verir`() = runTest {
        val plaintext = "Test mesaji 1:1".toByteArray()
        val cipherBytes = byteArrayOf(10, 20, 30, 40, 50)
        every { messageEncryptor.encrypt("alice", plaintext) } returns EncryptedEnvelope(
            type = EnvelopeType.SIGNAL,
            content = cipherBytes,
            timestamp = 0L,
            senderRegistrationId = 999
        )
        every { messageEncryptor.decrypt(eq("alice"), any()) } answers {
            val env = secondArg<EncryptedEnvelope>()
            // Alici tarafinda "decrypt" sahte — cipher bytes'i geri okur (gercek libsignal
            // burada ratchet ileri tasir, ama mock test'inde bytes round-trip kontrolu yapariz)
            assertThat(env.type).isEqualTo(EnvelopeType.SIGNAL)
            assertThat(env.content).isEqualTo(cipherBytes)
            assertThat(env.senderRegistrationId).isEqualTo(999)
            plaintext
        }

        val packed = cipher.encrypt("alice", plaintext)!!
        val unpacked = cipher.decrypt("alice", packed)

        assertThat(unpacked).isEqualTo(plaintext)
    }
}
