package com.securechat.media.crypto

/**
 * 1:1 dosya transferi icin Signal Protocol SessionCipher koprusu.
 *
 * FileTransferManager media modulunde, SessionEnsurer + MessageEncryptor
 * app modulundedir — circular bagim olusmamasi icin bu interface media
 * modulunde tanimli ve app modulu Hilt provide ile concrete impl sunar.
 *
 * Cipher null ise (test, dev) plaintext fallback. Production'da Hilt
 * binding mevcut oldugu icin FileTransferManager bu cipher uzerinden gecer.
 *
 * Davranis kontrati:
 *   - ensureSession async; PreKeyBundle yoksa false doner, encrypt cagrilmamalı.
 *   - encrypt suspend; success ciphertext bytes, fail null doner.
 *   - decrypt suspend; success plaintext bytes, fail null doner (sender'in
 *     session'i bizde yoksa NoSession dahil).
 *   - ARDISIK chunk'lar SessionCipher'in ratchet'ini ileri tasiyacagindan
 *     SIRA ÖNEMLI — chunk drop edilirse sonraki decrypt fail.
 */
interface OneToOneFileCipher {
    /** PreKeyBundle fetch + session kurulumu. Tekrarlanan cagrilar idempotent. */
    suspend fun ensureSession(recipientId: String): Boolean

    /** Ciphertext bytes ya da null (encrypt fail, session yok, vs.). */
    suspend fun encrypt(recipientId: String, plaintext: ByteArray): ByteArray?

    /** Plaintext bytes ya da null (decrypt fail, NoSession, InvalidMessage, vs.). */
    suspend fun decrypt(senderId: String, ciphertext: ByteArray): ByteArray?
}
