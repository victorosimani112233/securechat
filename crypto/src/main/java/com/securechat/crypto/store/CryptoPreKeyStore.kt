package com.securechat.crypto.store

/**
 * One-time PreKey persistence interface'i.
 * Storage modulu tarafindan Room DAO ile implement edilecek.
 * Her PreKey tek kullanimliktir ve kullanildiktan sonra silinir.
 */
interface CryptoPreKeyStore {
    suspend fun loadPreKey(preKeyId: Int): ByteArray?
    suspend fun storePreKey(preKeyId: Int, record: ByteArray)
    suspend fun containsPreKey(preKeyId: Int): Boolean
    suspend fun removePreKey(preKeyId: Int)
    suspend fun getAvailablePreKeyCount(): Int
    suspend fun getNextPreKeyId(): Int
}
