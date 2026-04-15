package com.securechat.crypto.store

/**
 * Signed PreKey persistence interface'i.
 * Storage modulu tarafindan Room DAO ile implement edilecek.
 * Signed PreKey periyodik olarak rotate edilir (varsayilan 7 gun).
 */
interface CryptoSignedPreKeyStore {
    suspend fun loadSignedPreKey(signedPreKeyId: Int): ByteArray?
    suspend fun loadAllSignedPreKeys(): List<ByteArray>
    suspend fun storeSignedPreKey(signedPreKeyId: Int, record: ByteArray)
    suspend fun containsSignedPreKey(signedPreKeyId: Int): Boolean
    suspend fun removeSignedPreKey(signedPreKeyId: Int)
}
