package com.securechat.crypto.store

/**
 * SenderKey persistence interface'i. Storage modulu tarafindan Room DAO ile
 * implement edilir. Her (groupId, senderId, deviceId) ucluse icin bir
 * SenderKeyRecord (serialize edilmis) tutar.
 *
 * Signal Protocol'un Sender Keys ozelliginin (group messaging) altyapisini saglar.
 */
interface CryptoSenderKeyStore {
    suspend fun loadSenderKey(groupId: String, senderId: String, deviceId: Int): ByteArray?
    suspend fun storeSenderKey(groupId: String, senderId: String, deviceId: Int, record: ByteArray)
    suspend fun deleteSenderKey(groupId: String, senderId: String, deviceId: Int)
    suspend fun deleteAllForGroup(groupId: String)
    suspend fun containsSenderKey(groupId: String, senderId: String, deviceId: Int): Boolean
}
