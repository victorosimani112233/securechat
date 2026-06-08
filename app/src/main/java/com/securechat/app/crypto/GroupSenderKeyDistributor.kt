package com.securechat.app.crypto

import com.securechat.app.data.UserSession
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.SecureChatSenderKeyStore
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ConversationDao
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.groups.GroupSessionBuilder
import org.whispersystems.libsignal.groups.SenderKeyName
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Grup mesajlasmasinda Sender Keys protokolu icin SKDM
 * (SenderKeyDistributionMessage) uretimi ve uyelere dagitimini yonetir.
 *
 * Akis:
 * 1. distributeToGroup(groupId): yerel sender key uret (GroupSessionBuilder.create)
 * 2. Her uyeye 1:1 Signal session uzerinden SKDM gonder ("SKDM:groupId:b64" envelope)
 * 3. Tracker ile gonderilmis uyeleri kaydet — duplicate fanout'u onler
 *
 * Concurrent: ayni grup icin tek seferde tek distribute calismasi icin per-group Mutex.
 *
 * GUVENLIK: SKDM 1:1 Signal session uzerinden tasinir (E2EE). Server icerigi goremez.
 */
@Singleton
class GroupSenderKeyDistributor @Inject constructor(
    private val senderKeyStore: SecureChatSenderKeyStore,
    private val sessionEnsurer: SessionEnsurer,
    private val messageEncryptor: MessageEncryptor,
    private val signalingClient: SignalingClient,
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val tracker: GroupSenderKeyTracker
) {
    private val perGroupMutexes = ConcurrentHashMap<String, Mutex>()

    /**
     * Grubun tum uyelerine yerel sender key'i SKDM ile dagitir. Daha onceden
     * dagitilmis uyelere tekrar gondermez (tracker). Yeni sender key uretmez
     * — store'da yoksa GroupSessionBuilder.create dogal olarak olusturur.
     *
     * @return Tum uyelere dagitildiysa true; en az bir hata varsa false
     */
    suspend fun ensureDistributed(groupId: String): Boolean = mutexFor(groupId).withLock {
        val senderId = userSession.userId ?: return@withLock false
        val conv = conversationDao.getById(groupId) ?: return@withLock false
        val members = conv.groupMembers
            ?.split(",")
            ?.map { it.trim() }
            ?.filter { it.isNotBlank() && it != senderId }
            ?: emptyList()
        if (members.isEmpty()) return@withLock true

        // Yerel sender key olustur (yoksa) — GroupSessionBuilder.create otomatik persist eder.
        val senderKeyName = SenderKeyName(groupId, SignalProtocolAddress(senderId, DEVICE_ID))
        val skdm = try {
            GroupSessionBuilder(senderKeyStore).create(senderKeyName)
        } catch (e: Exception) {
            android.util.Log.w("GroupSKDistrib", "SKDM uretimi basarisiz ($groupId): ${e.message}")
            return@withLock false
        }
        val skdmBytes = skdm.serialize()
        val skdmB64 = Base64.getEncoder().encodeToString(skdmBytes)
        val skdmEnvelope = "SKDM:$groupId:$skdmB64"

        var allOk = true
        for (memberId in members) {
            if (tracker.isDistributed(groupId, memberId)) continue
            val ok = sendSkdmTo(memberId, senderId, skdmEnvelope)
            if (ok) tracker.markDistributed(groupId, memberId)
            else allOk = false
        }
        allOk
    }

    /**
     * Tek uyeye SKDM gonderir. Yeni uye eklendiginde (handleGroupNotification) cagrilir.
     */
    suspend fun distributeToMember(groupId: String, memberId: String): Boolean = mutexFor(groupId).withLock {
        val senderId = userSession.userId ?: return@withLock false
        if (memberId == senderId) return@withLock true

        val senderKeyName = SenderKeyName(groupId, SignalProtocolAddress(senderId, DEVICE_ID))
        val skdm = try {
            GroupSessionBuilder(senderKeyStore).create(senderKeyName)
        } catch (e: Exception) {
            android.util.Log.w("GroupSKDistrib", "SKDM uretimi basarisiz ($groupId): ${e.message}")
            return@withLock false
        }
        val skdmEnvelope = "SKDM:$groupId:${Base64.getEncoder().encodeToString(skdm.serialize())}"
        val ok = sendSkdmTo(memberId, senderId, skdmEnvelope)
        if (ok) tracker.markDistributed(groupId, memberId)
        ok
    }

    /**
     * Grup icin yerel sender key'i sifirlar ve yeniden tum uyelere dagitir.
     * Forward secrecy icin uye cikarmada veya periyodik (7 gun) cagrilmali.
     */
    suspend fun rotate(groupId: String): Boolean = mutexFor(groupId).withLock {
        val senderId = userSession.userId ?: return@withLock false
        // Eski sender key'i sil — yeni create cagrisi sifirdan baslar.
        senderKeyStore.let {
            val name = SenderKeyName(groupId, SignalProtocolAddress(senderId, DEVICE_ID))
            // SenderKeyStore arayuzunde silme yok; backing store uzerinden temizlemek icin
            // bos record overwrite et — dogru yontem CryptoSenderKeyStore.deleteSenderKey'i
            // cagirmaktir. Bu rotate icin async cagri yapmamiz gerekiyor.
            try {
                // Direkt async store erisimi yok burada — alternatif: bos SenderKeyRecord persist
                // ederek state'i sifirla. GroupSessionBuilder.create sonraki cagri ile yeni
                // chain key uretir.
                it.storeSenderKey(name, org.whispersystems.libsignal.groups.state.SenderKeyRecord())
            } catch (e: Exception) {
                android.util.Log.w("GroupSKDistrib", "Sender key sifirlama hatasi: ${e.message}")
            }
        }
        tracker.clearGroup(groupId)
        // Yeniden dagit
        ensureDistributedInternal(groupId)
    }

    private suspend fun ensureDistributedInternal(groupId: String): Boolean {
        val senderId = userSession.userId ?: return false
        val conv = conversationDao.getById(groupId) ?: return false
        val members = conv.groupMembers
            ?.split(",")
            ?.map { it.trim() }
            ?.filter { it.isNotBlank() && it != senderId }
            ?: emptyList()
        if (members.isEmpty()) return true

        val senderKeyName = SenderKeyName(groupId, SignalProtocolAddress(senderId, DEVICE_ID))
        val skdm = try {
            GroupSessionBuilder(senderKeyStore).create(senderKeyName)
        } catch (e: Exception) {
            return false
        }
        val skdmEnvelope = "SKDM:$groupId:${Base64.getEncoder().encodeToString(skdm.serialize())}"

        var allOk = true
        for (memberId in members) {
            val ok = sendSkdmTo(memberId, senderId, skdmEnvelope)
            if (ok) tracker.markDistributed(groupId, memberId) else allOk = false
        }
        return allOk
    }

    /**
     * SKDM'i hedef uyeye 1:1 Signal session uzerinden gonderir.
     * Session yoksa kurar; encrypt fail ederse false doner.
     */
    private suspend fun sendSkdmTo(memberId: String, senderId: String, skdmEnvelope: String): Boolean {
        val sessionOk = sessionEnsurer.ensureSession(memberId)
        if (!sessionOk) {
            android.util.Log.w("GroupSKDistrib", "1:1 session kurulamadi, SKDM atlandi: $memberId")
            return false
        }
        val plain = skdmEnvelope.toByteArray(Charsets.UTF_8)
        val wireEnvelope = try {
            val cipher = messageEncryptor.encrypt(memberId, plain)
            val cipherB64 = Base64.getEncoder().encodeToString(cipher.content)
            "E2EE:v1:${cipher.type.name}:${cipher.senderRegistrationId}:$cipherB64"
        } catch (e: Exception) {
            android.util.Log.w("GroupSKDistrib", "SKDM encrypt hatasi ($memberId): ${e.message}")
            return false
        } finally {
            plain.fill(0)
        }
        return signalingClient.sendSignal(
            SignalMessage.EncryptedMessage(
                senderId = senderId,
                recipientId = memberId,
                timestamp = System.currentTimeMillis(),
                envelope = wireEnvelope
            )
        )
    }

    private fun mutexFor(groupId: String): Mutex =
        perGroupMutexes.computeIfAbsent(groupId) { Mutex() }

    companion object {
        const val DEVICE_ID = 1
    }
}
