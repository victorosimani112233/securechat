package com.securechat.app.crypto

import android.util.Log
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.crypto.model.EnvelopeType
import com.securechat.media.crypto.OneToOneFileCipher
import org.whispersystems.libsignal.protocol.CiphertextMessage
import java.nio.ByteBuffer
import javax.inject.Inject
import javax.inject.Singleton

/**
 * media.OneToOneFileCipher implementasyonu — SessionEnsurer ve MessageEncryptor
 * ile gercek SessionCipher'i sarmalar.
 *
 * Wire format (her ciphertext byte array):
 *   [byte 0]    encryption type magic (1 = PREKEY, 2 = SIGNAL)
 *   [byte 1..4] big-endian int — gondericinin registration id
 *   [byte 5..]  Signal Protocol ciphertext bytes
 *
 * Bu format minimum overhead (5 byte) + alici tarafta dogru SessionCipher
 * type'i secebilmek icin gerekli. Mevcut wireEnvelope "E2EE:v1:" string
 * format'iyla simetrik bilgi; file chunk'lari binary oldugu icin string
 * prefix'i kullanmiyoruz.
 *
 * GUVENLIK: Plaintext byte array kullanim sonrasi (caller tarafindan) fill(0)
 * ile sifirlanmali; bu sinif ARG'lari kopyalamaz, ortak buffer ile calisir.
 */
@Singleton
class OneToOneFileCipherImpl @Inject constructor(
    private val sessionEnsurer: SessionEnsurer,
    private val messageEncryptor: MessageEncryptor
) : OneToOneFileCipher {

    override suspend fun ensureSession(recipientId: String): Boolean =
        sessionEnsurer.ensureSession(recipientId)

    override suspend fun encrypt(recipientId: String, plaintext: ByteArray): ByteArray? {
        return try {
            val envelope = messageEncryptor.encrypt(recipientId, plaintext)
            packEnvelope(envelope)
        } catch (e: Exception) {
            Log.w(TAG, "1:1 file encrypt fail (${e.javaClass.simpleName}): ${e.message}")
            null
        }
    }

    override suspend fun decrypt(senderId: String, ciphertext: ByteArray): ByteArray? {
        return try {
            val envelope = unpackEnvelope(ciphertext) ?: return null
            messageEncryptor.decrypt(senderId, envelope)
        } catch (e: org.whispersystems.libsignal.DuplicateMessageException) {
            Log.d(TAG, "1:1 file chunk duplicate, ignore: $senderId")
            null
        } catch (e: org.whispersystems.libsignal.NoSessionException) {
            Log.w(TAG, "1:1 file chunk session yok: $senderId")
            null
        } catch (e: Exception) {
            Log.w(TAG, "1:1 file decrypt fail (${e.javaClass.simpleName}): ${e.message}")
            null
        }
    }

    /** EncryptedEnvelope -> [type:1, regId:4, content:N] kompakt binary format. */
    private fun packEnvelope(env: EncryptedEnvelope): ByteArray {
        val typeMagic: Byte = when (env.type) {
            EnvelopeType.PREKEY -> CiphertextMessage.PREKEY_TYPE.toByte()
            EnvelopeType.SIGNAL -> CiphertextMessage.WHISPER_TYPE.toByte()
        }
        val out = ByteArray(HEADER_SIZE + env.content.size)
        out[0] = typeMagic
        ByteBuffer.wrap(out, 1, 4).putInt(env.senderRegistrationId)
        System.arraycopy(env.content, 0, out, HEADER_SIZE, env.content.size)
        return out
    }

    private fun unpackEnvelope(packed: ByteArray): EncryptedEnvelope? {
        if (packed.size < HEADER_SIZE) return null
        val typeMagic = packed[0].toInt()
        val type = when (typeMagic) {
            CiphertextMessage.PREKEY_TYPE -> EnvelopeType.PREKEY
            CiphertextMessage.WHISPER_TYPE -> EnvelopeType.SIGNAL
            else -> return null
        }
        val regId = ByteBuffer.wrap(packed, 1, 4).int
        val content = packed.copyOfRange(HEADER_SIZE, packed.size)
        return EncryptedEnvelope(
            type = type,
            content = content,
            timestamp = System.currentTimeMillis(),
            senderRegistrationId = regId
        )
    }

    companion object {
        private const val TAG = "OneToOneFileCipher"
        const val HEADER_SIZE = 5
    }
}
