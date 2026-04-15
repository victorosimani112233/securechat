package com.securechat.storage.crypto

import com.securechat.crypto.store.CryptoSessionStore
import com.securechat.storage.dao.SessionDao
import com.securechat.storage.entity.SessionEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Session store implementasyonu. Room DAO uzerinden persist eder.
 * Session id formati: "$name:$deviceId"
 */
@Singleton
class CryptoSessionStoreImpl @Inject constructor(
    private val sessionDao: SessionDao
) : CryptoSessionStore {

    override suspend fun loadSession(name: String, deviceId: Int): ByteArray? =
        sessionDao.get(buildSessionId(name, deviceId))?.record

    override suspend fun storeSession(name: String, deviceId: Int, record: ByteArray) {
        sessionDao.insert(SessionEntity(buildSessionId(name, deviceId), record))
    }

    override suspend fun containsSession(name: String, deviceId: Int): Boolean =
        sessionDao.exists(buildSessionId(name, deviceId))

    override suspend fun deleteSession(name: String, deviceId: Int) {
        sessionDao.delete(buildSessionId(name, deviceId))
    }

    override suspend fun deleteAllSessions(name: String) {
        sessionDao.deleteAllForName(name)
    }

    override suspend fun getSubDeviceSessions(name: String): List<Int> {
        return sessionDao.getSessionIdsForName(name).mapNotNull { id ->
            id.substringAfter(":").toIntOrNull()
        }
    }

    /** name ve deviceId'den session id olusturur. */
    private fun buildSessionId(name: String, deviceId: Int): String = "$name:$deviceId"
}
