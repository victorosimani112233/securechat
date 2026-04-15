package com.securechat.storage.crypto

import com.securechat.crypto.store.CryptoSignedPreKeyStore
import com.securechat.storage.dao.SignedPreKeyDao
import com.securechat.storage.entity.SignedPreKeyEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Signed PreKey store implementasyonu. Room DAO uzerinden persist eder.
 */
@Singleton
class CryptoSignedPreKeyStoreImpl @Inject constructor(
    private val signedPreKeyDao: SignedPreKeyDao
) : CryptoSignedPreKeyStore {

    override suspend fun loadSignedPreKey(signedPreKeyId: Int): ByteArray? =
        signedPreKeyDao.get(signedPreKeyId)?.record

    override suspend fun loadAllSignedPreKeys(): List<ByteArray> =
        signedPreKeyDao.getAll().map { it.record }

    override suspend fun storeSignedPreKey(signedPreKeyId: Int, record: ByteArray) {
        signedPreKeyDao.insert(
            SignedPreKeyEntity(
                id = signedPreKeyId,
                record = record,
                createdAt = System.currentTimeMillis()
            )
        )
    }

    override suspend fun containsSignedPreKey(signedPreKeyId: Int): Boolean =
        signedPreKeyDao.exists(signedPreKeyId)

    override suspend fun removeSignedPreKey(signedPreKeyId: Int) {
        signedPreKeyDao.delete(signedPreKeyId)
    }
}
