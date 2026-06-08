package com.securechat.app.domain.usecase

import com.securechat.app.data.UserSession
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.resolver.ContactNameResolver
import org.json.JSONObject
import java.util.Base64
import javax.inject.Inject

/**
 * Grup admin'lerine sifrelenmis ozet export olay kaydi gonderir (zero-knowledge audit).
 *
 * Akis:
 *  1. Grup admin listesini al
 *  2. Her admin icin Signal Protocol session uzerinden ozet JSON'u sifrele
 *  3. Olusan adminPayloads map'ini SignalMessage.AdminEncryptedLog ile gonder
 *  4. Server her grup uyesine fanout yapar; non-admin client'lar adminPayloads'ta
 *     kendi userId'leri bulunmadigi icin sessizce filtreler.
 *
 * Eger bir admin ile Signal session henuz kurulmamissa o admin payload'a DAHIL EDILMEZ
 * — yeni atanan ve henuz mesajlasmamis admin'lerin gecmis loglari gormemesi gereksinimi
 * ile uyumlu (kasitli davranis).
 */
class RecordExportEventUseCase @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val messageEncryptor: MessageEncryptor,
    private val sessionEnsurer: com.securechat.app.crypto.SessionEnsurer,
    private val contactNameResolver: ContactNameResolver
) {

    // JSON payload format'i sade — manuel JSONObject ile serileze edilir.
    // Wire schema:
    //   { actorUserId, actorDisplayName, eventType, timestamp,
    //     messageCount, firstMsgTs?, lastMsgTs? }

    /**
     * @param groupId Hedef grup ID
     * @param eventType "EXPORT" (gelecekte genisleyebilir)
     * @param messageCount Export'a dahil mesaj sayisi
     * @param firstMsgTs / lastMsgTs Export tarih araligi (null ise tum sohbet)
     * @return Basariyla en az bir admin'e sifrelenip gonderildiyse true.
     */
    suspend operator fun invoke(
        groupId: String,
        eventType: String,
        messageCount: Int,
        firstMsgTs: Long? = null,
        lastMsgTs: Long? = null
    ): Boolean {
        val userId = userSession.userId ?: return false
        val conversation = conversationDao.getById(groupId) ?: return false
        if (!conversation.isGroup) return false

        val adminIds = conversation.groupAdmins?.split(",")?.filter { it.isNotBlank() }
            ?: emptyList()
        if (adminIds.isEmpty()) {
            android.util.Log.d("RecordExportEvent", "Admin yok, log atilmadi: $groupId")
            return false
        }

        val actorName = try {
            contactNameResolver.resolveDisplayName(userId)
        } catch (_: Exception) {
            userSession.displayName ?: userId
        }

        val payloadObj = JSONObject().apply {
            put("actorUserId", userId)
            put("actorDisplayName", actorName)
            put("eventType", eventType)
            put("timestamp", System.currentTimeMillis())
            put("messageCount", messageCount)
            if (firstMsgTs != null) put("firstMsgTs", firstMsgTs)
            if (lastMsgTs != null) put("lastMsgTs", lastMsgTs)
        }
        val plaintext = payloadObj.toString().toByteArray(Charsets.UTF_8)

        // Her admin icin ayri ciphertext uret.
        // Faz 2: SessionEnsurer ile session yoksa PreKeyBundle fetch + X3DH yapilir,
        // boylece YENI atanan ve henuz mesajlasmamis admin'ler de bundan SONRAKI
        // log'lari alabilir (gecmis log'lar yine kasitli olarak gozukmez — eski
        // payload'larda onlarin userId'si yoktur).
        val payloads = mutableMapOf<String, String>()
        for (adminId in adminIds) {
            if (adminId == userId) continue  // kendine sifrelemeye gerek yok
            try {
                if (!sessionEnsurer.ensureSession(adminId)) {
                    android.util.Log.w(
                        "RecordExportEvent",
                        "Session kurulamadi, skip: $adminId (PreKeyBundle fetch fail veya server offline)"
                    )
                    continue
                }
                val envelope: EncryptedEnvelope = messageEncryptor.encrypt(adminId, plaintext)
                // type + content + senderRegistrationId tek bir taşıyıcıda
                val combined = encodeEnvelope(envelope)
                payloads[adminId] = combined
            } catch (e: Exception) {
                android.util.Log.w(
                    "RecordExportEvent",
                    "Admin icin sifreleme basarisiz, skip: $adminId (${e.javaClass.simpleName})"
                )
            }
        }

        // Plaintext'i mumkun oldugu kadar erken sifirla
        plaintext.fill(0)

        if (payloads.isEmpty()) {
            android.util.Log.w("RecordExportEvent", "Hicbir admin icin session yok, log gonderilemedi")
            return false
        }

        val signal = SignalMessage.AdminEncryptedLog(
            senderId = userId,
            timestamp = System.currentTimeMillis(),
            groupId = groupId,
            eventType = eventType,
            adminPayloads = payloads
        )
        val sent = signalingClient.sendSignal(signal)
        android.util.Log.d(
            "RecordExportEvent",
            "Admin log gonderildi (sent=$sent, recipients=${payloads.size}/${adminIds.size})"
        )
        return sent
    }

    /**
     * EncryptedEnvelope'u tek string'e paketler — "TYPE:REG_ID:BASE64".
     * Decrypt tarafinda ters yon `RecordExportEventUseCase.decodeEnvelope` ile yapilir.
     */
    private fun encodeEnvelope(env: EncryptedEnvelope): String {
        val b64 = Base64.getEncoder().encodeToString(env.content)
        return "${env.type.name}:${env.senderRegistrationId}:$b64"
    }

    companion object {
        /**
         * IncomingMessageHandler tarafindan decrypt'te kullanilir — wire format
         * gondericiyle ayni olsun diye burada tek noktada tutulur.
         */
        fun decodeEnvelope(combined: String): EncryptedEnvelope? {
            val parts = combined.split(":", limit = 3)
            if (parts.size != 3) return null
            val type = try {
                com.securechat.crypto.model.EnvelopeType.valueOf(parts[0])
            } catch (_: Exception) { return null }
            val regId = parts[1].toIntOrNull() ?: return null
            val content = try { Base64.getDecoder().decode(parts[2]) } catch (_: Exception) { return null }
            return EncryptedEnvelope(
                type = type,
                content = content,
                timestamp = System.currentTimeMillis(),
                senderRegistrationId = regId
            )
        }
    }
}
