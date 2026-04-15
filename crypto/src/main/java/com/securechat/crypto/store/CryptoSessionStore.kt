package com.securechat.crypto.store

/**
 * Session persistence interface'i.
 * Storage modulu tarafindan Room DAO ile implement edilecek.
 * Her kullanici-cihaz cifti icin ayri bir session tutulur.
 */
interface CryptoSessionStore {
    suspend fun loadSession(name: String, deviceId: Int): ByteArray?
    suspend fun storeSession(name: String, deviceId: Int, record: ByteArray)
    suspend fun containsSession(name: String, deviceId: Int): Boolean
    suspend fun deleteSession(name: String, deviceId: Int)
    suspend fun deleteAllSessions(name: String)
    suspend fun getSubDeviceSessions(name: String): List<Int>
}
