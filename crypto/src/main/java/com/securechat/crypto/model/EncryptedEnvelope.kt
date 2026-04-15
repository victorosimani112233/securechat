package com.securechat.crypto.model

/**
 * Signal Protocol ile sifrelenmiş mesaj zarfı.
 * Mesajın tipini (PreKey veya Signal), sifrelenmis icerigini,
 * zaman damgasını ve gonderenin registration ID'sini icerir.
 */
data class EncryptedEnvelope(
    val type: EnvelopeType,
    val content: ByteArray,
    val timestamp: Long,
    val senderRegistrationId: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is EncryptedEnvelope) return false
        return type == other.type && content.contentEquals(other.content) &&
                timestamp == other.timestamp && senderRegistrationId == other.senderRegistrationId
    }

    override fun hashCode(): Int {
        var result = type.hashCode()
        result = 31 * result + content.contentHashCode()
        result = 31 * result + timestamp.hashCode()
        result = 31 * result + senderRegistrationId
        return result
    }
}

/**
 * Mesaj zarfı tipi.
 * PREKEY: Ilk mesaj icin X3DH key agreement mesajı
 * SIGNAL: Normal Double Ratchet mesajı
 */
enum class EnvelopeType {
    PREKEY,
    SIGNAL
}
