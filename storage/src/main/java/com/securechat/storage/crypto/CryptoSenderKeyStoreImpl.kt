package com.securechat.storage.crypto

import com.securechat.crypto.store.CryptoSenderKeyStore
import com.securechat.storage.dao.SenderKeyDao
import com.securechat.storage.entity.SenderKeyEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * SenderKey store implementasyonu. Room DAO uzerinden persist eder.
 */
@Singleton
class CryptoSenderKeyStoreImpl @Inject constructor(
    private val senderKeyDao: SenderKeyDao
) : CryptoSenderKeyStore {

    override suspend fun loadSenderKey(groupId: String, senderId: String, deviceId: Int): ByteArray? =
        senderKeyDao.get(groupId, senderId, deviceId)?.record

    override suspend fun storeSenderKey(
        groupId: String,
        senderId: String,
        deviceId: Int,
        record: ByteArray
    ) {
        senderKeyDao.put(
            SenderKeyEntity(
                groupId = groupId,
                senderId = senderId,
                deviceId = deviceId,
                record = record,
                updatedAt = System.currentTimeMillis()
            )
        )
    }

    override suspend fun deleteSenderKey(groupId: String, senderId: String, deviceId: Int) {
        senderKeyDao.delete(groupId, senderId, deviceId)
    }

    override suspend fun deleteAllForGroup(groupId: String) {
        senderKeyDao.deleteAllForGroup(groupId)
    }

    override suspend fun containsSenderKey(groupId: String, senderId: String, deviceId: Int): Boolean =
        senderKeyDao.exists(groupId, senderId, deviceId)
}
