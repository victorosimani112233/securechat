package com.securechat.app.data.incoming.handlers

import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.RecordExportEventUseCase
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.useAndZeroize
import com.securechat.network.SignalMessage
import com.securechat.storage.dao.ExportLogDao
import com.securechat.storage.entity.ExportLogEntity
import org.json.JSONObject
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Admin-only encrypted log mesaji islenir (zero-knowledge audit).
 *
 * Akis:
 *  1. Lokal userId, adminPayloads.keys icinde mi? Yoksa sessizce drop
 *     (non-admin client veya yeni atanan admin'in atanmadan onceki log).
 *  2. Kendi payload'imizi cek, MessageEncryptor.decrypt ile coz.
 *  3. JSON ayristir, ExportLogDao'ya kaydet (sadece bu cihazda decrypt'lediklerimiz).
 *
 * Yetkisiz veya hatali payload'lar SESSIZCE atilir — bilgi sizdirmaz.
 *
 * Faz 10: IncomingMessageHandler.handleAdminEncryptedLog extract edildi.
 */
@Singleton
class AdminEncryptedLogHandler @Inject constructor(
    private val userSession: UserSession,
    private val messageEncryptor: MessageEncryptor,
    private val exportLogDao: ExportLogDao
) : SignalHandler<SignalMessage.AdminEncryptedLog> {

    override suspend fun handle(signal: SignalMessage.AdminEncryptedLog) {
        val localUserId = userSession.userId ?: return
        val combined = signal.adminPayloads[localUserId] ?: return  // bizim icin degil, drop

        try {
            val envelope = RecordExportEventUseCase.decodeEnvelope(combined) ?: return
            val plaintext = messageEncryptor.decrypt(signal.senderId, envelope)
            plaintext.useAndZeroize { bytes ->
                val json = JSONObject(String(bytes, Charsets.UTF_8))
                val entry = ExportLogEntity(
                    id = UUID.randomUUID().toString(),
                    groupId = signal.groupId,
                    actorUserId = json.optString("actorUserId", signal.senderId),
                    actorDisplayName = json.optString("actorDisplayName", signal.senderId),
                    eventType = json.optString("eventType", signal.eventType),
                    timestamp = json.optLong("timestamp", signal.timestamp),
                    messageCount = json.optInt("messageCount", 0),
                    firstMsgTs = if (json.has("firstMsgTs")) json.optLong("firstMsgTs") else null,
                    lastMsgTs = if (json.has("lastMsgTs")) json.optLong("lastMsgTs") else null
                )
                exportLogDao.insert(entry)
                android.util.Log.d(
                    "AdminEncryptedLogHandler",
                    "Log alindi: ${entry.eventType} from ${entry.actorUserId} in ${entry.groupId}"
                )
            }
        } catch (e: Exception) {
            // Decrypt fail (session yok, yanlis kisi vb): sessizce drop — bilgi sizdirma
            android.util.Log.w(
                "AdminEncryptedLogHandler",
                "Decrypt fail (sessizce atildi): ${e.javaClass.simpleName}"
            )
        }
    }
}
