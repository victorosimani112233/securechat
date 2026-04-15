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
@Singleton
class IncomingMessageHandler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val signalingClient: SignalingClient,
    private val messageRepository: MessageRepository,
    private val conversationDao: ConversationDao,
    private val callManager: CallManager,
    private val fileTransferManager: FileTransferManager,
    private val userSession: UserSession,
    private val incomingCallHandler: IncomingCallHandler,
    private val missedCallTracker: MissedCallTracker,
    private val themeManager: ThemeManager
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        /** Uygulama on plandaysa true */
        @Volatile
        var isAppInForeground = false

        /** Simdiki acik olan sohbet ID'si - bu sohbetten gelen mesajlar icin bildirim gosterilmez */
        @Volatile
        var currentChatId: String? = null

        /** Yazmakta olan kullanicilarin durumu: peerId -> true/false */
        val typingStates = kotlinx.coroutines.flow.MutableStateFlow<Map<String, Boolean>>(emptyMap())
    }

    fun start() {
        scope.launch {
            signalingClient.incomingSignals.collect { signal ->
                android.util.Log.d("IncomingHandler", "Sinyal geldi: ${signal::class.simpleName} from=${signal.senderId}")
                when (signal) {
                    is SignalMessage.EncryptedMessage -> handleEncryptedMessage(signal)
                    is SignalMessage.FileTransfer -> handleFileTransfer(signal)
                    is SignalMessage.SdpOffer -> handleIncomingCall(signal)
                    is SignalMessage.SdpAnswer -> callManager.handleSdpAnswer(signal)
                    is SignalMessage.IceCandidate -> callManager.handleIceCandidate(signal)
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
                    is SignalMessage.DisappearingTimer -> handleDisappearingTimer(signal)
                    is SignalMessage.TypingIndicator -> handleTypingIndicator(signal)
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

        // Konusma yoksa olustur
        val existingConv = conversationDao.getByPeerId(senderId)
        if (existingConv == null) {
            conversationDao.insert(
                ConversationEntity(
                    id = senderId,
                    peerId = senderId,
                    peerName = resolvePeerName(senderId),
                    peerPhone = "",
                    lastMessage = null,
                    lastMessageTimestamp = null,
                    unreadCount = 0,
                    isMuted = false,
                    isPinned = false
                )
            )
        }

        // Dosyayi yerel depolamaya kaydet
        val savedUri = fileTransferManager.saveReceivedFile(signal.fileName, signal.data)
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

        // Sureli mesaj kontrolu — konusmada sureli mesaj aktifse expiresAt hesapla
        val fileNow = System.currentTimeMillis()
        val fileDisappDuration = existingConv?.disappearingDuration ?: 0
        val fileExpiresAt = if (fileDisappDuration > 0) fileNow + fileDisappDuration else null

        val message = LocalMessage(
            id = UUID.randomUUID().toString(),
            conversationId = senderId,
            senderId = senderId,
            peerId = senderId,
            content = fileContent,
            contentType = contentType,
            timestamp = fileNow,
            status = MessageStatus.DELIVERED,
            isOutgoing = false,
            expiresAt = fileExpiresAt
        )
        messageRepository.saveMessage(message)

        // Foreground service'e dosya alındığını bildir
        MessagingService.updateForNewMessage(1)

        android.util.Log.d("IncomingHandler", "Dosya alindi: ${signal.fileName} (${signal.fileSize} byte)")
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

        // MSGID prefix'ini ayristir
        val (originalMessageId, actualContent) = parseMessageId(content)

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

        // Sureli mesaj kontrolu — grupta sureli mesaj aktifse expiresAt hesapla
        val now = System.currentTimeMillis()
        val groupDisappDuration = (groupConv ?: conversationDao.getById(groupId))?.disappearingDuration ?: 0
        val groupExpiresAt = if (groupDisappDuration > 0) now + groupDisappDuration else null

        // CRITICAL: Gondericinin orijinal mesaj ID'sini kullan — "herkesten sil" icin gerekli
        val message = LocalMessage(
            id = originalMessageId ?: UUID.randomUUID().toString(),
            conversationId = groupId,
            senderId = senderId,
            peerId = senderId,
            content = actualContent,
            contentType = MessageContentType.TEXT,
            timestamp = now,
            status = MessageStatus.DELIVERED,
            isOutgoing = false,
            expiresAt = groupExpiresAt
        )
        messageRepository.saveMessage(message)

        // Foreground service'e mesaj geldiğini bildir
        MessagingService.updateForNewMessage(1)

        // Bildirim goster
        val senderName = resolvePeerName(senderId)
        val displayGroupName = groupConv?.peerName ?: groupName ?: "Grup"
        showMessageNotification("$senderName ($displayGroupName)", actualContent, groupId)

        // DELIVERED receipt gonder
        if (originalMessageId != null) {
            sendDeliveryReceipt(senderId, originalMessageId, "DELIVERED")
        }
    }

    /**
     * Birebir mesaji isler. Konusma yoksa yeni konusma olusturur.
     * MSGID prefix'i varsa ayristirilir ve DELIVERED receipt gonderilir.
     */
    private suspend fun handleDirectMessage(senderId: String, content: String) {
        // MSGID prefix'ini ayristir — geriye uyumluluk icin prefix yoksa da calisir
        val (originalMessageId, actualContent) = parseMessageId(content)

        // Konusma yoksa olustur
        val existingConv = conversationDao.getByPeerId(senderId)
        if (existingConv == null) {
            conversationDao.insert(
                ConversationEntity(
                    id = senderId,
                    peerId = senderId,
                    peerName = resolvePeerName(senderId),
                    peerPhone = "",
                    lastMessage = null,
                    lastMessageTimestamp = null,
                    unreadCount = 0,
                    isMuted = false,
                    isPinned = false
                )
            )
        }

        // Sureli mesaj kontrolu — konusmada sureli mesaj aktifse expiresAt hesapla
        val now = System.currentTimeMillis()
        val disappDuration = existingConv?.disappearingDuration ?: 0
        val expiresAt = if (disappDuration > 0) now + disappDuration else null

        // Yerel saat kullan — cihaz saati farklari mesaj sirasini bozmasin
        // CRITICAL: Gondericinin orijinal mesaj ID'sini kullan — "herkesten sil" icin gerekli
        val message = LocalMessage(
            id = originalMessageId ?: UUID.randomUUID().toString(),
            conversationId = senderId,
            senderId = senderId,
            peerId = senderId,
            content = actualContent,
            contentType = MessageContentType.TEXT,
            timestamp = now,
            status = MessageStatus.DELIVERED,
            isOutgoing = false,
            expiresAt = expiresAt
        )
        messageRepository.saveMessage(message)

        // Foreground service'e mesaj geldiğini bildir
        MessagingService.updateForNewMessage(1)

        // Bildirim goster
        val senderName = resolvePeerName(senderId)
        showMessageNotification(senderName, actualContent, senderId)

        // DELIVERED receipt gonder — gonderici mesajin ulastigini gorur
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

            // Bildirim goster (arka plan icin) - HER ZAMAN göster
            incomingCallHandler.showIncomingCall(
                session = session,
                peerName = peerName,
                fullScreenActivityClass = IncomingCallActivity::class.java
            )

            // Direkt Activity baslat - uygulama kapalı bile olsa çalışır
            try {
                val intent = android.content.Intent(context, IncomingCallActivity::class.java).apply {
                    putExtra("peer_id", signal.senderId)
                    putExtra("peer_name", peerName)
                    putExtra("call_type", signal.callType.name)
                    // Kritik flagler - sistem seviye aktivasyon
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NO_USER_ACTION)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                }
                context.startActivity(intent)
                android.util.Log.d("IncomingHandler", "IncomingCallActivity başlatıldı - Background call detection başarılı")
            } catch (e: Exception) {
                android.util.Log.e("IncomingHandler", "IncomingCallActivity başlatılamadı: ${e.message}")
                // Fallback: En azından bildirim çalışıyor
            }

            // MessagingService'e incoming call bildir
            MessagingService.updateForNewMessage(0) // Call notification olduğu için counter artırma

            // Missed call timer'ı başlat
            missedCallTracker.startMissedCallTimer(session, peerName)
        }
    }

    /**
     * Arama kontrol mesajlarini isler.
     */
    private fun handleCallControl(signal: SignalMessage.CallControl) {
        val session = callManager.currentSession

        when (signal.action) {
            CallAction.ACCEPT -> {
                // ACCEPT mesajini sadece OUTGOING/RINGING aramalarda isle
                // INCOMING aramalar zaten acceptCall() ile local olarak handle ediliyor
                if (session?.direction == com.securechat.media.model.CallDirection.OUTGOING &&
                    session.state == com.securechat.media.model.CallState.RINGING) {
                    callManager.onCallConnected()
                    // Timer iptal et - arama kabul edildi
                    session.callId?.let { missedCallTracker.cancelMissedCallTimer(it) }
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
                callManager.onRemoteHangup()
                // Timer iptal et - arama sonlandırıldı
                session?.callId?.let { missedCallTracker.cancelMissedCallTimer(it) }
            }
            CallAction.BUSY -> {
                callManager.onRemoteBusy()
                // Timer iptal et - karşı taraf meşgul
                session?.callId?.let { missedCallTracker.cancelMissedCallTimer(it) }
            }
            CallAction.RINGING -> { /* Karsi taraf calıyor — bilgi amacli */ }
        }
    }

    /**
     * Kullanici kimliginden goruntuleme adini cozer.
     * Oncelikle mevcut konusmalardan isim aranir, bulunamazsa userId doner.
     */
    private suspend fun resolvePeerName(userId: String): String {
        // Mevcut konusmada kayitli isim varsa onu kullan
        val existingConv = conversationDao.getByPeerId(userId)
        if (existingConv != null && existingConv.peerName != userId && existingConv.peerName.isNotBlank()) {
            return existingConv.peerName
        }
        // Fallback: userId'yi dondur (telefon numarasi veya kullanici kimligini gosterir)
        return userId
    }

    /**
     * MSGID prefix'ini ayristirir. Format: "MSGID:uuid:actualContent"
     * Prefix yoksa (geriye uyumluluk) icerik oldugu gibi doner.
     *
     * @return Pair(originalMessageId, actualContent) — messageId null olabilir
     */
    private fun parseMessageId(content: String): Pair<String?, String> {
        if (content.startsWith("MSGID:")) {
            val firstColon = content.indexOf(':') // "MSGID" sonrasi
            val secondColon = content.indexOf(':', firstColon + 1)
            if (secondColon > firstColon) {
                val messageId = content.substring(firstColon + 1, secondColon)
                val actualContent = content.substring(secondColon + 1)
                return Pair(messageId, actualContent)
            }
        }
        return Pair(null, content)
    }

    /**
     * Gondericiye delivery receipt gonderir.
     * Mesajin aliciya ulastigini (DELIVERED) veya okundugunu (READ) bildirir.
     */
    private fun sendDeliveryReceipt(recipientId: String, messageId: String, status: String) {
        val localUserId = userSession.userId ?: return
        signalingClient.sendSignal(
            SignalMessage.DeliveryReceipt(
                senderId = localUserId,
                recipientId = recipientId,
                timestamp = System.currentTimeMillis(),
                messageId = messageId,
                status = status
            )
        )
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
        messageRepository.updateMessageStatus(receipt.messageId, newStatus)
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
                content = "\u00AD Bu mesaj silindi",
                contentType = "DELETED"
            )
        } catch (e: Exception) {
            android.util.Log.e("IncomingHandler", "Mesaj silinirken hata", e)
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
        } catch (_: Exception) {
            true
        }

        val channelId = "elcim_messages_v4"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Eski kanallari temizle
        nm.deleteNotificationChannel("messages")
        nm.deleteNotificationChannel("elci_messages_v2")
        nm.deleteNotificationChannel("elci_messages_v3")
        if (nm.getNotificationChannel(channelId) == null) {
            val channel = NotificationChannel(channelId, "Elçim Mesajlar", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Elçim - Gelen mesaj bildirimleri"
                enableVibration(true)
                enableLights(true)
                lightColor = 0xFF00897B.toInt()
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }

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

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(com.securechat.app.R.mipmap.ic_launcher)
            .setColor(0xFF00897B.toInt())
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)

        if (showContent) {
            // Icerik gosterim modu: gonderici adi, mesaj icerigi, avatar
            val shortcutId = "contact_$conversationId"
            val person = androidx.core.app.Person.Builder()
                .setName(senderName)
                .setKey(conversationId)
                .setIcon(androidx.core.graphics.drawable.IconCompat.createWithBitmap(appIconBitmap))
                .setImportant(true)
                .build()

            // Conversation shortcut — Samsung'da MessagingStyle icin
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
                .addMessage(content, System.currentTimeMillis(), person)

            builder.setStyle(messagingStyle)
                .setShortcutId(shortcutId)
                .setSubText("Elçim")
        } else {
            // Gizlilik modu: icerik gosterilmez
            builder.setContentTitle("Elçim")
                .setContentText("Yeni mesaj")
                .setSubText("Elçim")
        }

        try {
            nm.notify(conversationId.hashCode(), builder.build())
            android.util.Log.d("IncomingHandler", "Bildirim gosterildi: $senderName (showContent=$showContent)")
        } catch (e: SecurityException) {
            android.util.Log.e("IncomingHandler", "Bildirim gosterilemedi (izin yok): ${e.message}")
        }
    }

    /**
     * Uygulama launcher ikonunu bildirim avatari olarak dondurur.
     */
    private fun getAppIconBitmap(): android.graphics.Bitmap {
        val drawable = context.packageManager.getApplicationIcon(context.applicationInfo)
        val size = 128
        val bitmap = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return bitmap
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
                            lastMessage = "${signal.senderId} grubu oluşturdu",
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

                    // Sistem mesajı kaydet
                    val targetMember = signal.targetMemberId ?: "bilinmeyen"
                    val systemMessage = "${signal.senderId}, ${targetMember}'i gruba ekledi"

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
                    android.util.Log.d("IncomingHandler", "Grup üye listesi güncelleniyor: ${signal.groupId}")
                    conversationDao.updateGroupMembers(signal.groupId, signal.groupMembers.joinToString(","))

                    // Sistem mesajı kaydet
                    val targetMember = signal.targetMemberId ?: "bilinmeyen"
                    val systemMessage = "${signal.senderId}, ${targetMember}'i gruptan çıkardı"

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

                    // Sistem mesaji kaydet
                    val systemMessage = "${signal.senderId}, ${targetMember}'i yonetici yapti"
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
