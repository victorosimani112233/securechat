package com.securechat.storage.crypto

import com.securechat.crypto.store.CryptoPreKeyStore
import com.securechat.storage.dao.PreKeyDao
import com.securechat.storage.entity.PreKeyEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * One-time PreKey store implementasyonu. Room DAO uzerinden persist eder.
 */
@Singleton
class CryptoPreKeyStoreImpl @Inject constructor(
    private val preKeyDao: PreKeyDao
) : CryptoPreKeyStore {

    override suspend fun loadPreKey(preKeyId: Int): ByteArray? =
        preKeyDao.get(preKeyId)?.record

    override suspend fun storePreKey(preKeyId: Int, record: ByteArray) {
        preKeyDao.insert(PreKeyEntity(preKeyId, record))
    }

    override suspend fun containsPreKey(preKeyId: Int): Boolean =
        preKeyDao.exists(preKeyId)

    override suspend fun removePreKey(preKeyId: Int) {
        preKeyDao.delete(preKeyId)
    }

    override suspend fun getAvailablePreKeyCount(): Int =
        preKeyDao.count()

    override suspend fun getNextPreKeyId(): Int =
        (preKeyDao.maxId() ?: -1) + 1
}
