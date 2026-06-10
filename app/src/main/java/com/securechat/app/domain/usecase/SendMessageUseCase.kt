package com.securechat.app.domain.usecase

import com.securechat.app.crypto.GroupSenderKeyDistributor
import com.securechat.app.crypto.SessionEnsurer
import com.securechat.app.data.UserSession
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.SecureChatSenderKeyStore
import com.securechat.network.SignalMessage
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.groups.GroupCipher
import org.whispersystems.libsignal.groups.SenderKeyName
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import kotlinx.coroutines.delay
import java.util.Base64
import java.util.UUID
import javax.inject.Inject

/**
 * Mesaj gonderme use case'i.
 *
 * Yavas baglanti durumunda mesaji hemen FAILED olarak isaretlemek yerine,
 * maksimum MAX_RETRY_COUNT kez yeniden deneme yapar. Her denemede
 * RETRY_DELAY_MS kadar bekler. Tum denemeler basarisiz olursa mesaj
 * FAILED olarak isaretlenir; bu arada SENDING durumunda kalir.
 */
class SendMessageUseCase @Inject constructor(
    private val messageRepository: MessageRepository,
    private val signalingClient: SignalingClient,
    private val userSession: UserSession,
    private val conversationDao: ConversationDao,
    private val messageEncryptor: MessageEncryptor,
    private val sessionEnsurer: SessionEnsurer,
    private val groupSenderKeyDistributor: GroupSenderKeyDistributor,
    private val senderKeyStore: SecureChatSenderKeyStore
) {
    companion object {
        /** Mesaj gonderim denemesi basarisiz oldugunda maksimum yeniden deneme sayisi. */
        const val MAX_RETRY_COUNT = 3
        /** Her yeniden deneme arasindaki bekleme suresi (milisaniye). */
        const val RETRY_DELAY_MS = 2000L
    }

    suspend operator fun invoke(
        conversationId: String,
        content: String,
        replyToId: String? = null,
        contentType: MessageContentType = MessageContentType.TEXT,
        isViewOnce: Boolean = false,
        mentionedUserIds: List<String> = emptyList()
    ) {
        val senderId = userSession.userId ?: "unknown"
        val timestamp = System.currentTimeMillis()

        // Grup mu birebir mi kontrol et
        val conversation = conversationDao.getById(conversationId)
        val isGroup = conversation?.isGroup == true

        // Sureli mesaj kontrolu — konusmada sureli mesaj aktifse expiresAt hesapla
        val disappearingDuration = conversation?.disappearingDuration ?: 0
        val expiresAt = if (disappearingDuration > 0) timestamp + disappearingDuration else null

        val message = LocalMessage(
            id = UUID.randomUUID().toString(),
            conversationId = conversationId,
            senderId = senderId,
            peerId = conversationId,
            content = content,
            contentType = contentType,
            timestamp = timestamp,
            status = MessageStatus.SENDING,
            isOutgoing = true,
            replyToId = replyToId,
            expiresAt = expiresAt,
            isViewOnce = isViewOnce
        )
        messageRepository.saveMessage(message)

        // Mesaj icerigi MSGID prefix'i ile gonderilir — alici taraf delivery receipt gonderebilsin
        // REPLY prefix eklenir — alici taraf reply mesajini gorebilsin
        val replyPrefix = if (replyToId != null) "REPLY:$replyToId:" else ""
        // POLL mesajlari POLL: prefix'i ile isaretlenir — alici taraf POLL olarak ayirt edebilsin
        val typePrefix = if (contentType == MessageContentType.POLL) "POLL:" else ""
        // EXP prefix: sureli mesaj icin mutlak expiresAt'i gomeriz — alici da ayni anda gormez
        // olur. Alici lokal duration'i bilmiyorsa veya transit gecikmesi varsa bile dogru calisir.
        val expPrefix = if (expiresAt != null) "EXP:$expiresAt:" else ""
        // VIEWONCE prefix: tek gosterimlik metin mesaji bayragi — POLL/icerikten ONCE.
        // Parser POLL gorunce geri kalanini content sayar; bu yuzden VIEWONCE'u POLL'den
        // once yerlestiriyoruz. Foto/dosya icin FileTransfer.isViewOnce kullanilir.
        val viewOncePrefix = if (isViewOnce) "VIEWONCE:" else ""
        // MENTION prefix: grup mesajinda etiketlenen uye ID'leri — alici tarafta yuksek
        // oncelikli bildirim icin. Sadece grup mesajinda gonderilir; 1:1'de gereksiz.
        // Parser MENTION'i VIEWONCE'tan SONRA, POLL'den ONCE bekler — sirayi koruyoruz.
        val mentionPrefix = if (isGroup && mentionedUserIds.isNotEmpty()) {
            // Guvenlik: csv icindeki virgul/iki nokta'lari userId'lerden temizle (ID'ler UUID).
            val sanitized = mentionedUserIds
                .map { it.replace(",", "").replace(":", "").trim() }
                .filter { it.isNotBlank() }
            if (sanitized.isNotEmpty()) "MENTION:${sanitized.joinToString(",")}:" else ""
        } else ""
        // Sira onemli: EXP, POLL/POLLVOTE'tan ONCE — parser POLL gorunce geri kalanini content
        // sayar. Boylece "MSGID:id:[REPLY:rid:][EXP:abs:][VIEWONCE:][MENTION:csv:][POLL:]content" formati olusur.
        val envelopeContent = "MSGID:${message.id}:${replyPrefix}${expPrefix}${viewOncePrefix}${mentionPrefix}${typePrefix}$content"

        // App uzun sure idle kaldiktan sonra ilk mesajda WS socket'i kapali olabilir. Bu durumda
        // sendSignal direkt false doner ve mesaj 6sn'lik retry penceresinden gecene kadar bekler;
        // socket bu pencere icinde acilmazsa FAILED olur. ensureConnected baglanti bekler — yoksa
        // baglanir (max 8sn) — boylece ilk gonderim cogu zaman tek deneme ile gider.
        // authToken pattern'i AppLifecycleObserver ile ayni: "token_$userId".
        runCatching {
            signalingClient.ensureConnected(
                userId = senderId,
                authToken = userSession.accessToken ?: "",
                timeoutMs = 8_000L
            )
        }

        // E2EE encrypt — SADECE BIR KEZ. Ratchet/sender chain ileri tasindigi icin retry'larda
        // ayni ciphertext'i tekrar gondeririz. Encrypt fail olursa mesaj FAILED isaretlenir;
        // plaintext fallback KESINLIKLE yok — guvenlik kuralina aykiri (CLAUDE.md).
        val wireEnvelope: String = try {
            if (isGroup) {
                buildGroupWireEnvelope(senderId, conversationId, envelopeContent, conversation)
            } else {
                buildDirectWireEnvelope(conversationId, envelopeContent)
            }
        } catch (e: EncryptionFailedException) {
            android.util.Log.e("SendMessage",
                "Encrypt fail — mesaj FAILED isaretleniyor: ${message.id} — ${e.message}")
            messageRepository.updateMessageStatus(message.id, MessageStatus.FAILED)
            return
        }

        // Ilk deneme
        val sent = attemptSend(senderId, conversationId, timestamp, wireEnvelope, isGroup, conversation)

        if (sent) {
            messageRepository.updateMessageStatus(message.id, MessageStatus.SENT)
            return
        }

        // Ilk deneme basarisiz — yeniden deneme dongusu (mesaj SENDING olarak kalir)
        android.util.Log.d("SendMessage", "Ilk gonderim basarisiz, yeniden deneme basliyor: ${message.id}")
        for (attempt in 1..MAX_RETRY_COUNT) {
            delay(RETRY_DELAY_MS)
            // Her retry oncesi de baglantiyi dene — socket gec aciliyorsa retry penceresi
            // icinde gercekten kullanilabilir olsun.
            runCatching {
                signalingClient.ensureConnected(
                    userId = senderId,
                    authToken = userSession.accessToken ?: "",
                    timeoutMs = 3_000L
                )
            }
            val retryResult = attemptSend(senderId, conversationId, timestamp, wireEnvelope, isGroup, conversation)
            if (retryResult) {
                messageRepository.updateMessageStatus(message.id, MessageStatus.SENT)
                android.util.Log.d("SendMessage", "Yeniden deneme basarili (deneme #$attempt): ${message.id}")
                return
            }
            android.util.Log.d("SendMessage", "Yeniden deneme basarisiz (deneme #$attempt/$MAX_RETRY_COUNT): ${message.id}")
        }

        // Tum denemeler basarisiz — FAILED olarak isaretle
        android.util.Log.d("SendMessage", "Tum denemeler basarisiz, FAILED: ${message.id}")
        messageRepository.updateMessageStatus(message.id, MessageStatus.FAILED)
    }

    /**
     * Mesaji signaling sunucusu uzerinden gondermeye calisir.
     *
     * @return Mesaj basariyla gonderildiyse true
     */
    private fun attemptSend(
        senderId: String,
        conversationId: String,
        timestamp: Long,
        wireEnvelope: String,
        isGroup: Boolean,
        conversation: com.securechat.storage.entity.ConversationEntity?
    ): Boolean {
        return if (isGroup) {
            val members = conversation?.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            // Sender Keys: tum uyelere AYNI ciphertext gonderilir; her uye kendi
            // SKDM ile turetilmis grup anahtariyla decrypt eder.
            val payloads = members.associateWith { wireEnvelope }
            signalingClient.sendSignal(
                SignalMessage.GroupMessageFanout(
                    senderId = senderId,
                    timestamp = timestamp,
                    groupId = conversationId,
                    recipientPayloads = payloads
                )
            )
        } else {
            signalingClient.sendSignal(
                SignalMessage.EncryptedMessage(
                    senderId = senderId,
                    recipientId = conversationId,
                    timestamp = timestamp,
                    envelope = wireEnvelope
                )
            )
        }
    }

    /**
     * Grup mesaji icin GroupCipher ile sifreleyip "GROUPSK:v1:..." wire envelope dondurur.
     * SKDM dagitimi yoksa best-effort dagitir (asenkron olarak diger uyelere ulasir).
     * Encrypt patlarsa hibrit donem icin eski "GROUP:..." plaintext format'a duser.
     */
    private suspend fun buildGroupWireEnvelope(
        senderId: String,
        groupId: String,
        envelopeContent: String,
        conversation: com.securechat.storage.entity.ConversationEntity?
    ): String {
        val groupName = conversation?.peerName ?: ""
        // SKDM dagitim — best-effort, basarisiz olsa bile encrypt deneriz.
        groupSenderKeyDistributor.ensureDistributed(groupId)

        val plainBytes = envelopeContent.toByteArray(Charsets.UTF_8)
        return try {
            val senderKeyName = SenderKeyName(groupId, SignalProtocolAddress(senderId, GroupSenderKeyDistributor.DEVICE_ID))
            val groupCipher = GroupCipher(senderKeyStore, senderKeyName)
            val ciphertext = groupCipher.encrypt(plainBytes)
            val ctB64 = Base64.getEncoder().encodeToString(ciphertext)
            "GROUPSK:v1:$groupId:$groupName:$ctB64"
        } catch (e: Exception) {
            // Plaintext fallback KALDIRILDI (2026-06-09 guvenlik fix).
            // Grup encrypt fail → mesaj FAILED isaretlenir, UI'da kullanici yeniden dener.
            throw EncryptionFailedException("Grup encrypt fail: ${e.message}", e)
        } finally {
            plainBytes.fill(0)
        }
    }

    /** 1:1 mesaj icin SessionCipher ile sifreleyip "E2EE:v1:..." wire envelope dondurur. */
    private suspend fun buildDirectWireEnvelope(recipientId: String, envelopeContent: String): String {
        val sessionOk = sessionEnsurer.ensureSession(recipientId)
        if (!sessionOk) {
            // Plaintext fallback KALDIRILDI (2026-06-09 guvenlik fix).
            // Session kurulamadi → mesaj FAILED isaretlenir; PreKeyBundle fetch'i bir
            // sonraki gonderim denemesinde tekrar tetiklenir (network gecici sorunu).
            throw EncryptionFailedException("Session kurulamadi: $recipientId")
        }
        val plainBytes = envelopeContent.toByteArray(Charsets.UTF_8)
        return try {
            val cipher = messageEncryptor.encrypt(recipientId, plainBytes)
            val cipherB64 = Base64.getEncoder().encodeToString(cipher.content)
            "E2EE:v1:${cipher.type.name}:${cipher.senderRegistrationId}:$cipherB64"
        } catch (e: Exception) {
            throw EncryptionFailedException("1:1 encrypt fail: ${e.message}", e)
        } finally {
            plainBytes.fill(0)
        }
    }
}

/**
 * Encrypt veya session kurulumu basarisiz oldugunda firlatilir.
 * SendMessageUseCase ana akisinda yakalanir → mesaj FAILED isaretlenir.
 * Plaintext fallback'in (mesaji sifresiz gonderme) yerini alir.
 */
class EncryptionFailedException(message: String, cause: Throwable? = null) : Exception(message, cause)
