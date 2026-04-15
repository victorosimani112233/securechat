package com.securechat.crypto.model

/**
 * WebRTC SRTP icin turetilmis sifreleme anahtarlari.
 * Kullanim sonrasi clear() ile bellekten sifirlanmalidir.
 */
data class CallEncryptionKeys(
    val masterKey: ByteArray,
    val masterSalt: ByteArray
) {
    /**
     * Key material'i bellekten sifirlar.
     * Arama sona erdiginde mutlaka cagrilmalidir.
     */
    fun clear() {
        masterKey.fill(0)
        masterSalt.fill(0)
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is CallEncryptionKeys) return false
        return masterKey.contentEquals(other.masterKey) && masterSalt.contentEquals(other.masterSalt)
    }

    override fun hashCode(): Int = 31 * masterKey.contentHashCode() + masterSalt.contentHashCode()
}
