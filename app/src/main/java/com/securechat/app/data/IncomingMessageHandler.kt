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
    private val phoneAccountRegistrar: dagger.Lazy<com.securechat.telecom.PhoneAccountRegistrar>
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
                when (signal) {
                    is SignalMessage.EncryptedMessage -> handleEncryptedMessage(signal)
                    is SignalMessage.FileTransfer -> handleFileTransfer(signal)
                    is SignalMessage.SdpOffer -> {
                        // Grup aramasi aktifse grup SDP Offer olarak isle
                        if (callManager.isCurrentCallGroup) {
                            callManager.handleGroupSdpOffer(signal)
                        } else {
                            handleIncomingCall(signal)
                        }
                    }
                    is SignalMessage.SdpAnswer -> {
                        if (callManager.isCurrentCallGroup) {
                            callManager.handleGroupSdpAnswer(signal)
                        } else {
                            callManager.handleSdpAnswer(signal)
                        }
                    }
                    is SignalMessage.IceCandidate -> {
                        if (callManager.isCurrentCallGroup) {
                            callManager.handleGroupIceCandidate(signal)
                        } else {
                            callManager.handleIceCandidate(signal)
                        }
                    }
                    is SignalMessage.CallControl -> {
                        android.util.Log.d("IncomingHandler", "CallControl: ${signal.action}")
                        handleCallControl(signal)
                    }
                    is SignalMessage.GroupNotification -> {
                        android.util.Log.d("IncomingHandler", "GroupNotification: ${signal.action} for group ${signal.groupId}")
                        handleGroupNotification(signal)
                    }
                    is SignalMessage.DeliveryReceipt -> handleDeliveryReceipt(signal)
                    is SignalMessage.MessageDelete -> handleMessageDelete(signal)
                    is SignalMessage.MessageEdit -> handleMessageEdit(signal)
                    is SignalMessage.DisappearingTimer -> handleDisappearingTimer(signal)
                    is SignalMessage.TypingIndicator -> handleTypingIndicator(signal)
                    is SignalMessage.PresenceUpdate -> handlePresenceUpdate(signal)
                    is SignalMessage.GroupCallInvite -> handleGroupCallInvite(signal)
                    is SignalMessage.GroupCallMemberJoined -> callManager.handleGroupCallMemberJoined(signal)
                    is SignalMessage.GroupCallMemberLeft -> callManager.handleGroupCallMemberLeft(signal)
                    is SignalMessage.GroupCallCoordinatorChanged -> callManager.handleGroupCallCoordinatorChanged(signal)
                    is SignalMessage.GroupCallJoinRequest -> callManager.handleGroupCallJoinRequest(signal)
                    is SignalMessage.GroupCallStatusResponse -> handleGroupCallStatusResponse(signal)
                    is SignalMessage.GroupCallStatusQuery -> { /* Sunucu tarafinda islenir */ }
                    is SignalMessage.SfuRoomCreated -> handleSfuRoomCreated(signal)
                    is SignalMessage.PresenceSubscribe -> { /* Sunucu tarafinda islenir */ }
                    is SignalMessage.PresenceUnsubscribe -> { /* Sunucu tarafinda islenir */ }
                    is SignalMessage.AudioData -> { }
                    is SignalMessage.VideoData -> { /* WebRTC P2P — artik kullanilmiyor */ }
                    else -> { }
                }
            }
        }
    }

    private suspend fun handleEncryptedMessage(signal: SignalMessage.EncryptedMessage) {
        val senderId = signal.senderId
        val content = signal.envelope

        if (content.startsWith("GROUP:")) {
            // Yeni format: "GROUP:groupId:groupName:gercekIcerik" (4 parca)
            // Eski format: "GROUP:groupId:gercekIcerik" (3 parca) — geriye uyumluluk
            val parts = content.split(":", limit = 4)
            if (parts.size >= 4) {
                val groupId = parts[1]
                val groupName = parts[2]
                val actualContent = parts[3]
                handleGroupMessage(senderId, groupId, actualContent, groupName)
            } else if (parts.size >= 3) {
                // Eski format — grup adi bilinmiyor
                val groupId = parts[1]
                val actualContent = parts[2]
                handleGroupMessage(senderId, groupId, actualContent, null)
            }
        } else {
            // Birebir mesaj
            handleDirectMessage(senderId, content)
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

        // Chunk destekli dosya alma — tek parcali veya coklu parcali
        val savedUri = fileTransferManager.receiveChunk(
            transferId = signal.transferId,
            chunkIndex = signal.chunkIndex,
            totalChunks = signal.totalChunks,
            fileName = signal.fileName,
            mimeType = signal.mimeType,
            fileSize = signal.fileSize,
            data = signal.data
        )

        // Henuz tum chunk'lar gelmedi — mesaj kaydetme, bekle
        if (savedUri == null && signal.totalChunks > 1 && signal.chunkIndex < signal.totalChunks - 1) {
            android.util.Log.d("IncomingHandler", "Chunk bekleniyor: ${signal.transferId} [${signal.chunkIndex + 1}/${signal.totalChunks}]")
            return
        }

        val filePath = savedUri?.path ?: ""

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
                caption = signal.caption?.takeIf { it.isNotBlank() },
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
                val notifBody = signal.caption?.takeIf { it.isNotBlank() } ?: "Dosya: ${signal.fileName}"
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
                caption = signal.caption?.takeIf { it.isNotBlank() },
                isViewOnce = signal.isViewOnce
            )
            messageRepository.saveMessage(message)

            // Dosya icin DELIVERED receipt — text mesajlardakine paralel. READ ChatViewModel'in.
            signal.originalMessageId?.let { sendDeliveryReceipt(senderId, it, "DELIVERED") }

            // Birebir sohbet kapaliysa bildirim goster — caption varsa ozet olarak kullan
            if (!isFileChatOpen) {
                val notifBody = signal.caption?.takeIf { it.isNotBlank() } ?: "Dosya: ${signal.fileName}"
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
        showMessageNotification("$senderName ($displayGroupName)", groupNotifPreview, groupId)

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
    private fun handleSfuRoomCreated(signal: SignalMessage.SfuRoomCreated) {
        val localUserId = userSession.userId ?: return
        val session = callManager.currentSession ?: return
        if (!session.isGroupCall || session.groupId != signal.groupId) {
            android.util.Log.d("IncomingHandler", "SfuRoomCreated atlandi — aktif grup arama uyusmuyor")
            return
        }
        if (session.state != com.securechat.media.model.CallState.ACTIVE) {
            android.util.Log.d("IncomingHandler", "SfuRoomCreated atlandi — call ACTIVE degil")
            return
        }
        val info = com.securechat.media.CallManager.SfuRoomBindInfo(
            roomId = signal.roomId,
            janusWsUrl = signal.janusWsUrl
        )
        callManager.bindSfuRoomFromInvite(localUserId, info)

        // activeGroupCalls state'inde SFU bilgisini ekle (sonradan katilim icin)
        val current = activeGroupCalls.value.toMutableMap()
        val existing = current[signal.groupId]
        if (existing != null) {
            current[signal.groupId] = existing.copy(
                mode = "SFU",
                sfuRoomId = signal.roomId,
                janusWsUrl = signal.janusWsUrl
            )
            activeGroupCalls.value = current
        }
    }

    /**
     * Sunucudan aktif grup arama durum cevabi — ChatScreen banner state'ini gunceller.
     */
    private fun handleGroupCallStatusResponse(signal: SignalMessage.GroupCallStatusResponse) {
        val current = activeGroupCalls.value.toMutableMap()
        val callId = signal.callId
        val coordinatorId = signal.coordinatorId
        val callType = signal.callType
        if (signal.isActive && callId != null && coordinatorId != null && callType != null) {
            current[signal.groupId] = ActiveGroupCallInfo(
                groupId = signal.groupId,
                callId = callId,
                coordinatorId = coordinatorId,
                callType = callType,
                participants = signal.participants,
                mode = signal.mode ?: "MESH",
                sfuRoomId = signal.sfuRoomId,
                janusWsUrl = signal.janusWsUrl
            )
        } else {
            current.remove(signal.groupId)
        }
        activeGroupCalls.value = current
        android.util.Log.d("IncomingHandler", "Grup arama durum guncellendi: ${signal.groupId} active=${signal.isActive}")
    }

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
    data class PollVoteRef(val pollMessageId: String, val optionIndex: Int)

    data class ParsedMessage(
        val messageId: String?,
        val replyToId: String?,
        val content: String,
        val contentType: MessageContentType = MessageContentType.TEXT,
        val pollVote: PollVoteRef? = null,
        /** EXP prefix'ten alinan mutlak expiresAt (ms). Yoksa null. */
        val absoluteExpiresAt: Long? = null,
        /** VIEWONCE prefix bayragi — tek gosterimlik metin mesaji. */
        val isViewOnce: Boolean = false
    )

    private fun parseMessageId(content: String): Pair<String?, String> {
        val parsed = parseMessageEnvelope(content)
        return Pair(parsed.messageId, parsed.content)
    }

    private fun parseMessageEnvelope(content: String): ParsedMessage {
        var remaining = content
        var messageId: String? = null
        var replyToId: String? = null
        var absoluteExpiresAt: Long? = null
        var isViewOnce = false

        // MSGID prefix
        if (remaining.startsWith("MSGID:")) {
            val firstColon = remaining.indexOf(':')
            val secondColon = remaining.indexOf(':', firstColon + 1)
            if (secondColon > firstColon) {
                messageId = remaining.substring(firstColon + 1, secondColon)
                remaining = remaining.substring(secondColon + 1)
            }
        }

        // REPLY prefix
        if (remaining.startsWith("REPLY:")) {
            val firstColon = remaining.indexOf(':')
            val secondColon = remaining.indexOf(':', firstColon + 1)
            if (secondColon > firstColon) {
                replyToId = remaining.substring(firstColon + 1, secondColon)
                remaining = remaining.substring(secondColon + 1)
            }
        }

        // EXP prefix — sureli mesaj icin mutlak expiresAt (ms). REPLY'dan sonra, POLL'den once.
        if (remaining.startsWith("EXP:")) {
            val firstColon = remaining.indexOf(':')
            val secondColon = remaining.indexOf(':', firstColon + 1)
            if (secondColon > firstColon) {
                absoluteExpiresAt = remaining.substring(firstColon + 1, secondColon).toLongOrNull()
                remaining = remaining.substring(secondColon + 1)
            }
        }

        // VIEWONCE prefix — tek gosterimlik metin mesaji bayragi (icerik degeri tasimaz).
        // POLL'den ONCE parse edilir, cunku POLL gorunce parser kalan her seyi icerik kabul eder.
        if (remaining.startsWith("VIEWONCE:")) {
            isViewOnce = true
            remaining = remaining.removePrefix("VIEWONCE:")
        }

        // POLLVOTE: prefix — anket oy guncellemesi (yeni mesaj olarak kaydedilmez,
        // mevcut anket mesajinin votes alanini gunceller)
        // Format: POLLVOTE:<pollMsgId>:<optionIndex>
        if (remaining.startsWith("POLLVOTE:")) {
            val parts = remaining.removePrefix("POLLVOTE:").split(":", limit = 2)
            if (parts.size == 2) {
                val pollMsgId = parts[0]
                val optionIdx = parts[1].toIntOrNull()
                if (optionIdx != null) {
                    return ParsedMessage(
                        messageId = messageId,
                        replyToId = null,
                        content = "",
                        contentType = MessageContentType.TEXT,
                        pollVote = PollVoteRef(pollMsgId, optionIdx),
                        absoluteExpiresAt = absoluteExpiresAt,
                        isViewOnce = isViewOnce
                    )
                }
            }
        }

        // POLL: prefix — anket mesaji
        if (remaining.startsWith("POLL:")) {
            return ParsedMessage(
                messageId = messageId,
                replyToId = replyToId,
                content = remaining.removePrefix("POLL:"),
                contentType = MessageContentType.POLL,
                pollVote = null,
                absoluteExpiresAt = absoluteExpiresAt,
                isViewOnce = isViewOnce
            )
        }

        return ParsedMessage(
            messageId = messageId,
            replyToId = replyToId,
            content = remaining,
            absoluteExpiresAt = absoluteExpiresAt,
            isViewOnce = isViewOnce
        )
    }

    /**
     * Karsi taraftan gelen oy bilgisini lokal anket mesajina uygular.
     * Var olan votes JSON'unu gunceller; tek secim modunda eski oyunu kaldirir,
     * toggle (zaten varsa cikarir) mantigiyla calisir.
     */
    private suspend fun applyRemotePollVote(senderId: String, vote: PollVoteRef) {
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

    /**
     * Gelen delivery receipt'i isler.
     * Mesaj durumunu DELIVERED veya READ olarak gunceller.
     * Durum yalnizca ileri yonde guncellenir (DELIVERED -> READ), geri alinmaz.
     */
    private suspend fun handleDeliveryReceipt(receipt: SignalMessage.DeliveryReceipt) {
        android.util.Log.d("IncomingHandler", "DeliveryReceipt: msgId=${receipt.messageId}, status=${receipt.status}")
        val newStatus = when (receipt.status) {
            "DELIVERED" -> MessageStatus.DELIVERED
            "READ" -> MessageStatus.READ
            else -> return
        }
        // Durum yalnizca ileri yonde guncellenir — geri alinmaz
        // SENDING < SENT < DELIVERED < READ siralamasi korunur
        val statusOrder = mapOf(
            MessageStatus.SENDING to 0,
            MessageStatus.SENT to 1,
            MessageStatus.DELIVERED to 2,
            MessageStatus.READ to 3,
            MessageStatus.FAILED to -1
        )
        val currentMessages = messageRepository.getMessageById(receipt.messageId)
        if (currentMessages != null) {
            val currentOrder = statusOrder[currentMessages.status] ?: -1
            val newOrder = statusOrder[newStatus] ?: -1
            if (newOrder > currentOrder) {
                messageRepository.updateMessageStatus(receipt.messageId, newStatus)
                android.util.Log.d("IncomingHandler", "Receipt: ${currentMessages.status} -> $newStatus")
            } else {
                android.util.Log.d("IncomingHandler", "Receipt ignored: ${currentMessages.status} >= $newStatus")
            }
        } else {
            // Mesaj bulunamadiysa yine de guncelle (race condition durumunda)
            messageRepository.updateMessageStatus(receipt.messageId, newStatus)
        }
    }

    /** Typing timeout job'lari — her kullanici icin ayri. */
    private val typingTimeoutJobs = mutableMapOf<String, kotlinx.coroutines.Job>()

    /**
     * Yazma gostergesini isler. Karsi taraf yazmaya basladiginda/biraktiginda UI'i gunceller.
     * 10 saniye sonra otomatik temizlenir (sinyal kaybolursa diye).
     */
    private fun handleTypingIndicator(signal: SignalMessage.TypingIndicator) {
        // Onceki timeout'u iptal et
        typingTimeoutJobs[signal.senderId]?.cancel()

        val current = typingStates.value.toMutableMap()
        if (signal.isTyping) {
            current[signal.senderId] = true
            typingStates.value = current
            // Guvenlik icin 10 saniye sonra otomatik temizle
            typingTimeoutJobs[signal.senderId] = scope.launch {
                kotlinx.coroutines.delay(10_000)
                val updated = typingStates.value.toMutableMap()
                updated.remove(signal.senderId)
                typingStates.value = updated
            }
        } else {
            current.remove(signal.senderId)
            typingStates.value = current
        }
    }

    private fun handlePresenceUpdate(signal: SignalMessage.PresenceUpdate) {
        val current = presenceStates.value.toMutableMap()
        // Karsi taraf son gorulmeyi gizliyorsa lastSeen=0 olarak kaydet
        val effectiveLastSeen = if (signal.hideLastSeen) 0L else signal.lastSeen
        current[signal.senderId] = PresenceInfo(
            isOnline = signal.isOnline,
            lastSeen = effectiveLastSeen
        )
        presenceStates.value = current
        android.util.Log.d("IncomingHandler", "Presence guncellendi: ${signal.senderId} online=${signal.isOnline} lastSeen=$effectiveLastSeen hideLastSeen=${signal.hideLastSeen} (toplam: ${current.size})")
    }

    /**
     * Karsi taraftan gelen sureli mesaj zamanlayici ayarini isler.
     * Konusmadaki disappearingDuration degerini gunceller.
     * conversationId bos ise senderId kullanilir (birebir sohbet, geriye uyumluluk).
     */
    private suspend fun handleDisappearingTimer(signal: SignalMessage.DisappearingTimer) {
        // conversationId bos ise birebir sohbet — senderId = konusma ID'si
        val targetConvId = signal.conversationId.ifBlank { signal.senderId }
        android.util.Log.d("IncomingHandler", "DisappearingTimer: duration=${signal.duration} from=${signal.senderId} conv=$targetConvId")
        conversationDao.updateDisappearingDuration(targetConvId, signal.duration)

        // Race penceresi: timer signal bazen ilk mesajdan biraz sonra gelir (WS sirasi farkli olabilir,
        // FCM push'tan oncelikli gelmis olabilir). Son N saniye icindeki, henuz expiresAt'i olmayan
        // gelen mesajlara retroaktif expiresAt uygula — boylece "timer biraz once acildi ama ilk
        // mesaj kacti" hatasi giderilir. Pencere: 60 saniye, sadece duration > 0 ise.
        if (signal.duration > 0) {
            val now = System.currentTimeMillis()
            val windowStart = now - RACE_WINDOW_MS
            try {
                messageRepository.applyRetroactiveExpiry(
                    conversationId = targetConvId,
                    duration = signal.duration,
                    windowStart = windowStart,
                    now = now
                )
            } catch (e: Exception) {
                android.util.Log.w("IncomingHandler", "Retroaktif expiresAt uygulanamadi: ${e.message}")
            }
        }
    }

    /**
     * Karsi taraftan gelen mesaj silme bildirimini isler.
     * Mesaj icerigini "Bu mesaj silindi" olarak gunceller.
     */
    private suspend fun handleMessageDelete(signal: SignalMessage.MessageDelete) {
        android.util.Log.d("IncomingHandler", "MessageDelete: msgId=${signal.messageId} from=${signal.senderId}")
        try {
            messageRepository.updateMessageContent(
                messageId = signal.messageId,
                content = "Bu mesaj silindi",
                contentType = "DELETED"
            )
            android.util.Log.d("IncomingHandler", "Mesaj basariyla silindi: ${signal.messageId}")

            // Konuşma listesinde son mesaj bu ise güncelle
            val conversationId = signal.senderId
            val conv = conversationDao.getById(conversationId)
            if (conv != null) {
                conversationDao.updateLastMessage(conversationId, "Bu mesaj silindi", conv.lastMessageTimestamp ?: System.currentTimeMillis())
            }
        } catch (e: Exception) {
            android.util.Log.e("IncomingHandler", "Mesaj silinirken hata: ${e.message}", e)
        }
    }

    /**
     * Karsi taraftan gelen mesaj duzenleme bildirimini isler.
     * Mesaj icerigini yeni icerikle gunceller ve editedAt zamanini kaydeder.
     */
    private suspend fun handleMessageEdit(signal: SignalMessage.MessageEdit) {
        android.util.Log.d("IncomingHandler", "MessageEdit: msgId=${signal.messageId} from=${signal.senderId}")
        try {
            messageRepository.editMessage(
                messageId = signal.messageId,
                newContent = signal.newContent,
                editedAt = signal.timestamp
            )
            android.util.Log.d("IncomingHandler", "Mesaj basariyla duzenlendi: ${signal.messageId}")
        } catch (e: Exception) {
            android.util.Log.e("IncomingHandler", "Mesaj duzenlenirken hata: ${e.message}", e)
        }
    }

    /**
     * Android bildirim gosterir. Gelen mesaj icin ses ve titresim ile bildirim olusturur.
     * Bildirim kanali yoksa olusturulur (Android 8+ zorunluluk).
     *
     * SMART LOGIC:
     * - Uygulama background'daysa her zaman bildirim goster
     * - Uygulama foreground'daysa sadece current chat'ten farkliysa bildirim goster
     */
    private suspend fun showMessageNotification(senderName: String, content: String, conversationId: String) {
        // Sessiz konusmalar icin bildirim gosterilir ama ses/titresim kapatilir
        val conv = conversationDao.getById(conversationId)
            ?: conversationDao.getByPeerId(conversationId)
        val isMutedRaw = conv?.isMuted == true

        // Sessize alinmis grupta bile @mention bildirim gonderilmeli
        val isMuted = if (isMutedRaw) {
            val currentUserId = userSession.userId ?: ""
            val currentDisplayName = userSession.displayName ?: ""
            val isMentioned = content.contains("@$currentUserId") ||
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

            else -> {
                android.util.Log.d("IncomingHandler", "Bilinmeyen grup aksiyonu: ${signal.action}")
            }
        }
    }
}
