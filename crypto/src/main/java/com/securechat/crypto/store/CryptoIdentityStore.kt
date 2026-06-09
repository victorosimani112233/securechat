package com.securechat.crypto.store

/**
 * Identity key persistence interface'i.
 * Storage modulu tarafindan Room DAO ile implement edilecek.
 * Identity key cifti cihaz basina bir tane olup uzun omurludur.
 */
interface CryptoIdentityStore {
    suspend fun loadIdentity(name: String): ByteArray?
    suspend fun storeIdentity(name: String, identityKey: ByteArray): Boolean
    /**
     * Bir peer icin saklanan identity key'i siler. Auto-session-healing sirasinda
     * (peer reinstall yaptiginda identity rotasyonu) cagrilir; bir sonraki
     * PreKeyBundle fetch'inde yeni identity TOFU kuralina gore yeniden trust edilir.
     */
    suspend fun deleteIdentity(name: String)
    suspend fun getLocalRegistrationId(): Int
    suspend fun storeLocalRegistrationId(registrationId: Int)
    suspend fun getIdentityKeyPair(): ByteArray?
    suspend fun storeIdentityKeyPair(keyPair: ByteArray)
}
