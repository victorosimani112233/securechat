package com.securechat.app.data

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import com.securechat.app.IncomingCallActivity
import com.securechat.app.ui.components.ThemeManager
import com.securechat.media.CallManager
import com.securechat.media.FileTransferManager
import com.securechat.media.IncomingCallHandler
import com.securechat.network.NetworkTypeProvider
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.CallAction
import com.securechat.network.model.ConnectionState
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Signaling sunucusundan gelen tum mesajlari isleyen sinif.
 *
 * Mesaj tiplerine gore uygun isleyicilere yonlendirir:
 * - EncryptedMessage -> Mesaj deposuna kaydeder
 * - FileTransfer -> Dosyayi kaydeder ve mesaj olarak isler
 * - SdpOffer -> CallManager'a gelen arama olarak iletir
 * - SdpAnswer -> CallManager'a SDP answer olarak iletir (WebRTC P2P)
 * - IceCandidate -> CallManager'a ICE candidate olarak iletir (WebRTC P2P)
 * - CallControl -> Arama kontrol aksiyonlarini isler
 * - AudioData/VideoData -> Artik kullanilmiyor (WebRTC P2P medya akisi)
 */
private const val ELCIM_SUMMARY_ID = 0
private const val ELCIM_PRIVACY_NOTIF_ID = 1

@Singleton
class IncomingMessageHandler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val signalingClient: SignalingClient,
    private val messageRepository: MessageRepository,
    private val conversationDao: ConversationDao,
    private val contactDao: com.securechat.storage.dao.ContactDao,
    private val callManager: CallManager,
    private val fileTransferManager: FileTransferManager,
    private val userSession: UserSession,
    private val incomingCallHandler: IncomingCallHandler,
    private val ringtonePlayer: com.securechat.media.RingtonePlayer,
    private val missedCallTracker: MissedCallTracker,
    private val themeManager: ThemeManager,
    private val phoneAccountRegistrar: dagger.Lazy<com.securechat.telecom.PhoneAccountRegistrar>,
    private val exportBannerAckStore: ExportBannerAckStore,
    private val messageEncryptor: com.securechat.crypto.MessageEncryptor,
    private val sessionManager: com.securechat.crypto.SessionManager,
    private val exportLogDao: com.securechat.storage.dao.ExportLogDao,
    private val senderKeyStore: com.securechat.crypto.SecureChatSenderKeyStore,
    private val groupSenderKeyDistributor: com.securechat.app.crypto.GroupSenderKeyDistributor,
    private val oneToOneFileCipher: com.securechat.media.crypto.OneToOneFileCipher,
    // Faz 10: handler'lar — kademeli extract
    private val deliveryReceiptHandler: com.securechat.app.data.incoming.handlers.DeliveryReceiptHandler,
    private val typingPresenceHandler: com.securechat.app.data.incoming.handlers.TypingPresenceHandler,
    private val disappearingTimerHandler: com.securechat.app.data.incoming.handlers.DisappearingTimerHandler,
    private val messageEditDeleteHandler: com.securechat.app.data.incoming.handlers.MessageEditDeleteHandler,
    private val adminEncryptedLogHandler: com.securechat.app.data.incoming.handlers.AdminEncryptedLogHandler,
    private val groupCallStateHandler: com.securechat.app.data.incoming.handlers.GroupCallStateHandler,
    // F5: auto-download policy — gelen medya/dosya icin disk-keep karari
    private val autoDownloadPolicyStore: AutoDownloadPolicyStore,
    private val autoDownloadDecider: AutoDownloadDecider,
    private val networkTypeProvider: NetworkTypeProvider
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Bildirim ikonu icin onbelleklenmis bitmap — her bildirimde yeniden olusturulmasin diye. */
    private var cachedAppIconBitmap: android.graphics.Bitmap? = null

    companion object {
        /** Sureli mesaj timer signal'i ile gelen mesaj arasindaki race penceresi (ms). */
        private const val RACE_WINDOW_MS = 60_000L

        /** Uygulama on plandaysa true — backing flow ile observe edilebilir. */
        private val _isAppInForegroundFlow = kotlinx.coroutines.flow.MutableStateFlow(false)
        val isAppInForegroundFlow: kotlinx.coroutines.flow.StateFlow<Boolean> = _isAppInForegroundFlow

        var isAppInForeground: Boolean
            get() = _isAppInForegroundFlow.value
            set(value) { _isAppInForegroundFlow.value = value }

        /** Simdiki acik olan sohbet ID'si - bu sohbetten gelen mesajlar icin bildirim gosterilmez */
        @Volatile
        var currentChatId: String? = null

        /** Yazmakta olan kullanicilarin durumu: peerId -> true/false */
        val typingStates = kotlinx.coroutines.flow.MutableStateFlow<Map<String, Boolean>>(emptyMap())

        /** Kullanicilarin cevrimici durumu: peerId -> PresenceInfo */
        val presenceStates = kotlinx.coroutines.flow.MutableStateFlow<Map<String, PresenceInfo>>(emptyMap())

        /** Karsi tarafin kamera durumu — video arama sirasinda kullanilir */
        val remoteCameraEnabled = kotlinx.coroutines.flow.MutableStateFlow(true)

        /** Aktif grup arama durumu — ChatScreen banner'i bu state'i observe eder. */
        data class ActiveGroupCallInfo(
            val groupId: String,
            val callId: String,
            val coordinatorId: String,
            val callType: com.securechat.network.model.CallType,
            val participants: List<String>,
            val mode: String, // MESH veya SFU
            val sfuRoomId: Long? = null,
            val janusWsUrl: String? = null
            // GUVENLIK: apiSecret BURADAN KALDIRILDI (C2 fix) — Janus auth Nginx katmaninda.
        )
        val activeGroupCalls = kotlinx.coroutines.flow.MutableStateFlow<Map<String, ActiveGroupCallInfo>>(emptyMap())

        /** Bildirim mesaj sayaci — sohbet basina mesaj sayisi ve son mesajlar */
        private val notifMessageCount = mutableMapOf<String, Int>()
        private val notifRecentMessages = mutableMapOf<String, MutableList<Pair<String, Long>>>() // content, timestamp

        /** Uygulama acildiginda veya bildirimler temizlendiginde sayaclari sifirla */
        fun clearNotificationCounts() {
            notifMessageCount.clear()
            notifRecentMessages.clear()
        }

        /** Tek bir konusmanin bildirim sayacini sifirla (kullanici swipe ile dismiss etti) */
        fun clearConversationNotificationCount(conversationId: String) {
            notifMessageCount.remove(conversationId)
            notifRecentMessages.remove(conversationId)
        }
    }

    data class PresenceInfo(val isOnline: Boolean, val lastSeen: Long)

    fun start() {
        // Baglanti kopunca peerleri offline isaretle ama lastSeen bilgisini koru
        signalingClient.onConnectionLostListener = {
            val updated = presenceStates.value.mapValues { (_, info) ->
                info.copy(isOnline = false)
            }
            presenceStates.value = updated
            android.util.Log.d("IncomingHandler", "Baglanti koptu, peerler offline isaretlendi (lastSeen korundu)")
        }

        // WebSocket (yeniden) baglaninca: ASLA otomatik online gonderme.
        // Presence sadece Activity.onResume/onPause ile kontrol edilir.
        // Foreground servis reconnect yaptiginda kullaniciyi online gostermemeli.
        signalingClient.onConnectedListener = null

        // CallManager.callSession terminal state'ine gectiğinde:
        // - ESKI: activeGroupCalls'tan grubu hemen silerdi → "ben aramadan ciktim ama
        //   digerleri devam ediyor" senaryosunda banner kaybolurdu, sohbete tekrar
        //   girince yeniden gelirdi. Bu yanlistir: yerel cikis ≠ aramanin bitmesi.
        // - YENI: sunucuya fresh GroupCallStatusQuery gonderilir, gercek durum
        //   handleGroupCallStatusResponse uzerinden update edilir (hala aktifse banner kalir).
        // Ayni collector RINGING'den herhangi bir state'e gecince missed-call timer'i da
        // iptal eder (yanitlanan arama icin hayalet missed bildirim sorununu kapatir).
        scope.launch {
            var lastSeenCallId: String? = null
            var lastSeenState: com.securechat.media.model.CallState? = null
            callManager.callSession.collect { session ->
                // Grup arama banner: yerel session terminal'e dustugunde server'a
                // refresh query gonder — gerçek aktif durum cevapla gelir.
                if (session != null && session.isGroupCall) {
                    val gid = session.groupId
                    val terminal = session.state == com.securechat.media.model.CallState.ENDED ||
                                   session.state == com.securechat.media.model.CallState.FAILED ||
                                   session.state == com.securechat.media.model.CallState.REJECTED ||
                                   session.state == com.securechat.media.model.CallState.BUSY
                    if (terminal && gid != null) {
                        val uid = userSession.userId
                        if (!uid.isNullOrBlank()) {
                            try {
                                signalingClient.sendSignal(
                                    SignalMessage.GroupCallStatusQuery(
                                        senderId = uid,
                                        recipientId = "server",
                                        timestamp = System.currentTimeMillis(),
                                        groupId = gid
                                    )
                                )
                                android.util.Log.d("IncomingHandler", "Yerel cikis sonrasi fresh status query: $gid")
                            } catch (e: Exception) {
                                android.util.Log.w("IncomingHandler", "Status query gonderilemedi: ${e.message}")
                            }
                        }
                    }
                }

                // Missed-call timer iptal: arama RINGING'den herhangi bir state'e gecince.
                // Yerel acceptCall (INCOMING+RINGING → ACTIVE) bu yoldan yakalanir; karsi taraf
                // ACCEPT'i CallControl uzerinden zaten cancel ediyor. Bu collector eksik
                // yolu kapatir — bazen yanitlanmis arama icin gelen sahte missed bildirim sorunu.
                val callId = session?.callId
                val state = session?.state
                if (callId != null && state != null) {
                    val wasRinging = lastSeenCallId == callId &&
                        lastSeenState == com.securechat.media.model.CallState.RINGING
                    val leftRinging = wasRinging && state != com.securechat.media.model.CallState.RINGING
                    val nowActive = state == com.securechat.media.model.CallState.ACTIVE
                    if (leftRinging || nowActive) {
                        missedCallTracker.cancelMissedCallTimer(callId)
                    }
                    lastSeenCallId = callId
                    lastSeenState = state
                } else if (session == null && lastSeenCallId != null) {
                    // Session temizlendi — son callId icin de iptal et (defansif)
                    lastSeenCallId?.let { missedCallTracker.cancelMissedCallTimer(it) }
                    lastSeenCallId = null
                    lastSeenState = null
                }
            }
        }

        scope.launch {
            signalingClient.incomingSignals.collect { signal ->
                android.util.Log.d("IncomingHandler", "Sinyal geldi: ${signal::class.simpleName} from=${signal.senderId}")
                dispatchSignal(signal)
            }
        }
    }

    /**
     * Tek bir signal'i isler. Flow contract:
     *   - CancellationException PROPAGATE edilir (yapisal coroutine iptal saygisi).
     *   - Diger Throwable'lar yakalanir ve drop edilir — collect lambdasi cancel edilmez,
     *     aksi takdirde signalingClient.incomingSignals flow'u kapanir ve WebSocket
     *     reconnect dongusune girer (kullanici "mesajlar gitmiyor" hatasi).
     *
     * Per-signal hata izolasyonu: bir signal'in islenmesi diger signal'larin akisini
     * etkilemez. Bu tasarim Signal Protocol decrypt fail (NoSession, InvalidMessage)
     * gibi expected exception'larin WS state'ini bozmasini onler.
     */
    private suspend fun dispatchSignal(signal: SignalMessage) {
        try {
            // Signal isleme Dispatchers.Default'a kaydirilir — Signal Protocol senkron
            // callback'leri (SessionStore, SenderKeyStore) `runBlocking(Dispatchers.IO)`
            // kullanir. Eger collect lambdasi da IO'daysa (mevcut scope IO),
            // runBlocking ayni IO thread'ini bloke eder, WebSocket frame okuma durur,
            // server ping timeout uygulayip baglantiyi koparir. Default dispatcher'ina
            // gecmek bu deadlock-benzeri darbogazi kaldirir.
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            when (signal) {
                is SignalMessage.EncryptedMessage -> handleEncryptedMessage(signal)
                is SignalMessage.FileTransfer -> handleFileTransfer(signal)
                is SignalMessage.SdpOffer -> {
                    if (callManager.isCurrentCallGroup) callManager.handleGroupSdpOffer(signal)
                    else handleIncomingCall(signal)
                }
                is SignalMessage.SdpAnswer -> {
                    if (callManager.isCurrentCallGroup) callManager.handleGroupSdpAnswer(signal)
                    else callManager.handleSdpAnswer(signal)
                }
                is SignalMessage.IceCandidate -> {
                    if (callManager.isCurrentCallGroup) callManager.handleGroupIceCandidate(signal)
                    else callManager.handleIceCandidate(signal)
                }
                is SignalMessage.CallControl -> {
                    android.util.Log.d("IncomingHandler", "CallControl: ${signal.action}")
                    handleCallControl(signal)
                }
                is SignalMessage.GroupNotification -> {
                    android.util.Log.d("IncomingHandler", "GroupNotification: ${signal.action} for group ${signal.groupId}")
                    handleGroupNotification(signal)
                }
                is SignalMessage.DeliveryReceipt -> deliveryReceiptHandler.handle(signal)
                is SignalMessage.MessageDelete -> messageEditDeleteHandler.onDelete(signal)
                is SignalMessage.MessageEdit -> messageEditDeleteHandler.onEdit(signal)
                is SignalMessage.MessagePin -> handleMessagePin(signal)
                is SignalMessage.DisappearingTimer -> disappearingTimerHandler.handle(signal)
                is SignalMessage.TypingIndicator -> typingPresenceHandler.onTyping(signal, scope)
                is SignalMessage.PresenceUpdate -> typingPresenceHandler.onPresence(signal)
                is SignalMessage.GroupCallInvite -> handleGroupCallInvite(signal)
                is SignalMessage.GroupCallMemberJoined -> callManager.handleGroupCallMemberJoined(signal)
                is SignalMessage.GroupCallMemberLeft -> callManager.handleGroupCallMemberLeft(signal)
                is SignalMessage.GroupCallCoordinatorChanged -> callManager.handleGroupCallCoordinatorChanged(signal)
                is SignalMessage.GroupCallJoinRequest -> callManager.handleGroupCallJoinRequest(signal)
                is SignalMessage.GroupCallStatusResponse -> groupCallStateHandler.onStatusResponse(signal)
                is SignalMessage.GroupCallStatusQuery -> { /* Sunucu tarafinda islenir */ }
                is SignalMessage.SfuRoomCreated -> groupCallStateHandler.onSfuRoomCreated(signal)
                is SignalMessage.AdminEncryptedLog -> adminEncryptedLogHandler.handle(signal)
                is SignalMessage.SessionResetRequest -> handleSessionResetRequest(signal)
                is SignalMessage.PresenceSubscribe -> { /* Sunucu tarafinda islenir */ }
                is SignalMessage.PresenceUnsubscribe -> { /* Sunucu tarafinda islenir */ }
                is SignalMessage.AudioData -> { }
                is SignalMessage.VideoData -> { /* WebRTC P2P — artik kullanilmiyor */ }
                else -> { }
            }
            }  // withContext(Default)
        } catch (ce: kotlinx.coroutines.CancellationException) {
            throw ce
        } catch (t: Throwable) {
            android.util.Log.e(
                "IncomingHandler",
                "Signal islenirken yakalanmamis hata (${signal::class.simpleName} from=${signal.senderId}): ${t.message}",
                t
            )
        }
    }

    /**
     * NoSessionException nedeniyle bekleyen grup mesajlarini gec gelen SKDM
     * tarafindan yeniden islenmek uzere tutar. Her grup icin max 50 entry RAM'de.
     * Key: groupId, Value: pending ciphertext + sender bilgisi.
     */
    private data class PendingGroupMsg(val senderId: String, val groupId: String, val groupName: String, val ciphertextB64: String)
    private val pendingGroupMessages =
        java.util.concurrent.ConcurrentHashMap<String, MutableList<PendingGroupMsg>>()

    private suspend fun handleEncryptedMessage(signal: SignalMessage.EncryptedMessage) {
        val senderId = signal.senderId
        when (val format = com.securechat.app.data.incoming.EnvelopeFormatDetector.detect(signal.envelope)) {
            is com.securechat.app.data.incoming.EnvelopeFormat.DirectE2EE -> handleDirectE2EE(signal, format)
            is com.securechat.app.data.incoming.EnvelopeFormat.GroupV1 -> handleGroupV1(senderId, format)
            is com.securechat.app.data.incoming.EnvelopeFormat.Skdm -> handleSkdm(senderId, format)
            is com.securechat.app.data.incoming.EnvelopeFormat.GroupLegacy -> {
                com.securechat.app.diagnostics.HybridLegacyTelemetry.recordGroupLegacy()
                handleGroupMessage(senderId, format.groupId, format.payload, format.groupName)
            }
            is com.securechat.app.data.incoming.EnvelopeFormat.DirectLegacy -> {
                com.securechat.app.diagnostics.HybridLegacyTelemetry.recordDirectLegacy()
                handleDirectMessage(senderId, format.payload)
            }
            com.securechat.app.data.incoming.EnvelopeFormat.Unknown ->
                android.util.Log.w("IncomingHandler", "Bilinmeyen envelope formati: from=$senderId")
        }
    }

    /**
     * 1:1 E2EE mesaji decrypt edip uygun handler'a yonlendirir.
     * Decrypt sonucu ya plaintext direct mesaj ya da legacy "GROUP:" wrapper olabilir.
     */
    private suspend fun handleDirectE2EE(
        signal: SignalMessage.EncryptedMessage,
        format: com.securechat.app.data.incoming.EnvelopeFormat.DirectE2EE
    ) {
        val senderId = signal.senderId
        val plainStr: String = try {
            val cipherBytes = java.util.Base64.getDecoder().decode(format.ciphertextB64)
            val envelope = com.securechat.crypto.model.EncryptedEnvelope(
                type = format.type,
                content = cipherBytes,
                timestamp = signal.timestamp,
                senderRegistrationId = format.regId
            )
            val plain = messageEncryptor.decrypt(senderId, envelope)
            val s = String(plain, Charsets.UTF_8)
            plain.fill(0)
            s
        } catch (e: org.whispersystems.libsignal.DuplicateMessageException) {
            android.util.Log.d("IncomingHandler", "1:1 duplicate mesaj, ignore: $senderId")
            return
        } catch (e: org.whispersystems.libsignal.InvalidMessageException) {
            android.util.Log.w("IncomingHandler", "1:1 bozuk mesaj (InvalidMessage): $senderId — ${e.message}; auto-heal tetikleniyor")
            triggerSessionHealing(senderId, "invalid_message")
            return
        } catch (e: org.whispersystems.libsignal.NoSessionException) {
            android.util.Log.w("IncomingHandler", "1:1 session yok (gondericinin session'i bizim store'da yok): $senderId; auto-heal tetikleniyor")
            triggerSessionHealing(senderId, "no_session")
            return
        } catch (e: org.whispersystems.libsignal.InvalidKeyException) {
            android.util.Log.w("IncomingHandler", "1:1 identity mismatch (InvalidKey): $senderId — ${e.message}; auto-heal tetikleniyor")
            triggerSessionHealing(senderId, "invalid_key")
            return
        } catch (e: org.whispersystems.libsignal.InvalidKeyIdException) {
            android.util.Log.w("IncomingHandler", "1:1 prekey id bulunamadi: $senderId — ${e.message}; auto-heal tetikleniyor")
            triggerSessionHealing(senderId, "invalid_key_id")
            return
        } catch (e: org.whispersystems.libsignal.UntrustedIdentityException) {
            android.util.Log.w("IncomingHandler", "1:1 untrusted identity: $senderId — ${e.message}; auto-heal tetikleniyor")
            triggerSessionHealing(senderId, "untrusted_identity")
            return
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "1:1 decrypt beklenmeyen hata (${e.javaClass.simpleName}): ${e.message}")
            return
        }

        // Decrypt edilmis icerik SKDM olabilir — 1:1 session uzerinden tasiyoruz (K3)
        when (val inner = com.securechat.app.data.incoming.EnvelopeFormatDetector.detect(plainStr)) {
            is com.securechat.app.data.incoming.EnvelopeFormat.Skdm -> handleSkdm(senderId, inner)
            else -> handleDirectMessage(senderId, plainStr)
        }
    }

    /**
     * Session healing: alici decrypt fail edince tetiklenir.
     *
     * Asimetrik priority (crossed-PreKey race fix): iki taraf ayni anda fail edip
     * ayni anda yeni session kurarsa, her birinin sessionId'si farkli olur ve
     * ratchet uyumsuzlugu sonsuza dek devam eder. Bunu kirmak icin **sadece
     * userId'si daha "buyuk" (lexicographic) olan taraf** session resetlemeyi
     * baslatma yetkisine sahiptir:
     *
     *   - INITIATOR (myId > peerId): local session sil + reset request gonder.
     *     Sonraki encrypt'te PreKey ile yeni session kurar, PREKEY message atar.
     *   - RESPONDER (myId < peerId): SADECE local session sil. Yeni session
     *     kurmayi BEKLER — karsidan gelecek PREKEY message yeni session'i kuracak.
     *     Reset request gondermez (initiator tarafi zaten gonderecek).
     *
     * Bu sayede sadece initiator tarafi PreKeyBundle fetch eder, race ortadan
     * kalkar.
     *
     * Per-peer 5sn dedup: ayni peer icin spam'i onler ama hizli iyilesmeye izin verir.
     */
    private val recentHealRequests = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private fun triggerSessionHealing(peerId: String, reason: String) {
        val myId = userSession.userId
        if (myId == null) {
            android.util.Log.w("IncomingHandler", "Auto-heal: userId yok, atlandi")
            return
        }

        val now = System.currentTimeMillis()
        val last = recentHealRequests[peerId] ?: 0L
        if (now - last < 5_000L) {
            android.util.Log.d("IncomingHandler", "Session heal dedup (son 5sn icinde): $peerId")
            return
        }
        recentHealRequests[peerId] = now

        // Her durumda local bozuk session'i sil
        try {
            sessionManager.resetSession(peerId)
            android.util.Log.d("IncomingHandler", "Local session silindi: $peerId")
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "Local session silinemedi: $peerId — ${e.message}")
        }

        // Asimetrik priority: sadece INITIATOR (buyuk userId) reset request gonderir
        val amInitiator = myId > peerId
        if (amInitiator) {
            val sent = signalingClient.sendSessionResetRequest(peerId, reason)
            android.util.Log.d("IncomingHandler", "[INITIATOR] SessionResetRequest gonderildi ($peerId, reason=$reason): $sent")
        } else {
            android.util.Log.d("IncomingHandler", "[RESPONDER] Karsi tarafin PREKEY mesajini bekliyor: $peerId")
        }
    }

    /**
     * Karsi taraftan gelen session reset talebi — bizim tarafta da session'i siler.
     * Bir sonraki encrypt PreKeyBundle fetch + yeni session ile baslar (PREKEY message).
     */
    private fun handleSessionResetRequest(signal: SignalMessage.SessionResetRequest) {
        val peerId = signal.senderId
        android.util.Log.d("IncomingHandler", "SessionResetRequest alindi: $peerId (reason=${signal.reason})")
        try {
            sessionManager.resetSession(peerId)
            android.util.Log.d("IncomingHandler", "Local session silindi (peer talebi): $peerId")
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "Session silinemedi: $peerId — ${e.message}")
        }
    }

    /** Grup E2EE (GROUPSK:v1) mesaji — GroupCipher ile decrypt. */
    private suspend fun handleGroupV1(
        senderId: String,
        format: com.securechat.app.data.incoming.EnvelopeFormat.GroupV1
    ) {
        val senderKeyName = org.whispersystems.libsignal.groups.SenderKeyName(
            format.groupId,
            org.whispersystems.libsignal.SignalProtocolAddress(senderId, com.securechat.app.crypto.GroupSenderKeyDistributor.DEVICE_ID)
        )
        val groupCipher = org.whispersystems.libsignal.groups.GroupCipher(senderKeyStore, senderKeyName)
        val ciphertext = try {
            java.util.Base64.getDecoder().decode(format.ciphertextB64)
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "Grup ciphertext base64 bozuk: ${e.message}")
            return
        }
        try {
            val plain = groupCipher.decrypt(ciphertext)
            val plainStr = String(plain, Charsets.UTF_8)
            plain.fill(0)
            handleGroupMessage(senderId, format.groupId, plainStr, format.groupName)
        } catch (e: org.whispersystems.libsignal.NoSessionException) {
            // SKDM henuz islenmedi — gec gelmesini bekle, queue'la.
            android.util.Log.w("IncomingHandler", "Grup mesaji SKDM bekliyor: $senderId / ${format.groupId}")
            queuePendingGroupMessage(senderId, format.groupId, format.groupName, format.ciphertextB64)
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "Grup decrypt fail (${e.javaClass.simpleName}): ${e.message}")
        }
    }

    /** SKDM (SenderKeyDistributionMessage) — gondericinin grup sender key'ini process eder. */
    private suspend fun handleSkdm(
        senderId: String,
        format: com.securechat.app.data.incoming.EnvelopeFormat.Skdm
    ) {
        try {
            val bytes = java.util.Base64.getDecoder().decode(format.skdmB64)
            val skdm = org.whispersystems.libsignal.protocol.SenderKeyDistributionMessage(bytes)
            val senderKeyName = org.whispersystems.libsignal.groups.SenderKeyName(
                format.groupId,
                org.whispersystems.libsignal.SignalProtocolAddress(senderId, com.securechat.app.crypto.GroupSenderKeyDistributor.DEVICE_ID)
            )
            org.whispersystems.libsignal.groups.GroupSessionBuilder(senderKeyStore)
                .process(senderKeyName, skdm)
            android.util.Log.d("IncomingHandler", "SKDM islendi: sender=$senderId group=${format.groupId}")
            // SKDM islendikten sonra bekleyen grup mesajlarini retry et
            retryPendingGroupMessages(senderId, format.groupId)
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "SKDM islenemedi (${e.javaClass.simpleName}): ${e.message}")
        }
    }

    private fun queuePendingGroupMessage(senderId: String, groupId: String, groupName: String, ciphertextB64: String) {
        val key = "$groupId:$senderId"
        val list = pendingGroupMessages.computeIfAbsent(key) { mutableListOf() }
        synchronized(list) {
            if (list.size >= 50) list.removeAt(0)
            list.add(PendingGroupMsg(senderId, groupId, groupName, ciphertextB64))
        }
    }

    private suspend fun retryPendingGroupMessages(senderId: String, groupId: String) {
        val key = "$groupId:$senderId"
        val list = pendingGroupMessages.remove(key) ?: return
        val snapshot = synchronized(list) { list.toList() }
        for (m in snapshot) {
            handleGroupV1(
                senderId,
                com.securechat.app.data.incoming.EnvelopeFormat.GroupV1(m.groupId, m.groupName, m.ciphertextB64)
            )
        }
    }

    /**
     * Gelen dosya transferini isler.
     * Dosya yerel depolamaya kaydedilir ve sohbete mesaj olarak eklenir.
     * Resim dosyalari IMAGE, digerleri FILE tipi ile kaydedilir.
     */
    private suspend fun handleFileTransfer(signal: SignalMessage.FileTransfer) {
        val senderId = signal.senderId
        val localUserId = userSession.userId ?: "unknown"

        // Kendi gonderdigimiz grup dosyasini ignore et (zaten lokal olarak kaydedildi)
        if (senderId == localUserId) {
            android.util.Log.d("IncomingHandler", "Kendi dosya mesaji ignore edildi - duplicate prevention")
            return
        }

        // Decrypt:
        //   - "gsk-v1" grup → GroupCipher (Sender Keys)
        //   - "e2ee-v1" 1:1 → SessionCipher (Double Ratchet, Sprint 6-A)
        //   - null → plaintext (hibrit donem)
        val chunkB64 = when {
            signal.encryption == "gsk-v1" && !signal.groupId.isNullOrBlank() -> {
                try {
                    val ct = java.util.Base64.getDecoder().decode(signal.data)
                    val senderKeyName = org.whispersystems.libsignal.groups.SenderKeyName(
                        signal.groupId!!,
                        org.whispersystems.libsignal.SignalProtocolAddress(senderId, com.securechat.app.crypto.GroupSenderKeyDistributor.DEVICE_ID)
                    )
                    val cipher = org.whispersystems.libsignal.groups.GroupCipher(senderKeyStore, senderKeyName)
                    val pt = cipher.decrypt(ct)
                    java.util.Base64.getEncoder().encodeToString(pt)
                } catch (e: Exception) {
                    android.util.Log.w("IncomingHandler", "Grup chunk decrypt fail (${e.javaClass.simpleName}): ${e.message}")
                    return
                }
            }
            signal.encryption == "e2ee-v1" && signal.groupId.isNullOrBlank() -> {
                val ct = try {
                    java.util.Base64.getDecoder().decode(signal.data)
                } catch (e: Exception) {
                    android.util.Log.w("IncomingHandler", "1:1 chunk base64 bozuk: ${e.message}")
                    return
                }
                val pt = oneToOneFileCipher.decrypt(senderId, ct)
                if (pt == null) {
                    android.util.Log.w("IncomingHandler", "1:1 chunk decrypt fail — chunk drop")
                    return
                }
                java.util.Base64.getEncoder().encodeToString(pt)
            }
            else -> signal.data
        }

        // Caption decrypt — chunk ile ayni cipher.
        val decryptedCaption: String? = when {
            signal.caption.isNullOrBlank() -> signal.caption
            signal.encryption == "gsk-v1" && !signal.groupId.isNullOrBlank() -> {
                try {
                    val ct = java.util.Base64.getDecoder().decode(signal.caption)
                    val senderKeyName = org.whispersystems.libsignal.groups.SenderKeyName(
                        signal.groupId!!,
                        org.whispersystems.libsignal.SignalProtocolAddress(senderId, com.securechat.app.crypto.GroupSenderKeyDistributor.DEVICE_ID)
                    )
                    val cipher = org.whispersystems.libsignal.groups.GroupCipher(senderKeyStore, senderKeyName)
                    val pt = cipher.decrypt(ct)
                    val s = String(pt, Charsets.UTF_8)
                    pt.fill(0)
                    s
                } catch (e: Exception) {
                    android.util.Log.w("IncomingHandler", "Caption (group) decrypt fail, plaintext as-is: ${e.message}")
                    signal.caption
                }
            }
            signal.encryption == "e2ee-v1" && signal.groupId.isNullOrBlank() -> {
                try {
                    val ct = java.util.Base64.getDecoder().decode(signal.caption)
                    val pt = oneToOneFileCipher.decrypt(senderId, ct)
                    if (pt != null) {
                        val s = String(pt, Charsets.UTF_8)
                        pt.fill(0)
                        s
                    } else signal.caption
                } catch (e: Exception) {
                    android.util.Log.w("IncomingHandler", "Caption (1:1) decrypt fail, plaintext as-is: ${e.message}")
                    signal.caption
                }
            }
            else -> signal.caption
        }

        // Chunk destekli dosya alma — tek parcali veya coklu parcali
        val savedUri = fileTransferManager.receiveChunk(
            transferId = signal.transferId,
            chunkIndex = signal.chunkIndex,
            totalChunks = signal.totalChunks,
            fileName = signal.fileName,
            mimeType = signal.mimeType,
            fileSize = signal.fileSize,
            data = chunkB64
        )

        // Henuz tum chunk'lar gelmedi — mesaj kaydetme, bekle
        if (savedUri == null && signal.totalChunks > 1 && signal.chunkIndex < signal.totalChunks - 1) {
            android.util.Log.d("IncomingHandler", "Chunk bekleniyor: ${signal.transferId} [${signal.chunkIndex + 1}/${signal.totalChunks}]")
            return
        }

        // F5: Auto-download policy — kullanici tercihi negatifse disk'ten dosyayi sil.
        // E2EE chunked transfer'da ratchet zaten chunk decrypt sirasinda ilerledi;
        // post-receive cleanup yapariz (bant tasarrufu degil, depolama tasarrufu).
        // Mesaj DB kaydi metadata ile birlikte tutulur, filePath="" — UI "indirilmedi"
        // gosterip kullanici manuel re-download tetikleyebilir.
        val autoDownloadAllowed = if (savedUri != null) {
            val policy = autoDownloadPolicyStore.policy.first()
            val category = autoDownloadDecider.categoryFor(signal.mimeType)
            val network = networkTypeProvider.current()
            val allow = autoDownloadDecider.shouldDownload(policy, category, signal.fileSize, network)
            if (!allow) {
                runCatching {
                    val path = savedUri.path
                    if (!path.isNullOrBlank()) {
                        val f = java.io.File(path)
                        if (f.exists() && f.isFile) f.delete()
                    }
                }.onFailure { e ->
                    android.util.Log.w("IncomingHandler", "Auto-download policy: dosya silinemedi: ${e.message}")
                }
                android.util.Log.d(
                    "IncomingHandler",
                    "Auto-download policy negatif (category=$category network=$network size=${signal.fileSize}) — dosya silindi: ${signal.fileName}"
                )
            }
            allow
        } else true

        val filePath = if (autoDownloadAllowed) (savedUri?.path ?: "") else ""

        // Resim dosyalari IMAGE, digerleri FILE olarak siniflandirilir
        val contentType = if (signal.mimeType.startsWith("image/")) {
            MessageContentType.IMAGE
        } else {
            MessageContentType.FILE
        }

        val fileContent = LocalMessage.buildFileContent(
            fileName = signal.fileName,
            mimeType = signal.mimeType,
            fileSize = signal.fileSize,
            filePath = filePath
        )

        val isGroupFile = !signal.groupId.isNullOrBlank()

        if (isGroupFile) {
            // --- Grup dosya mesaji ---
            val groupId = signal.groupId!!
            val groupName = signal.groupName

            val groupConv = conversationDao.getById(groupId)
            if (groupConv == null) {
                // Grup henuz yerel veritabaninda yok — otomatik olustur
                val resolvedGroupName = if (!groupName.isNullOrBlank()) groupName else "Grup"
                android.util.Log.d("IncomingHandler", "Dosya icin grup olusturuluyor: $groupId, isim: $resolvedGroupName")
                conversationDao.insert(
                    ConversationEntity(
                        id = groupId,
                        peerId = groupId,
                        peerName = resolvedGroupName,
                        peerPhone = "",
                        lastMessage = null,
                        lastMessageTimestamp = null,
                        unreadCount = 0,
                        isMuted = false,
                        isPinned = false,
                        isGroup = true,
                        groupMembers = senderId
                    )
                )
            } else {
                // Mevcut grupta senderId yoksa ekle
                val currentMembers = groupConv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                if (senderId !in currentMembers) {
                    val updatedMembers = (currentMembers + senderId).joinToString(",")
                    conversationDao.updateGroupMembers(groupId, updatedMembers)
                }
            }

            val fileNow = System.currentTimeMillis()
            val groupDisappDuration = (groupConv ?: conversationDao.getById(groupId))?.disappearingDuration ?: 0
            // Asama 3: gonderici signal'a absoluteExpiresAt gomduyse onu kullan
            val groupFileExpiresAt = signal.absoluteExpiresAt
                ?: if (groupDisappDuration > 0) fileNow + groupDisappDuration else null
            // isGroupChatOpen sadece bildirim kararinda kullanilir; status DAIMA DELIVERED.
            // READ'e gecis ChatViewModel.markIncomingMessagesAsRead'in sorumlulugu (tek-kaynak).
            val isGroupChatOpen = currentChatId == groupId && isAppInForeground

            val message = LocalMessage(
                id = signal.originalMessageId ?: UUID.randomUUID().toString(),
                conversationId = groupId,
                senderId = senderId,
                peerId = senderId,
                content = fileContent,
                contentType = contentType,
                timestamp = fileNow,
                status = MessageStatus.DELIVERED,
                isOutgoing = false,
                expiresAt = groupFileExpiresAt,
                caption = decryptedCaption?.takeIf { it.isNotBlank() },
                isViewOnce = signal.isViewOnce
            )
            messageRepository.saveMessage(message)

            android.util.Log.d("IncomingHandler", "Grup dosya alindi: ${signal.fileName} -> $groupId")

            // Dosya icin DELIVERED receipt — text mesajlardakine paralel. READ ChatViewModel'in.
            signal.originalMessageId?.let { sendDeliveryReceipt(senderId, it, "DELIVERED") }

            // Grup sohbeti acik degilse bildirim goster (sessiz konusmalar icin sessiz bildirim)
            if (!isGroupChatOpen) {
                val senderName = resolvePeerName(senderId)
                val convForNotif = conversationDao.getById(groupId)
                val displayGroupName = convForNotif?.peerName ?: "Grup"
                val notifBody = decryptedCaption?.takeIf { it.isNotBlank() } ?: "Dosya: ${signal.fileName}"
                showMessageNotification("$senderName ($displayGroupName)", notifBody, groupId)
            }
        } else {
            // --- Birebir dosya mesaji ---
            val senderName = resolvePeerName(senderId)

            val existingConv = conversationDao.getByPeerId(senderId)
            if (existingConv == null) {
                val senderPhone = resolvePeerPhone(senderId)
                conversationDao.insert(
                    ConversationEntity(
                        id = senderId,
                        peerId = senderId,
                        peerName = senderName,
                        peerPhone = senderPhone,
                        lastMessage = null,
                        lastMessageTimestamp = null,
                        unreadCount = 0,
                        isMuted = false,
                        isPinned = false
                    )
                )
            }

            val fileNow = System.currentTimeMillis()
            val fileDisappDuration = existingConv?.disappearingDuration ?: 0
            // Asama 3: gonderici signal'a absoluteExpiresAt gomduyse onu kullan
            val fileExpiresAt = signal.absoluteExpiresAt
                ?: if (fileDisappDuration > 0) fileNow + fileDisappDuration else null
            // isFileChatOpen sadece bildirim kararinda kullanilir; status DAIMA DELIVERED.
            // READ'e gecis ChatViewModel.markIncomingMessagesAsRead'in sorumlulugu (tek-kaynak).
            val isFileChatOpen = currentChatId == senderId && isAppInForeground

            val message = LocalMessage(
                id = signal.originalMessageId ?: UUID.randomUUID().toString(),
                conversationId = senderId,
                senderId = senderId,
                peerId = senderId,
                content = fileContent,
                contentType = contentType,
                timestamp = fileNow,
                status = MessageStatus.DELIVERED,
                isOutgoing = false,
                expiresAt = fileExpiresAt,
                caption = decryptedCaption?.takeIf { it.isNotBlank() },
                isViewOnce = signal.isViewOnce
            )
            messageRepository.saveMessage(message)

            // Dosya icin DELIVERED receipt — text mesajlardakine paralel. READ ChatViewModel'in.
            signal.originalMessageId?.let { sendDeliveryReceipt(senderId, it, "DELIVERED") }

            // Birebir sohbet kapaliysa bildirim goster — caption varsa ozet olarak kullan
            if (!isFileChatOpen) {
                val notifBody = decryptedCaption?.takeIf { it.isNotBlank() } ?: "Dosya: ${signal.fileName}"
                showMessageNotification(senderName, notifBody, senderId)
            }

            android.util.Log.d("IncomingHandler", "Dosya alindi: ${signal.fileName} (${signal.fileSize} byte)")
        }
    }

    /**
     * Grup mesajini isler. Grup konusmasi yoksa otomatik olusturulur,
     * boylece grup uyeleri ilk mesaji kaybetmez.
     *
     * @param groupName Mesajla birlikte gelen grup adi. null ise fallback kullanilir.
     */
    private suspend fun handleGroupMessage(senderId: String, groupId: String, content: String, groupName: String?) {
        val localUserId = userSession.userId ?: "unknown"

        // DUPLICATE FIX: Kendi mesajlarını ignore et (zaten lokal olarak kaydedildi)
        if (senderId == localUserId) {
            android.util.Log.d("IncomingHandler", "Kendi grup mesajı ignore edildi - duplicate prevention")
            return
        }

        // MSGID ve REPLY prefix'lerini ayristir
        val parsedGroup = parseMessageEnvelope(content)
        val originalMessageId = parsedGroup.messageId
        val actualContent = parsedGroup.content
        val groupReplyToId = parsedGroup.replyToId

        // POLLVOTE: grup ankette oy guncellemesi
        if (parsedGroup.pollVote != null) {
            applyRemotePollVote(senderId, parsedGroup.pollVote)
            if (originalMessageId != null) {
                sendDeliveryReceipt(senderId, originalMessageId, "DELIVERED")
            }
            return
        }

        val groupConv = conversationDao.getById(groupId)
        if (groupConv == null) {
            // Grup henuz yerel veritabaninda yok — otomatik olustur
            val resolvedGroupName = if (!groupName.isNullOrBlank()) groupName else "Grup"
            android.util.Log.d("IncomingHandler", "Grup bulunamadi, olusturuluyor: $groupId, isim: $resolvedGroupName")
            conversationDao.insert(
                ConversationEntity(
                    id = groupId,
                    peerId = groupId,
                    peerName = resolvedGroupName,
                    peerPhone = "",
                    lastMessage = null,
                    lastMessageTimestamp = null,
                    unreadCount = 0,
                    isMuted = false,
                    isPinned = false,
                    isGroup = true,
                    // CRITICAL FIX: Geçici olarak sadece senderId, sonradan grup bildirimi ile tam liste gelecek
                    groupMembers = senderId
                )
            )
        } else {
            // CRITICAL FIX: Mevcut grupta senderId yoksa ekle (grup üye senkronizasyonu)
            val currentMembers = groupConv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            if (senderId !in currentMembers) {
                val updatedMembers = (currentMembers + senderId).joinToString(",")
                android.util.Log.d("IncomingHandler", "Grup üyesi eklendi: $senderId -> $groupId")
                conversationDao.updateGroupMembers(groupId, updatedMembers)
            }
        }

        // Sureli mesaj kontrolu — gonderici envelope'a gomduyse onu kullan, yoksa lokal fallback.
        val now = System.currentTimeMillis()
        val groupDisappDuration = (groupConv ?: conversationDao.getById(groupId))?.disappearingDuration ?: 0
        val groupExpiresAt = parsedGroup.absoluteExpiresAt
            ?: if (groupDisappDuration > 0) now + groupDisappDuration else null

        // Mesaj DAIMA DELIVERED ile kaydedilir; READ'e gecisi ChatViewModel.markIncomingMessagesAsRead
        // ustlenir (sohbet aciksa Flow uzerinden yakalanip READ + receipt gonderilir). Boylece
        // gonderici onceleyebilir bir gri-cift-tik -> mavi-cift-tik gecisi gorur (tek-kaynak prensibi).
        // Eski davranis: isGroupChatOpen ise direkt READ idi — DELIVERED adimi atlanip dogrudan
        // mavi cift tik olusuyordu (bug).

        // CRITICAL: Gondericinin orijinal mesaj ID'sini kullan — "herkesten sil" icin gerekli
        val message = LocalMessage(
            id = originalMessageId ?: UUID.randomUUID().toString(),
            conversationId = groupId,
            senderId = senderId,
            peerId = senderId,
            content = actualContent,
            contentType = parsedGroup.contentType,
            timestamp = now,
            status = MessageStatus.DELIVERED,
            replyToId = groupReplyToId,
            isOutgoing = false,
            expiresAt = groupExpiresAt,
            isViewOnce = parsedGroup.isViewOnce
        )
        messageRepository.saveMessage(message)

        // Bildirim goster — anket icin ozel ozet
        val senderName = resolvePeerName(senderId)
        val displayGroupName = groupConv?.peerName ?: groupName ?: "Grup"
        val groupNotifPreview = if (parsedGroup.contentType == MessageContentType.POLL) {
            val q = try { org.json.JSONObject(actualContent).optString("question", "Anket") } catch (_: Exception) { "Anket" }
            "📊 Anket: $q"
        } else actualContent
        // Mention algilama — gonderici MENTION prefix gomduyse + listede localUserId varsa,
        // bildirim mute olsa bile high-priority kanal kullanilir (showMessageNotification icinde
        // @id contains check zaten var; ek olarak structured liste daha guvenilir).
        val isMentioned = parsedGroup.mentionedUserIds.contains(localUserId)
        showMessageNotification(
            "$senderName ($displayGroupName)",
            groupNotifPreview,
            groupId,
            forceHighPriority = isMentioned
        )

        // Receipt: DAIMA DELIVERED. READ receipt'i ChatViewModel.markIncomingMessagesAsRead gonderir
        // (sohbet aciksa Flow uzerinden). Tek-kaynak prensibi: WhatsApp benzeri tik gecisi animasyonel.
        if (originalMessageId != null) {
            sendDeliveryReceipt(senderId, originalMessageId, "DELIVERED")
        }
    }

    /**
     * Birebir mesaji isler. Konusma yoksa yeni konusma olusturur.
     * MSGID prefix'i varsa ayristirilir ve DELIVERED receipt gonderilir.
     */
    private suspend fun handleDirectMessage(senderId: String, content: String) {
        // MSGID ve REPLY prefix'lerini ayristir — geriye uyumluluk icin prefix yoksa da calisir
        val parsed = parseMessageEnvelope(content)
        val originalMessageId = parsed.messageId
        val actualContent = parsed.content
        val replyToId = parsed.replyToId

        // POLLVOTE: yeni mesaj kaydedilmez, mevcut anket guncellenir
        if (parsed.pollVote != null) {
            applyRemotePollVote(senderId, parsed.pollVote)
            if (originalMessageId != null) {
                sendDeliveryReceipt(senderId, originalMessageId, "DELIVERED")
            }
            return
        }

        // Isim cozumle (sunucudan sifreli numara dahil) — bir kez cagir, tekrar kullan
        val senderName = resolvePeerName(senderId)

        // Konusma yoksa olustur
        val existingConv = conversationDao.getByPeerId(senderId)
        if (existingConv == null) {
            val senderPhone = resolvePeerPhone(senderId)
            conversationDao.insert(
                ConversationEntity(
                    id = senderId,
                    peerId = senderId,
                    peerName = senderName,
                    peerPhone = senderPhone,
                    lastMessage = null,
                    lastMessageTimestamp = null,
                    unreadCount = 0,
                    isMuted = false,
                    isPinned = false
                )
            )
        }

        // Sureli mesaj kontrolu — once gondericinin envelope'a gomdugu EXP'i kullan (Asama 3).
        // EXP yoksa (eski client veya timer signal henuz gelmemis) lokal duration'a fallback.
        val now = System.currentTimeMillis()
        val disappDuration = existingConv?.disappearingDuration ?: 0
        val expiresAt = parsed.absoluteExpiresAt
            ?: if (disappDuration > 0) now + disappDuration else null

        // Mesaj DAIMA DELIVERED ile kaydedilir; READ'e gecisi ChatViewModel.markIncomingMessagesAsRead
        // ustlenir (sohbet aciksa Flow uzerinden yakalanip READ + receipt gonderilir). Boylece
        // gonderici onceleyebilir bir gri-cift-tik -> mavi-cift-tik gecisi gorur (tek-kaynak prensibi).
        // Eski davranis: isChatOpen ise direkt READ idi — DELIVERED adimi atlanip dogrudan mavi
        // cift tik olusuyordu (bug).

        // CRITICAL: Gondericinin orijinal mesaj ID'sini kullan — "herkesten sil" icin gerekli
        val message = LocalMessage(
            id = originalMessageId ?: UUID.randomUUID().toString(),
            conversationId = senderId,
            senderId = senderId,
            peerId = senderId,
            content = actualContent,
            contentType = parsed.contentType,
            timestamp = now,
            status = MessageStatus.DELIVERED,
            replyToId = replyToId,
            isOutgoing = false,
            expiresAt = expiresAt,
            isViewOnce = parsed.isViewOnce
        )
        messageRepository.saveMessage(message)

        // Bildirim goster — anket icin ozel ozet
        val notifPreview = if (parsed.contentType == MessageContentType.POLL) {
            val q = try { org.json.JSONObject(actualContent).optString("question", "Anket") } catch (_: Exception) { "Anket" }
            "📊 Anket: $q"
        } else actualContent
        showMessageNotification(senderName, notifPreview, senderId)

        // Receipt: DAIMA DELIVERED. READ receipt'i ChatViewModel.markIncomingMessagesAsRead gonderir
        // (sohbet aciksa Flow uzerinden). Tek-kaynak prensibi: WhatsApp benzeri tik gecisi animasyonel.
        if (originalMessageId != null) {
            sendDeliveryReceipt(senderId, originalMessageId, "DELIVERED")
        }
    }

    /**
     * Gelen SDP Offer'i isler — yeni gelen arama.
     * UserSession'dan yerel userId alinir, boylece ICE candidate gonderiminde
     * dogru senderId kullanilir.
     * Full-screen intent bildirimi gosterilir, boylece ekran kilitliyken de
     * kullanici aramayi gorebilir.
     */
    private suspend fun handleIncomingCall(signal: SignalMessage.SdpOffer) {
        val localUserId = userSession.userId ?: "unknown"
        callManager.handleIncomingCall(signal, localUserId)

        val peerName = resolvePeerName(signal.senderId)
        val session = callManager.currentSession

        if (session != null) {
            android.util.Log.d("IncomingHandler", "INCOMING CALL DETECTED - Background handler aktif")

            // EKRANI UYANDIR: Doze/screen-off durumunda full-screen intent her zaman tetiklenmez.
            // Wake lock + screen-on flag ile cihaz uyandirilir; sonra notification full-screen
            // intent IncomingCallActivity'i kilit ekraninda acabilir.
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                @Suppress("DEPRECATION")
                val wl = pm.newWakeLock(
                    android.os.PowerManager.FULL_WAKE_LOCK or
                    android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    android.os.PowerManager.ON_AFTER_RELEASE,
                    "SecureChat:IncomingCall"
                )
                wl.acquire(10_000) // 10sn — full-screen intent'in tetiklenmesi icin yeterli
                android.util.Log.d("IncomingHandler", "Wake lock alindi, ekran uyandiriliyor")
            } catch (e: Exception) {
                android.util.Log.w("IncomingHandler", "Wake lock alinamadi: ${e.message}")
            }

            // UI garantisi: notification + full-screen intent HER ZAMAN gosterilir.
            // setFullScreenIntent IncomingCallActivity'yi kilit ekraninda otomatik baslatir
            // — ekstra startActivity cagrisina gerek yok (eski kodda redundant idi,
            // tek aksiyonu duplicate Activity launch'tu).
            //
            // Telecom notifyIncomingCall opsiyonel olarak audio routing icin cagirilir.
            // Cogu cihazda Telecom kendi sistem UI'sini de gosterir; bazi cihazlarda
            // (SELF_MANAGED PhoneAccount onaylanmamis, ekran kapali vs.) UI sessizce
            // cikmaz — bu yuzden notification fallback'e GUVENMEK YERINE notification
            // her zaman gosterilir. Telecom UI cikarsa kullanici iki UI gorebilir
            // ama onceki "yalnizca ringtone, UI yok" regresyonundan iyidir.
            // Sessize alinmis sohbet/grup mu — bildirim seviyesinde davranisi etkiler
            val callMuted = try {
                conversationDao.getByPeerId(signal.senderId)?.isMuted == true
            } catch (_: Exception) { false }

            incomingCallHandler.showIncomingCall(
                session = session,
                peerName = peerName,
                fullScreenActivityClass = IncomingCallActivity::class.java,
                isMuted = callMuted
            )

            // Sessize alinmis kisi arasa zil calmamali — ringtone'i bypass et
            if (callMuted) {
                try { ringtonePlayer.stopRinging() } catch (_: Exception) {}
            }

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                try {
                    val isVideo = signal.callType == com.securechat.network.model.CallType.VIDEO
                    phoneAccountRegistrar.get().notifyIncomingCall(
                        callId = session.callId,
                        peerId = signal.senderId,
                        peerName = peerName,
                        isVideo = isVideo
                    )
                } catch (e: Exception) {
                    android.util.Log.w("IncomingHandler", "Telecom notifyIncomingCall hatası: ${e.message}")
                }
            }

            // Missed call timer'ı başlat
            missedCallTracker.startMissedCallTimer(session, peerName)
        }
    }

    /**
     * SFU room olusturuldu — koordinator veya davet edilen uye burada Janus'a baglanir.
     * 4+ kisilik grup aramasinda server otomatik olarak bu mesaji broadcast eder.
     */
    // Faz 10: handleSfuRoomCreated + handleGroupCallStatusResponse -> GroupCallStateHandler

    /**
     * Gelen grup arama davetiyesini isler.
     * CallManager'a iletir ve gelen arama bildirimini gosterir.
     */
    private suspend fun handleGroupCallInvite(signal: SignalMessage.GroupCallInvite) {
        val localUserId = userSession.userId ?: "unknown"

        // Aktif grup arama state'ine ekle — ChatScreen banner cagrida bunu gorur
        val isSfu = signal.participants.size >= 4
        val current = activeGroupCalls.value.toMutableMap()
        current[signal.groupId] = ActiveGroupCallInfo(
            groupId = signal.groupId,
            callId = signal.callId,
            coordinatorId = signal.senderId,
            callType = signal.callType,
            participants = signal.participants,
            mode = if (isSfu) "SFU" else "MESH"
        )
        activeGroupCalls.value = current

        callManager.handleGroupCallInvite(signal, localUserId)

        val callerName = resolvePeerName(signal.senderId)
        // Grup adi: yerel DB'de varsa kullan, yoksa "Grup Araması" generic fallback.
        // ESKI: peerName="Grup: <uuid>" gosteriyordu cunku resolvePeerName(senderId) sadece
        // arayanin adini cozer; arayan rehberde yoksa UUID dondururdu. Yeni davranis:
        // baslikta grup adi, alt satirda kim aradigi.
        val groupConv = conversationDao.getById(signal.groupId)
        val groupName = groupConv?.peerName?.takeIf {
            it.isNotBlank() && it != signal.groupId
        } ?: "Grup Araması"
        val displayTitle = if (callerName != signal.senderId) "$groupName · $callerName" else groupName
        val session = callManager.currentSession

        if (session != null) {
            // Grup sessize alinmis mi
            val groupMuted = try {
                groupConv?.isMuted == true
            } catch (_: Exception) { false }

            android.util.Log.d("IncomingHandler", "GELEN GRUP ARAMASI: ${signal.groupId} from $callerName ($displayTitle) muted=$groupMuted")

            // Gelen arama bildirimini goster
            incomingCallHandler.showIncomingCall(
                session = session,
                peerName = displayTitle,
                fullScreenActivityClass = IncomingCallActivity::class.java,
                isMuted = groupMuted
            )

            // Sessize alinmis grup arasa zil calmamali + Activity kilit ekrani uzerine atlamasin
            if (groupMuted) {
                try { ringtonePlayer.stopRinging() } catch (_: Exception) {}
            }

            // Full-screen Activity SADECE sessize alinmamis grup aramalarinda
            if (!groupMuted) try {
                val intent = android.content.Intent(context, IncomingCallActivity::class.java).apply {
                    putExtra("peer_id", signal.senderId)
                    putExtra("peer_name", displayTitle)
                    putExtra("call_type", signal.callType.name)
                    putExtra("is_group_call", true)
                    putExtra("group_id", signal.groupId)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                }
                context.startActivity(intent)
            } catch (e: Exception) {
                android.util.Log.e("IncomingHandler", "Grup arama Activity baslatılamadı: ${e.message}")
            }

            missedCallTracker.startMissedCallTimer(session, displayTitle)
        }
    }

    /**
     * Arama kontrol mesajlarini isler.
     */
    private fun handleCallControl(signal: SignalMessage.CallControl) {
        val session = callManager.currentSession

        // Grup aramasi aktifse grup-ozel islem
        if (session?.isGroupCall == true) {
            when (signal.action) {
                CallAction.ACCEPT -> {
                    // Koordinator olarak: uye kabul etti
                    callManager.onGroupMemberAccepted(signal.senderId)
                    session.callId.let { missedCallTracker.cancelMissedCallTimer(it) }
                }
                CallAction.HANGUP -> {
                    callManager.onGroupMemberHangup(signal.senderId)
                }
                CallAction.REJECT -> {
                    android.util.Log.d("IncomingHandler", "Grup uyesi reddetti: ${signal.senderId}")
                }
                else -> {}
            }
            return
        }

        when (signal.action) {
            CallAction.ACCEPT -> {
                // ACCEPT mesajini sadece OUTGOING/RINGING aramalarda isle
                // INCOMING aramalar zaten acceptCall() ile local olarak handle ediliyor
                if (session?.direction == com.securechat.media.model.CallDirection.OUTGOING &&
                    session.state == com.securechat.media.model.CallState.RINGING) {
                    callManager.onCallConnected()
                    // Timer iptal et - arama kabul edildi
                    missedCallTracker.cancelMissedCallTimer(session.callId)
                } else {
                    android.util.Log.d("IncomingHandler", "ACCEPT mesaji islenmedi - direction=${session?.direction}, state=${session?.state}")
                }
            }
            CallAction.REJECT -> {
                callManager.onRemoteReject()
                // Timer iptal et - arama reddedildi
                session?.callId?.let { missedCallTracker.cancelMissedCallTimer(it) }
            }
            CallAction.HANGUP -> {
                // Caller cevap beklemeden kapatti — B INCOMING+RINGING ise missed call.
                // Hemen kaydet/bildirim at (30sn timer beklemesin, daha iyi UX).
                val wasIncomingRinging = session?.direction == com.securechat.media.model.CallDirection.INCOMING &&
                    session.state == com.securechat.media.model.CallState.RINGING
                val sessionSnapshot = session
                callManager.onRemoteHangup()
                if (wasIncomingRinging && sessionSnapshot != null) {
                    scope.launch {
                        val peerName = resolvePeerName(sessionSnapshot.peerId)
                        missedCallTracker.triggerMissedCallNow(sessionSnapshot, peerName)
                    }
                } else {
                    sessionSnapshot?.callId?.let { missedCallTracker.cancelMissedCallTimer(it) }
                }
            }
            CallAction.BUSY -> {
                callManager.onRemoteBusy()
                // Timer iptal et - karşı taraf meşgul
                session?.callId?.let { missedCallTracker.cancelMissedCallTimer(it) }
            }
            CallAction.RINGING -> { /* Karsi taraf calıyor — bilgi amacli */ }
            CallAction.CAMERA_OFF -> {
                remoteCameraEnabled.value = false
                android.util.Log.d("IncomingHandler", "Karsi taraf kamerayi kapatti")
            }
            CallAction.CAMERA_ON -> {
                remoteCameraEnabled.value = true
                android.util.Log.d("IncomingHandler", "Karsi taraf kamerayi acti")
            }
        }
    }

    /**
     * Kullanici kimliginden goruntuleme adini cozer.
     * Oncelikle mevcut konusmalardan isim aranir, bulunamazsa sunucudan
     * sifreli telefon numarasi cekilip cozumlenir.
     */
    private suspend fun resolvePeerName(userId: String): String {
        // 1. Mevcut konusmada kayitli isim varsa onu kullan
        val existingConv = conversationDao.getByPeerId(userId)
        if (existingConv != null && existingConv.peerName != userId && existingConv.peerName.isNotBlank()) {
            return existingConv.peerName
        }
        // 2. UUID ile contacts DB'de ara (discovery sonrasi kaydedilmis)
        try {
            val contact = contactDao.getById(userId)
            if (contact != null && contact.displayName.isNotBlank()) {
                return contact.displayName
            }
        } catch (_: Exception) { }
        // 3. Sunucudan sifreli telefon numarasini cek ve coz
        try {
            val phone = fetchAndDecryptPhone(userId)
            if (phone != null) {
                // Cozumlenen numarayi conversation'a kaydet — bir daha sunucuya sorma
                if (existingConv != null) {
                    conversationDao.update(existingConv.copy(peerName = phone, peerPhone = phone))
                }
                return phone
            }
        } catch (_: Exception) { }
        // 4. Fallback: UUID doner
        return userId
    }

    /**
     * Kullanici kimliginden telefon numarasini cozer.
     * Oncelikle mevcut konusmadan, bulunamazsa contacts DB'den,
     * en son sunucudan cekilir.
     */
    private suspend fun resolvePeerPhone(userId: String): String {
        // 1. Mevcut konusmada kayitli numara varsa onu kullan
        try {
            val existingConv = conversationDao.getByPeerId(userId)
            if (existingConv != null && existingConv.peerPhone.isNotBlank()
                && existingConv.peerPhone != existingConv.peerName) {
                return existingConv.peerPhone
            }
        } catch (_: Exception) { }
        // 2. Contacts DB'de telefon numarasi varsa onu kullan
        try {
            val contact = contactDao.getById(userId)
            if (contact != null && contact.phoneNumber.isNotBlank()) {
                return contact.phoneNumber
            }
        } catch (_: Exception) { }
        // 3. Sunucudan sifreli telefon numarasini cek
        try {
            val phone = fetchAndDecryptPhone(userId)
            if (phone != null) return phone
        } catch (_: Exception) { }
        // 4. Fallback: bos string
        return ""
    }

    /**
     * Sunucudan kullanicinin sifreli telefon numarasini ceker ve istemcide cozer.
     * Sunucu sifreli veriyi saklar ama cozme anahtarina sahip degildir.
     */
    private suspend fun fetchAndDecryptPhone(userId: String): String? {
        return kotlinx.coroutines.withContext(Dispatchers.IO) {
            try {
                val url = "${com.securechat.app.BuildConfig.API_BASE_URL}/api/v1/users/$userId/phone"
                val request = okhttp3.Request.Builder().url(url).get().build()
                okhttp3.OkHttpClient().newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val body = response.body?.string() ?: return@use null
                        val json = org.json.JSONObject(body)
                        val encryptedPhone = json.optString("encryptedPhone", "")
                        if (encryptedPhone.isNotBlank()) {
                            val decrypted = com.securechat.contacts.PhoneEncryptor.decrypt(encryptedPhone)
                            if (decrypted != null) {
                                // Numarayi formatla: 905551234567 -> +90 555 123 4567
                                formatPhoneNumber(decrypted)
                            } else null
                        } else null
                    } else null
                }
            } catch (e: Exception) {
                android.util.Log.w("IncomingHandler", "Telefon cozumleme basarisiz: ${e.message}")
                null
            }
        }
    }

    /**
     * Ham rakamlari okunabilir telefon numarasina cevirir.
     * Ornek: "905551234567" -> "+90 555 123 4567"
     */
    private fun formatPhoneNumber(digits: String): String {
        if (digits.length < 7) return "+$digits"
        // Turkiye formati: 90 + 10 hane
        if (digits.startsWith("90") && digits.length == 12) {
            return "+90 ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}"
        }
        // Genel format: +ulke kodu + numara
        return "+$digits"
    }

    /**
     * MSGID prefix'ini ayristirir. Format: "MSGID:uuid:actualContent"
     * Prefix yoksa (geriye uyumluluk) icerik oldugu gibi doner.
     *
     * @return Pair(originalMessageId, actualContent) — messageId null olabilir
     */
    /**
     * Mesaj envelope'unu parse eder.
     * Format: "MSGID:uuid:REPLY:replyId:actualContent" veya "MSGID:uuid:actualContent"
     *
     * @return Triple(originalMessageId, replyToId, actualContent)
     */
    // Faz 10: Pure parsing logic 'data/incoming/parser/MessageEnvelopeParser.kt'ye
    // extract edildi. Buradaki private helper'lar parser'a delegate eder.

    private fun parseMessageId(content: String): Pair<String?, String> =
        com.securechat.app.data.incoming.parser.MessageEnvelopeParser.parseMessageId(content)

    private fun parseMessageEnvelope(content: String): com.securechat.app.data.incoming.parser.ParsedEnvelope =
        com.securechat.app.data.incoming.parser.MessageEnvelopeParser.parse(content)

    /**
     * Karsi taraftan gelen oy bilgisini lokal anket mesajina uygular.
     * Var olan votes JSON'unu gunceller; tek secim modunda eski oyunu kaldirir,
     * toggle (zaten varsa cikarir) mantigiyla calisir.
     */
    private suspend fun applyRemotePollVote(senderId: String, vote: com.securechat.app.data.incoming.parser.PollVoteRef) {
        val pollMessage = messageRepository.getMessageById(vote.pollMessageId) ?: return
        if (pollMessage.contentType != MessageContentType.POLL) return
        val json = try { org.json.JSONObject(pollMessage.content) } catch (_: Exception) { return }
        val votesObj = json.optJSONObject("votes") ?: org.json.JSONObject()
        val singleChoice = json.optBoolean("singleChoice", true)

        if (singleChoice) {
            val keys = votesObj.keys().asSequence().toList()
            for (key in keys) {
                val arr = votesObj.optJSONArray(key) ?: continue
                val filtered = org.json.JSONArray()
                for (i in 0 until arr.length()) {
                    if (arr.getString(i) != senderId) filtered.put(arr.getString(i))
                }
                votesObj.put(key, filtered)
            }
        }

        val optKey = vote.optionIndex.toString()
        val optArr = votesObj.optJSONArray(optKey) ?: org.json.JSONArray()
        val voters = (0 until optArr.length()).map { optArr.getString(it) }
        if (senderId in voters) {
            val filtered = org.json.JSONArray()
            voters.filter { it != senderId }.forEach { filtered.put(it) }
            votesObj.put(optKey, filtered)
        } else {
            optArr.put(senderId)
            votesObj.put(optKey, optArr)
        }

        json.put("votes", votesObj)
        messageRepository.updateMessageContent(
            vote.pollMessageId,
            json.toString(),
            MessageContentType.POLL.name
        )
    }

    /**
     * Gondericiye delivery receipt gonderir.
     * Mesajin aliciya ulastigini (DELIVERED) veya okundugunu (READ) bildirir.
     */
    private fun sendDeliveryReceipt(recipientId: String, messageId: String, status: String) {
        val localUserId = userSession.userId ?: return
        val receipt = SignalMessage.DeliveryReceipt(
            senderId = localUserId,
            recipientId = recipientId,
            timestamp = System.currentTimeMillis(),
            messageId = messageId,
            status = status
        )
        val sent = signalingClient.sendSignal(receipt)
        if (!sent) {
            // WebSocket bagli degil — baglanti gelince tekrar dene
            scope.launch {
                try {
                    signalingClient.connectionState.first { it is ConnectionState.Connected }
                    signalingClient.sendSignal(receipt)
                    android.util.Log.d("IncomingHandler", "Receipt retry basarili: $messageId ($status)")
                } catch (e: Exception) {
                    android.util.Log.w("IncomingHandler", "Receipt retry basarisiz: $messageId ($status): ${e.message}")
                }
            }
        }
    }

    // Faz 10: handleDeliveryReceipt -> DeliveryReceiptHandler (handlers/)

    // Faz 10: handleTypingIndicator + handlePresenceUpdate -> TypingPresenceHandler (handlers/)

    // Faz 10: handleDisappearingTimer -> DisappearingTimerHandler (handlers/)

    // Faz 10: handleMessageDelete + handleMessageEdit -> MessageEditDeleteHandler (handlers/)

    /**
     * Android bildirim gosterir. Gelen mesaj icin ses ve titresim ile bildirim olusturur.
     * Bildirim kanali yoksa olusturulur (Android 8+ zorunluluk).
     *
     * SMART LOGIC:
     * - Uygulama background'daysa her zaman bildirim goster
     * - Uygulama foreground'daysa sadece current chat'ten farkliysa bildirim goster
     */
    private suspend fun showMessageNotification(
        senderName: String,
        content: String,
        conversationId: String,
        forceHighPriority: Boolean = false
    ) {
        // Sessiz konusmalar icin bildirim gosterilir ama ses/titresim kapatilir
        val conv = conversationDao.getById(conversationId)
            ?: conversationDao.getByPeerId(conversationId)
        val isMutedRaw = conv?.isMuted == true

        // Sessize alinmis grupta bile @mention bildirim gonderilmeli.
        // forceHighPriority: gonderici MENTION envelope prefix gomduyse caller true verir
        // (string-icindeki @ kontrolune gore daha guvenilir, isim icinde bosluk problemi yok).
        val isMuted = if (isMutedRaw) {
            val currentUserId = userSession.userId ?: ""
            val currentDisplayName = userSession.displayName ?: ""
            val isMentioned = forceHighPriority ||
                              content.contains("@$currentUserId") ||
                              (currentDisplayName.isNotBlank() && content.contains("@$currentDisplayName"))
            if (isMentioned) {
                android.util.Log.d("IncomingHandler", "Sessize alinmis grupta @mention algilandi")
                false // @mention varsa sessiz degil — normal bildirim goster
            } else {
                true // @mention yoksa sessiz kalsin
            }
        } else {
            false
        }

        // Smart bildirim logic: current chat'ten gelen mesajlarda bildirim gosterme
        val shouldShowNotification = if (isAppInForeground) {
            conversationId != currentChatId
        } else {
            true
        }

        if (!shouldShowNotification) {
            android.util.Log.d("IncomingHandler", "Bildirim gosterilmedi - current chat: $conversationId")
            return
        }

        // Kullanici tercihi: mesaj icerigi gosterilsin mi?
        val showContent = try {
            themeManager.showNotificationContent.first()
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "showNotificationContent okunamadi: ${e.message}")
            true
        }
        android.util.Log.d("IncomingHandler", "showContent=$showContent (false=gizlilik modu aktif)")

        val channelIdHigh = "elcim_messages_v4"
        val channelIdLow = "elcim_messages_low_v1"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Eski kanallari temizle
        nm.deleteNotificationChannel("messages")
        nm.deleteNotificationChannel("elci_messages_v2")
        nm.deleteNotificationChannel("elci_messages_v3")

        // Normal mesajlar (heads-up + ses)
        if (nm.getNotificationChannel(channelIdHigh) == null) {
            val channel = NotificationChannel(channelIdHigh, "Elçim Mesajlar", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Elçim - Gelen mesaj bildirimleri"
                enableVibration(true)
                enableLights(true)
                lightColor = 0xFF00897B.toInt()
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }

        // Sessize alinmis sohbetler icin AYRI kanal (IMPORTANCE_LOW, ses/titresim yok, heads-up yok).
        // KRITIK: Android 8+ kanal-seviyesi ayarlari bildirim-seviyesi setSilent/PRIORITY override eder;
        // bu yuzden gercek "sessize" davranisi ancak ikinci kanal ile saglanir.
        if (nm.getNotificationChannel(channelIdLow) == null) {
            val channel = NotificationChannel(channelIdLow, "Elçim Mesajlar (Sessiz)", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Sessize alinmis sohbetlerden gelen mesajlar"
                enableVibration(false)
                enableLights(false)
                setSound(null, null)
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }

        // Routing: bu mesaj sessize alinmis sohbetten geliyorsa low kanaldan post et
        val channelId = if (isMuted) channelIdLow else channelIdHigh

        // Tiklaninca ilgili sohbeti acan intent
        val tapIntent = android.content.Intent(context, com.securechat.app.SecureChatActivity::class.java).apply {
            putExtra("chat_peer", conversationId)
            flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                    android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = android.app.PendingIntent.getActivity(
            context, conversationId.hashCode(), tapIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val appIconBitmap = getAppIconBitmap()

        val groupKey = "elcim_messages"

        // Mesaj sayacini guncelle
        notifMessageCount[conversationId] = (notifMessageCount[conversationId] ?: 0) + 1
        val recentList = notifRecentMessages.getOrPut(conversationId) { mutableListOf() }
        recentList.add(Pair(content, System.currentTimeMillis()))
        if (recentList.size > 5) recentList.removeAt(0)

        val totalMessages = notifMessageCount.values.sum()
        val chatCount = notifMessageCount.size

        if (!showContent) {
            // ── GIZLILIK MODU: tek bildirim, sayac guncellenir ──
            // Onceki per-conversation bildirimlerini temizle
            nm.cancel(ELCIM_SUMMARY_ID)
            for (notif in nm.activeNotifications) {
                if (notif.notification.group == groupKey) {
                    nm.cancel(notif.id)
                }
            }

            val privacyIntent = android.content.Intent(context, com.securechat.app.SecureChatActivity::class.java).apply {
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val privacyPendingIntent = android.app.PendingIntent.getActivity(
                context, ELCIM_PRIVACY_NOTIF_ID, privacyIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val privacyText = if (chatCount > 1) {
                "$chatCount sohbetten $totalMessages yeni mesaj"
            } else {
                "$totalMessages yeni mesaj"
            }

            val shouldBeSilent = isAppInForeground || isMuted
            val privPriority = if (shouldBeSilent) NotificationCompat.PRIORITY_LOW
                              else NotificationCompat.PRIORITY_HIGH
            val privDefaults = if (shouldBeSilent) 0
                               else NotificationCompat.DEFAULT_ALL

            val privacyBuilder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(com.securechat.app.R.mipmap.ic_launcher)
                .setColor(0xFF3E7BFA.toInt())
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(privPriority)
                .setAutoCancel(true)
                .setContentIntent(privacyPendingIntent)
                .setDefaults(privDefaults)
                .setSilent(shouldBeSilent)
                .setNumber(totalMessages)
                .setContentTitle("Elçim")
                .setContentText(privacyText)
                .setSubText("Elçim")
                // GUVENLIK (M9 fix): Lock screen'de "Elcim — N yeni mesaj" gostermek bile bilgi sizdirir
                // (cihaz sahibi disinda birinin elinde olabilir). VISIBILITY_SECRET ile lock screen'de
                // bildirim TAMAMEN gizlenir — sadece unlock sonrasi gorulebilir.
                .setVisibility(NotificationCompat.VISIBILITY_SECRET)

            try {
                nm.notify(ELCIM_PRIVACY_NOTIF_ID, privacyBuilder.build())
                android.util.Log.d("IncomingHandler", "Gizlilik bildirimi: $privacyText")
            } catch (e: SecurityException) {
                android.util.Log.e("IncomingHandler", "Bildirim gosterilemedi (izin yok): ${e.message}")
            }
            return
        }

        // ── NORMAL MOD: sohbet basina ayri bildirim + grup ozeti ──

        // Mevcut aktif bildirimleri say
        val existingNotifications = nm.activeNotifications.filter {
            it.notification.group == groupKey && it.id != ELCIM_SUMMARY_ID && it.id != ELCIM_PRIVACY_NOTIF_ID
        }
        val existingChatCount = existingNotifications.map { it.id }.toSet().size
        val willHaveChats = if (existingNotifications.any { it.id == conversationId.hashCode() }) existingChatCount else existingChatCount + 1

        val subText = if (willHaveChats > 1) {
            "Elçim · $willHaveChats sohbet, $totalMessages mesaj"
        } else {
            "Elçim"
        }

        // On plandayken veya sessiz konusmada banner gosterme — sessiz bildirim yeter
        val shouldBeSilent = isAppInForeground || isMuted
        val priority = if (shouldBeSilent) NotificationCompat.PRIORITY_LOW
                       else NotificationCompat.PRIORITY_HIGH

        // Kullanici tarafindan secilen bildirim sesi URI'si
        val customSoundUri = try {
            themeManager.notificationSoundUri.first()
        } catch (_: Exception) {
            ""
        }

        // Sessiz degilse ve ozel ses secilmisse DEFAULT_ALL yerine sadece isik/titresim kullan
        val defaults = if (shouldBeSilent) {
            0
        } else if (customSoundUri.isNotEmpty()) {
            // Ozel ses kullanilacak, varsayilan sesi devre disi birak
            NotificationCompat.DEFAULT_VIBRATE or NotificationCompat.DEFAULT_LIGHTS
        } else {
            NotificationCompat.DEFAULT_ALL
        }

        // Per-peer dismiss intent — kullanici bu konusmanin bildirimini swipe ederse sayac sifirlanir
        val dismissIntent = android.content.Intent(context, NotifDismissReceiver::class.java).apply {
            action = NotifDismissReceiver.ACTION_DISMISS
            putExtra(NotifDismissReceiver.EXTRA_CONVERSATION_ID, conversationId)
        }
        val dismissPendingIntent = android.app.PendingIntent.getBroadcast(
            context,
            conversationId.hashCode(),
            dismissIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(com.securechat.app.R.mipmap.ic_launcher)
            .setColor(0xFF3E7BFA.toInt())
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(priority)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setDeleteIntent(dismissPendingIntent)
            .setDefaults(defaults)
            .setSilent(shouldBeSilent)
            .setGroup(groupKey)
            .setNumber(notifMessageCount[conversationId] ?: 1)
            .setContentTitle(senderName)

        // Ozel bildirim sesi ayarla (sessiz degilse)
        if (!shouldBeSilent && customSoundUri.isNotEmpty()) {
            try {
                builder.setSound(android.net.Uri.parse(customSoundUri))
            } catch (e: Exception) {
                android.util.Log.w("IncomingHandler", "Ozel bildirim sesi uygulanamadi: ${e.message}")
            }
        }

        val shortcutId = "contact_$conversationId"
        val person = androidx.core.app.Person.Builder()
            .setName(senderName)
            .setKey(conversationId)
            .setIcon(androidx.core.graphics.drawable.IconCompat.createWithBitmap(appIconBitmap))
            .setImportant(true)
            .build()

        try {
            val shortcutIntent = android.content.Intent(context, com.securechat.app.SecureChatActivity::class.java).apply {
                action = android.content.Intent.ACTION_VIEW
                putExtra("chat_peer", conversationId)
            }
            val shortcut = androidx.core.content.pm.ShortcutInfoCompat.Builder(context, shortcutId)
                .setShortLabel(senderName)
                .setLongLived(true)
                .setPerson(person)
                .setIcon(androidx.core.graphics.drawable.IconCompat.createWithBitmap(appIconBitmap))
                .setIntent(shortcutIntent)
                .build()
            androidx.core.content.pm.ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
        } catch (e: Exception) {
            android.util.Log.w("IncomingHandler", "Shortcut olusturulamadi: ${e.message}")
        }

        val messagingStyle = NotificationCompat.MessagingStyle(person)
            .setConversationTitle(senderName)
        for ((msg, ts) in recentList) {
            messagingStyle.addMessage(msg, ts, person)
        }

        builder.setStyle(messagingStyle)
            .setShortcutId(shortcutId)
            .setSubText(subText)

        try {
            nm.notify(conversationId.hashCode(), builder.build())

            // Grup ozet bildirimi — HER ZAMAN olustur (API 24+ setGroup pattern'i):
            // activeNotifications.size race condition'a takiliyordu — kendi sayacimizi kullaniyoruz.
            // WhatsApp davranisi: tek sohbet bile olsa stacked notification icin summary lazim.
            val finalChatCount = notifMessageCount.size
            val finalTotalMessages = notifMessageCount.values.sum()
            val summaryText = if (finalChatCount > 1) {
                "$finalChatCount sohbetten $finalTotalMessages yeni mesaj"
            } else {
                "$finalTotalMessages yeni mesaj"
            }

            val summaryIntent = android.content.Intent(context, com.securechat.app.SecureChatActivity::class.java).apply {
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val summaryPendingIntent = android.app.PendingIntent.getActivity(
                context, ELCIM_SUMMARY_ID, summaryIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val inboxStyle = NotificationCompat.InboxStyle()
                .setBigContentTitle("Elçim")
                .setSummaryText(summaryText)
            // notifMessageCount'tan beslenen InboxStyle — race-free
            val activeForSummary = nm.activeNotifications.filter {
                it.notification.group == groupKey && it.id != ELCIM_SUMMARY_ID && it.id != ELCIM_PRIVACY_NOTIF_ID
            }
            for (notif in activeForSummary) {
                val extras = notif.notification.extras
                val title = extras.getString("android.title") ?: ""
                val text = extras.getCharSequence("android.text")?.toString() ?: ""
                if (title.isNotBlank()) inboxStyle.addLine("$title: $text")
            }

            val summaryDismissIntent = android.content.Intent(context, NotifDismissReceiver::class.java).apply {
                action = NotifDismissReceiver.ACTION_DISMISS_ALL
            }
            val summaryDismissPendingIntent = android.app.PendingIntent.getBroadcast(
                context,
                ELCIM_SUMMARY_ID,
                summaryDismissIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val summaryBuilder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(com.securechat.app.R.mipmap.ic_launcher)
                .setColor(0xFF3E7BFA.toInt())
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setGroup(groupKey)
                .setGroupSummary(true)
                .setAutoCancel(true)
                .setContentIntent(summaryPendingIntent)
                .setDeleteIntent(summaryDismissPendingIntent)
                .setSubText("Elçim")
                .setContentTitle("Elçim")
                .setContentText(summaryText)
                .setNumber(finalTotalMessages)
                .setStyle(inboxStyle)
                .setSilent(true) // Summary sessiz — per-peer notif zaten ses cikariyor

            nm.notify(ELCIM_SUMMARY_ID, summaryBuilder.build())

            android.util.Log.d("IncomingHandler", "Bildirim gosterildi: $senderName (showContent=$showContent, msgCount=${notifMessageCount[conversationId]}, summary=$summaryText)")
        } catch (e: SecurityException) {
            android.util.Log.e("IncomingHandler", "Bildirim gosterilemedi (izin yok): ${e.message}")
        }
    }

    /**
     * Uygulama launcher ikonunu bildirim avatari olarak dondurur.
     */
    private fun getAppIconBitmap(): android.graphics.Bitmap {
        cachedAppIconBitmap?.let { return it }
        val drawable = context.packageManager.getApplicationIcon(context.applicationInfo)
        val size = 128
        val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        cachedAppIconBitmap = bitmap
        return bitmap
    }

    /**
     * Bellek baskisi altinda onbelleklenmis bitmap'i serbest birakir.
     * SecureChatApplication.onTrimMemory() tarafindan cagrilir.
     */
    fun clearBitmapCache() {
        cachedAppIconBitmap = null
    }

    /**
     * Grup bildirimleri isler (CREATE, ADD_MEMBER, REMOVE_MEMBER, vb.).
     * Grup olusturma, uye ekleme/cikarma islemleri icin.
     */
    private suspend fun handleGroupNotification(signal: SignalMessage.GroupNotification) {
        val localUserId = userSession.userId ?: "unknown"

        when (signal.action) {
            com.securechat.network.model.GroupAction.CREATE -> {
                // Yeni grup olusturuldu - yerel veritabanina kaydet
                val groupConv = conversationDao.getById(signal.groupId)
                if (groupConv == null) {
                    android.util.Log.d("IncomingHandler", "Yeni grup olusturuluyor: ${signal.groupId}, isim: ${signal.groupName}")
                    conversationDao.insert(
                        ConversationEntity(
                            id = signal.groupId,
                            peerId = signal.groupId,
                            peerName = signal.groupName,
                            peerPhone = "",
                            lastMessage = "${resolvePeerName(signal.senderId)} grubu oluşturdu",
                            lastMessageTimestamp = signal.timestamp,
                            unreadCount = if (signal.senderId != localUserId) 1 else 0,
                            isMuted = false,
                            isPinned = false,
                            isGroup = true,
                            groupMembers = signal.groupMembers.joinToString(","),
                            groupAdmins = signal.senderId // Grup kurucusu ilk admin
                        )
                    )

                    // Bildirim goster (kendi isleminde degil ise)
                    if (signal.senderId != localUserId) {
                        val senderName = resolvePeerName(signal.senderId)
                        showMessageNotification(
                            "$senderName (${signal.groupName})",
                            "grubu oluşturdu",
                            signal.groupId
                        )
                    }
                } else {
                    // CRITICAL FIX: Grup zaten varsa, üye listesini güncelle
                    // Bu creator'ın kendisine gönderdiği bildirimi aldığında da çalışır
                    android.util.Log.d("IncomingHandler", "Grup mevcut, üye listesi güncelleniyor: ${signal.groupId}")

                    // Mevcut üye listesi ile gelen listeyi birleştir (duplicate kontrolü)
                    val currentMembers = groupConv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                    val incomingMembers = signal.groupMembers.filter { it.isNotBlank() }
                    val allMembers = (currentMembers + incomingMembers).distinct()

                    conversationDao.updateGroupMembers(signal.groupId, allMembers.joinToString(","))
                    android.util.Log.d("IncomingHandler", "Grup üye listesi güncellendi: ${signal.groupId}, üyeler: $allMembers")
                }
            }

            com.securechat.network.model.GroupAction.ADD_MEMBER -> {
                // Gruba yeni uye eklendi
                val groupConv = conversationDao.getById(signal.groupId)
                if (groupConv != null) {
                    android.util.Log.d("IncomingHandler", "Grup üye listesi güncelleniyor: ${signal.groupId}")
                    conversationDao.updateGroupMembers(signal.groupId, signal.groupMembers.joinToString(","))

                    // Sistem mesajı kaydet — UUID yerine isimleri kullan
                    val targetMember = signal.targetMemberId ?: "bilinmeyen"
                    val adderName = resolvePeerName(signal.senderId)
                    val addedName = resolvePeerName(targetMember)
                    val systemMessage = "$adderName, $addedName'i gruba ekledi"

                    val message = com.securechat.storage.domain.LocalMessage(
                        id = UUID.randomUUID().toString(),
                        conversationId = signal.groupId,
                        senderId = "SYSTEM",
                        peerId = signal.groupId, // Grup ID'si peer olarak
                        content = systemMessage,
                        contentType = MessageContentType.SYSTEM,
                        timestamp = signal.timestamp,
                        status = MessageStatus.DELIVERED,
                        isOutgoing = false
                    )
                    messageRepository.saveMessage(message)

                    // Sender Keys: yeni uye eklenince kendi sender key'imizi ona dagit.
                    // Diger uyeler de ayni branch'i alip kendi key'lerini gonderir — sonucta
                    // yeni uye herkesin SK'sini elde eder.
                    val newMemberId = signal.targetMemberId
                    if (newMemberId != null && newMemberId != localUserId) {
                        scope.launch {
                            groupSenderKeyDistributor.distributeToMember(signal.groupId, newMemberId)
                        }
                    }
                }
            }

            com.securechat.network.model.GroupAction.REMOVE_MEMBER -> {
                // Gruptan uye cikarildi
                val groupConv = conversationDao.getById(signal.groupId)
                if (groupConv != null) {
                    val targetMember = signal.targetMemberId ?: "bilinmeyen"

                    // Cikarilan uye kendimiz ise konusmayi arsivle ve aktif sohbetlerden kaldir
                    if (targetMember == localUserId) {
                        android.util.Log.w("IncomingHandler", "Gruptan çıkarıldınız: ${signal.groupId}")

                        // Uye listesini guncelle (kendimizi cikar)
                        val updatedMembers = signal.groupMembers.filter { it != localUserId }
                        conversationDao.updateGroupMembers(signal.groupId, updatedMembers.joinToString(","))

                        // Konusmayi arsivle
                        conversationDao.updateArchived(signal.groupId, true)

                        // Bu grup icin bekleyen bildirimleri temizle
                        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        nm.cancel(signal.groupId.hashCode())
                        // Bildirim sayacini da temizle
                        notifMessageCount.remove(signal.groupId)
                        notifRecentMessages.remove(signal.groupId)

                        // Sistem mesaji kaydet — kullanici cikarildigini bilsin
                        val systemMessage = "Bu gruptan çıkarıldınız"
                        val message = com.securechat.storage.domain.LocalMessage(
                            id = UUID.randomUUID().toString(),
                            conversationId = signal.groupId,
                            senderId = "SYSTEM",
                            peerId = signal.groupId,
                            content = systemMessage,
                            contentType = MessageContentType.SYSTEM,
                            timestamp = signal.timestamp,
                            status = MessageStatus.DELIVERED,
                            isOutgoing = false
                        )
                        messageRepository.saveMessage(message)
                    } else {
                        // Baskasi cikarildi — uye listesini guncelle
                        android.util.Log.d("IncomingHandler", "Grup üye listesi güncelleniyor: ${signal.groupId}")
                        conversationDao.updateGroupMembers(signal.groupId, signal.groupMembers.joinToString(","))

                        // Sistem mesaji kaydet — UUID yerine isimleri kullan
                        val removerName = resolvePeerName(signal.senderId)
                        val removedName = resolvePeerName(targetMember)
                        val systemMessage = "$removerName, $removedName'i gruptan çıkardı"
                        val message = com.securechat.storage.domain.LocalMessage(
                            id = UUID.randomUUID().toString(),
                            conversationId = signal.groupId,
                            senderId = "SYSTEM",
                            peerId = signal.groupId,
                            content = systemMessage,
                            contentType = MessageContentType.SYSTEM,
                            timestamp = signal.timestamp,
                            status = MessageStatus.DELIVERED,
                            isOutgoing = false
                        )
                        messageRepository.saveMessage(message)
                    }

                    // Sender Keys: uye cikarildi → forward secrecy icin kendi sender key'imizi rotate et.
                    // Bizim kendimiz cikarildiysa rotate gereksiz — gruptan ayrildigimiz icin
                    // artik o gruba mesaj atmayacagiz.
                    if (targetMember != localUserId) {
                        scope.launch {
                            groupSenderKeyDistributor.rotate(signal.groupId)
                        }
                    }
                }
            }

            com.securechat.network.model.GroupAction.LEAVE_GROUP -> {
                // Bir uye kendi istegi ile gruptan ayrildi
                val groupConv = conversationDao.getById(signal.groupId)
                if (groupConv != null) {
                    // Ayrilan uyeyi grup uyelerinden cikar
                    val currentMembers = groupConv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                    val updatedMembers = currentMembers.filter { it != signal.senderId }
                    conversationDao.updateGroupMembers(signal.groupId, updatedMembers.joinToString(","))

                    // Sistem mesaji kaydet
                    val leaverName = resolvePeerName(signal.senderId)
                    val leaveMessage = com.securechat.storage.domain.LocalMessage(
                        id = UUID.randomUUID().toString(),
                        conversationId = signal.groupId,
                        senderId = "SYSTEM",
                        peerId = signal.groupId,
                        content = "$leaverName gruptan ayrıldı",
                        contentType = MessageContentType.SYSTEM,
                        timestamp = signal.timestamp,
                        status = MessageStatus.DELIVERED,
                        isOutgoing = false
                    )
                    messageRepository.saveMessage(leaveMessage)

                    // Sender Keys: bir uye ayrildi → forward secrecy icin sender key'imizi rotate et.
                    // Kendi LEAVE_GROUP bildirimimizi kendimiz islemeyiz (signal recipient != self).
                    if (signal.senderId != localUserId) {
                        scope.launch {
                            groupSenderKeyDistributor.rotate(signal.groupId)
                        }
                    }
                }
            }

            com.securechat.network.model.GroupAction.UPDATE_ADMIN -> {
                // Admin listesi guncellendi — hedef uye admin olarak yukseltildi
                val groupConv = conversationDao.getById(signal.groupId)
                if (groupConv != null) {
                    val targetMember = signal.targetMemberId ?: "bilinmeyen"
                    android.util.Log.d("IncomingHandler", "Admin guncelleniyor: $targetMember -> ${signal.groupId}")

                    // Mevcut admin listesine yeni admin'i ekle
                    val currentAdmins = groupConv.groupAdmins?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                    val updatedAdmins = (currentAdmins + targetMember).distinct().joinToString(",")
                    conversationDao.updateGroupAdmins(signal.groupId, updatedAdmins)

                    // Sistem mesaji kaydet — UUID yerine kullanici adlarini kullan
                    val promoterName = resolvePeerName(signal.senderId)
                    val promotedName = resolvePeerName(targetMember)
                    val systemMessage = "$promoterName, $promotedName'i yönetici yaptı"
                    val message = com.securechat.storage.domain.LocalMessage(
                        id = UUID.randomUUID().toString(),
                        conversationId = signal.groupId,
                        senderId = "SYSTEM",
                        peerId = signal.groupId,
                        content = systemMessage,
                        contentType = MessageContentType.SYSTEM,
                        timestamp = signal.timestamp,
                        status = MessageStatus.DELIVERED,
                        isOutgoing = false
                    )
                    messageRepository.saveMessage(message)
                }
            }

            com.securechat.network.model.GroupAction.UPDATE_EXPORT_POLICY -> {
                // Sohbet disa aktarma izni admin tarafindan ac/kapat edildi.
                // targetMemberId alani yeni durumu "true"/"false" stringi olarak tasir.
                val groupConv = conversationDao.getById(signal.groupId)
                if (groupConv != null) {
                    val newEnabled = signal.targetMemberId?.toBooleanStrictOrNull() ?: false
                    conversationDao.updateExportEnabled(signal.groupId, newEnabled)
                    // Export ACILIRSA banner ack'ini sifirla — kullanici yeni durumu
                    // gorebilsin diye one-time uyari tekrar gosterilir.
                    if (newEnabled) exportBannerAckStore.reset(signal.groupId)

                    val actorName = resolvePeerName(signal.senderId)
                    val systemMessage = if (newEnabled) {
                        "$actorName sohbet dışa aktarmayı açtı"
                    } else {
                        "$actorName sohbet dışa aktarmayı kapattı"
                    }
                    val message = com.securechat.storage.domain.LocalMessage(
                        id = UUID.randomUUID().toString(),
                        conversationId = signal.groupId,
                        senderId = "SYSTEM",
                        peerId = signal.groupId,
                        content = systemMessage,
                        contentType = MessageContentType.SYSTEM,
                        timestamp = signal.timestamp,
                        status = MessageStatus.DELIVERED,
                        isOutgoing = false
                    )
                    messageRepository.saveMessage(message)
                }
            }

            com.securechat.network.model.GroupAction.SET_READ_ONLY -> {
                // "Sadece admin yazabilir" duyuru kanali bayragi admin tarafindan toggle edildi.
                // targetMemberId alani yeni durumu "true"/"false" stringi olarak tasir.
                // Yetki: sender admin olmalidir (UPDATE_EXPORT_POLICY ile ayni pattern).
                val groupConv = conversationDao.getById(signal.groupId)
                if (groupConv != null) {
                    val admins = groupConv.groupAdmins
                        ?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                    if (signal.senderId !in admins) {
                        android.util.Log.w(
                            "IncomingHandler",
                            "SET_READ_ONLY: gonderici admin degil, signal dropluyor: ${signal.senderId}"
                        )
                        return
                    }

                    val newReadOnly = signal.targetMemberId?.toBooleanStrictOrNull() ?: false
                    conversationDao.updateReadOnly(signal.groupId, newReadOnly)

                    val actorName = resolvePeerName(signal.senderId)
                    val systemMessage = if (newReadOnly) {
                        "$actorName grubu duyuru kanaline cevirdi (sadece adminler yazabilir)"
                    } else {
                        "$actorName duyuru kanali ayarini kapatti"
                    }
                    val message = com.securechat.storage.domain.LocalMessage(
                        id = UUID.randomUUID().toString(),
                        conversationId = signal.groupId,
                        senderId = "SYSTEM",
                        peerId = signal.groupId,
                        content = systemMessage,
                        contentType = MessageContentType.SYSTEM,
                        timestamp = signal.timestamp,
                        status = MessageStatus.DELIVERED,
                        isOutgoing = false
                    )
                    messageRepository.saveMessage(message)
                }
            }

            else -> {
                android.util.Log.d("IncomingHandler", "Bilinmeyen grup aksiyonu: ${signal.action}")
            }
        }
    }

    // Faz 10: handleAdminEncryptedLog -> AdminEncryptedLogHandler (handlers/)

    /**
     * MessagePin signal handler — karsi taraf bir mesaji sabitledi/pin kaldirdi.
     *
     * Yetki tekrar kontrolu: grup mesajinda sender admin degilse signal'i sessizce
     * dropla (server zero-knowledge — kotu niyetli client her zaman gonderebilir,
     * client-side enforce yapmaliyiz).
     *
     * Lokal mesaj DB'de yoksa (gec gelen signal veya silinmis mesaj) sessizce yok say.
     */
    private suspend fun handleMessagePin(signal: SignalMessage.MessagePin) {
        val localUserId = userSession.userId ?: return
        val message = messageRepository.getMessageById(signal.messageId) ?: run {
            android.util.Log.d(
                "IncomingHandler",
                "MessagePin: mesaj bulunamadi (silinmis veya gec geldi): ${signal.messageId}"
            )
            return
        }

        // Grup mesajinda admin kontrolu
        val conversationId = signal.groupId ?: message.conversationId
        val conv = conversationDao.getById(conversationId)
        if (conv?.isGroup == true) {
            val admins = conv.groupAdmins?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            if (signal.senderId !in admins) {
                android.util.Log.w(
                    "IncomingHandler",
                    "MessagePin: gonderici admin degil, signal dropluyor: ${signal.senderId} -> ${signal.groupId}"
                )
                return
            }
        }

        // Kendi cihazimizdaki pin durumu zaten guncel (sender = biz). Yine de
        // multi-device senaryosunda gelirse idempotent guncelleme yapariz.
        if (signal.senderId == localUserId) return

        messageRepository.updateMessagePinned(
            messageId = signal.messageId,
            isPinned = signal.isPinned,
            pinnedAt = signal.pinnedAt
        )
        android.util.Log.d(
            "IncomingHandler",
            "MessagePin uygulandi: ${signal.messageId} isPinned=${signal.isPinned}"
        )
    }
}
