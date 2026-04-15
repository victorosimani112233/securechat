package com.securechat.crypto.store

/**
 * Identity key persistence interface'i.
 * Storage modulu tarafindan Room DAO ile implement edilecek.
 * Identity key cifti cihaz basina bir tane olup uzun omurludur.
 */
interface CryptoIdentityStore {
    suspend fun loadIdentity(name: String): ByteArray?
    suspend fun storeIdentity(name: String, identityKey: ByteArray): Boolean
    suspend fun getLocalRegistrationId(): Int
    suspend fun storeLocalRegistrationId(registrationId: Int)
    suspend fun getIdentityKeyPair(): ByteArray?
    suspend fun storeIdentityKeyPair(keyPair: ByteArray)
}
