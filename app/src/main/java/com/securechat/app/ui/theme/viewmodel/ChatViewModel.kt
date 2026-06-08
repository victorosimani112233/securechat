package com.securechat.app.ui.viewmodel

import android.content.SharedPreferences
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.MarkAsReadUseCase
import com.securechat.app.domain.usecase.ObserveMessagesUseCase
import com.securechat.app.domain.usecase.SendMessageUseCase
import com.securechat.media.FileTransferManager
import com.securechat.media.FileTransferResult
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import com.securechat.storage.resolver.ContactNameResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import javax.inject.Inject

/**
 * Sohbet ekrani ViewModel'i.
 * Mesaj gonderme, dosya gonderme, mesajlari gozlemleme, okundu isaretleme,
 * mesaj silme ve grup konusma bilgisi yonetir.
 */
@HiltViewModel
class ChatViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val sendMessageUseCase: SendMessageUseCase,
    private val observeMessagesUseCase: ObserveMessagesUseCase,
    private val markAsReadUseCase: MarkAsReadUseCase,
    private val messageRepository: MessageRepository,
    private val conversationDao: ConversationDao,
    private val fileTransferManager: FileTransferManager,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val contactNameResolver: ContactNameResolver,
    private val sharedPreferences: SharedPreferences,
    private val callManager: com.securechat.media.CallManager,
    private val exportBannerAckStore: com.securechat.app.data.ExportBannerAckStore,
    private val recordExportEventUseCase: com.securechat.app.domain.usecase.RecordExportEventUseCase
) : ViewModel() {

    /** Navigation argument'inden alinan konusma kimlik numarasi. */
    val conversationId: String = savedStateHandle.get<String>("conversationId") ?: ""

    /** Yerel kullanicinin kimligi — anket UI'inda hangi secenegi kendisinin oyladigini bulmak icin gerekli. */
    val currentUserId: String = userSession.userId ?: ""

    /** Sayfalama icin her seferde yuklenen mesaj sayisi. */
    private val PAGE_SIZE = 50

    /** Esanli dosya gonderimini sinirlar — UI donmasini engeller (maks 3). */
    private val fileUploadSemaphore = Semaphore(3)

    /** Mevcut mesaj limiti — loadMore() cagrildiginda artar. */
    private val _messageLimit = MutableStateFlow(PAGE_SIZE)

    /** Daha eski mesaj yuklenebilir mi. */
    private val _hasMoreMessages = MutableStateFlow(true)
    val hasMoreMessages: StateFlow<Boolean> = _hasMoreMessages.asStateFlow()

    /** Konusmadaki mesajlarin reaktif listesi (sayfalamali). */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    val messages: StateFlow<List<LocalMessage>> = _messageLimit.flatMapLatest { limit ->
        messageRepository.getRecentMessages(conversationId, limit)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Konusma bilgisi — grup mu, ismi, uye sayisi vb. */
    private val _conversationInfo = MutableStateFlow<ConversationInfo?>(null)
    val conversationInfo: StateFlow<ConversationInfo?> = _conversationInfo.asStateFlow()

    /** Dosya gonderim durumu — hata mesajlari icin. */
    private val _fileTransferEvent = MutableSharedFlow<String>()
    val fileTransferEvent: SharedFlow<String> = _fileTransferEvent.asSharedFlow()

    /** Aktif upload ilerleme durumu — messageId -> progress yuzde (0-100). */
    private val _uploadProgress = MutableStateFlow<Map<String, Int>>(emptyMap())
    val uploadProgress: StateFlow<Map<String, Int>> = _uploadProgress.asStateFlow()

    // --- Sohbet ici arama state'leri ---
    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _searchResultIds = MutableStateFlow<List<String>>(emptyList())
    val searchResultIds: StateFlow<List<String>> = _searchResultIds.asStateFlow()

    private val _currentSearchIndex = MutableStateFlow(-1)
    val currentSearchIndex: StateFlow<Int> = _currentSearchIndex.asStateFlow()

    /** Highlight edilecek mesaj ID'si. */
    private val _highlightedMessageId = MutableStateFlow<String?>(null)
    val highlightedMessageId: StateFlow<String?> = _highlightedMessageId.asStateFlow()

    /** Sureli mesaj suresi (ms). 0 = kapali. */
    private val _disappearingDuration = MutableStateFlow(0L)
    val disappearingDuration: StateFlow<Long> = _disappearingDuration.asStateFlow()

    /** Sohbet disa aktarma izni — grup sohbetleri icin. Kapali ise kopya engellenir. */
    private val _isExportEnabled = MutableStateFlow(false)
    val isExportEnabled: StateFlow<Boolean> = _isExportEnabled.asStateFlow()

    /** Grup sohbeti mi? — UI'da export kararlari bunu kullanir (1:1 sohbet etkilenmez). */
    private val _isGroupChat = MutableStateFlow(false)
    val isGroupChat: StateFlow<Boolean> = _isGroupChat.asStateFlow()

    /** Export izin banner'i — admin yeni katilanlari bilgilendirmek icin. */
    private val _shouldShowExportBanner = MutableStateFlow(false)
    val shouldShowExportBanner: StateFlow<Boolean> = _shouldShowExportBanner.asStateFlow()

    /** Kullanici banner'i kapatti — bir daha ayni durum icin gosterme. */
    fun acknowledgeExportBanner() {
        exportBannerAckStore.acknowledge(conversationId)
        _shouldShowExportBanner.value = false
    }

    /** Export durumu degistiginde banner gorunurlugunu yeniden hesapla. */
    private fun refreshExportBannerVisibility() {
        _shouldShowExportBanner.value =
            _isGroupChat.value &&
            _isExportEnabled.value &&
            exportBannerAckStore.shouldShow(conversationId)
    }

    /** Karsi taraf yaziyor mu. */
    val peerIsTyping: StateFlow<Boolean> = IncomingMessageHandler.typingStates
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())
        .let { flow ->
            val result = MutableStateFlow(false)
            viewModelScope.launch {
                flow.collect { map ->
                    result.value = map[conversationId] == true
                }
            }
            result
        }

    /** Karsi taraf cevrimici mi. */
    val peerPresence: StateFlow<IncomingMessageHandler.PresenceInfo?> = IncomingMessageHandler.presenceStates
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())
        .let { flow ->
            val result = MutableStateFlow<IncomingMessageHandler.PresenceInfo?>(null)
            viewModelScope.launch {
                flow.collect { map ->
                    result.value = map[conversationId]
                }
            }
            result
        }

    private var isCurrentlyTyping = false

    /** Scroll hedefi — belirli bir mesaja scroll tetikler. */
    private val _scrollToMessageId = MutableSharedFlow<String>()
    val scrollToMessageId: SharedFlow<String> = _scrollToMessageId.asSharedFlow()

    /** READ receipt gonderdigi mesaj ID'leri — duplicate onleme. */
    private val readReceiptSentIds = mutableSetOf<String>()

    init {
        // Ekran acildiginda konusmayi okundu olarak isaretle ve bilgilerini yukle
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            markAsReadUseCase(conversationId)
            loadConversationInfo()
            // Sureli mesaj ayarini yukle
            val conv = conversationDao.getById(conversationId)
            _disappearingDuration.value = conv?.disappearingDuration ?: 0
            _isGroupChat.value = conv?.isGroup == true
            _isExportEnabled.value = conv?.isExportEnabled == true
        }

        // Export izni admin tarafindan toggle edilince DB guncellenir + sistem mesaji
        // gelir; Flow ile dinleyip live update — banner & kopya menusu anlik reaksiyon verir.
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            conversationDao.observeById(conversationId).collect { entity ->
                if (entity != null) {
                    _isExportEnabled.value = entity.isExportEnabled
                    _isGroupChat.value = entity.isGroup
                    refreshExportBannerVisibility()
                }
            }
        }

        // Sohbet acildiginda SENDING durumunda takilmis mesajlari FAILED olarak isaretle
        // 2 dakikadan eski SENDING mesajlar gonderim sirasinda takilmis kabul edilir
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            recoverStuckSendingMessages()
        }

        // Sohbet acikken gelen mesajlari surekli izle ve READ receipt gonder
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            markIncomingMessagesAsRead()
        }

        // Sureli mesajlari periyodik olarak temizle.
        // Acilista bir kez hemen calistir, sonra interval ile devam et — interval konusmadaki
        // disappearingDuration'a gore dinamik: kisa timer'larda agresif kontrol, uzun timer'larda
        // batarya dostu. Boylelikle 30sn timer maksimum ~5sn gecikmeyle siliniyor.
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            // Ilk acilis cleanup'i — onceki seansta dolan mesajlar varsa hemen gitsin
            runCatching { messageRepository.deleteExpiredMessages() }
            while (true) {
                val intervalMs = when {
                    _disappearingDuration.value in 1..60_000L -> 5_000L
                    _disappearingDuration.value in 60_001..3_600_000L -> 15_000L
                    else -> 60_000L
                }
                kotlinx.coroutines.delay(intervalMs)
                val deleted = messageRepository.deleteExpiredMessages()
                if (deleted > 0) {
                    android.util.Log.d("ChatViewModel", "Sureli mesaj temizlendi: $deleted")
                }
            }
        }

        // Baglanti kuruldugunda bekleyen silme islemlerini gonder
        viewModelScope.launch {
            signalingClient.connectionState.collect { state ->
                if (state is ConnectionState.Connected) {
                    flushPendingDeletes()
                }
            }
        }

        // Presence subscribe: Bu kisi icin cevrimici durumunu sunucudan iste
        // Grup sohbetlerinde presence subscribe YAPILMAZ — group_uuid gercek bir kullanici degil
        if (!conversationId.startsWith("group_")) {
            viewModelScope.launch {
                signalingClient.connectionState.collect { state ->
                    if (state is com.securechat.network.model.ConnectionState.Connected) {
                        signalingClient.subscribePresence(conversationId)
                    }
                }
            }
        }

        // Current chat tracking: Bu sohbet acildiginda bildirim sistemine bildir
        IncomingMessageHandler.currentChatId = conversationId
        android.util.Log.d("ChatViewModel", "Current chat set to: $conversationId")

        // Grup sohbeti acildiginda sunucudan aktif grup arama durumunu sorgula —
        // banner bu cevap ile populate edilir.
        if (conversationId.startsWith("group_")) {
            viewModelScope.launch {
                signalingClient.connectionState.collect { state ->
                    if (state is ConnectionState.Connected) {
                        val uid = userSession.userId ?: return@collect
                        signalingClient.sendSignal(
                            com.securechat.network.SignalMessage.GroupCallStatusQuery(
                                senderId = uid,
                                recipientId = "server",
                                timestamp = System.currentTimeMillis(),
                                groupId = conversationId
                            )
                        )
                    }
                }
            }
        }
    }

    /**
     * Bu sohbet (grup) icin aktif grup arama bilgisi — ChatScreen banner observe eder.
     * Kullanici zaten bir aramadaysa (callManager.callSession != null) banner gizlenir.
     */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    val activeGroupCallForChat: StateFlow<IncomingMessageHandler.Companion.ActiveGroupCallInfo?> =
        kotlinx.coroutines.flow.combine(
            IncomingMessageHandler.activeGroupCalls,
            callManager.callSession
        ) { activeMap, currentSession ->
            val info = activeMap[conversationId] ?: return@combine null
            // Kullanici zaten bir aramada ise banner gosterme
            if (currentSession != null && (
                currentSession.state == com.securechat.media.model.CallState.RINGING ||
                currentSession.state == com.securechat.media.model.CallState.ACTIVE ||
                currentSession.state == com.securechat.media.model.CallState.INITIATING
            )) {
                return@combine null
            }
            info
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /**
     * Aktif grup aramasina sonradan katil — banner tap callback'i.
     * Hem mesh hem SFU modunu CallManager.joinGroupCall icinde handle edilir.
     */
    fun joinActiveGroupCall() {
        val info = activeGroupCallForChat.value ?: return
        val uid = userSession.userId ?: return
        val sfuInfo = if (info.mode == "SFU" && info.sfuRoomId != null && info.janusWsUrl != null) {
            com.securechat.media.CallManager.SfuRoomBindInfo(
                roomId = info.sfuRoomId,
                janusWsUrl = info.janusWsUrl
            )
        } else null

        callManager.joinGroupCall(
            userId = uid,
            groupId = info.groupId,
            callId = info.callId,
            coordinatorId = info.coordinatorId,
            callType = info.callType,
            sfuRoomInfo = sfuInfo
        )
    }

    override fun onCleared() {
        super.onCleared()
        // Presence unsubscribe (gruplarda subscribe yapilmadigi icin unsubscribe de yapilmaz)
        if (!conversationId.startsWith("group_")) {
            signalingClient.unsubscribePresence(conversationId)
        }
        // Chat screen kapatildiginda current chat'i temizle
        IncomingMessageHandler.currentChatId = null

        // GUVENLIK (M12 fix): Hassas state'leri temizle — memory dump'larda mesaj icerigi
        // veya search query'si gorunmesin. messages StateFlow zaten WhileSubscribed(5000)
        // ile GC eligible, ama diger state'leri explicit sifirla.
        _searchQuery.value = ""
        _searchResultIds.value = emptyList()
        _highlightedMessageId.value = null
        _conversationInfo.value = null
        _uploadProgress.value = emptyMap()
        draftMessages.remove(conversationId)

        android.util.Log.d("ChatViewModel", "Current chat cleared, sensitive state wiped")
    }

    /** Taslak mesaji kaydeder — kullanici sohbetten cikarken cagrilir. */
    fun saveDraft(text: String) {
        if (text.isBlank()) {
            draftMessages.remove(conversationId)
        } else {
            draftMessages[conversationId] = text
        }
    }

    /** Kayitli taslak mesaji getirir. */
    fun getDraft(): String = draftMessages[conversationId] ?: ""

    /**
     * Daha eski mesajlari yukler (sayfalama).
     * Kullanici liste basina scroll ettiginde cagrilir.
     */
    fun loadMore() {
        val currentLimit = _messageLimit.value
        val currentSize = messages.value.size
        // Mevcut mesaj sayisi limitten azsa, daha fazla mesaj yoktur
        if (currentSize < currentLimit) {
            _hasMoreMessages.value = false
            return
        }
        _messageLimit.value = currentLimit + PAGE_SIZE
    }

    companion object {
        /** Oturum boyunca sohbet taslaklarini tutar. */
        private val draftMessages = mutableMapOf<String, String>()

        /** SharedPreferences anahtari: cevrimdisi silme islemlerinin kuyrugu. */
        private const val PREF_PENDING_DELETES = "pending_deletes"

        /** SENDING durumunda takili kalmis mesajlar icin esik suresi (2 dakika). */
        private const val STUCK_MESSAGE_THRESHOLD_MS = 2 * 60 * 1000L
    }

    /**
     * Sohbet acikken gelen (okunmamis) mesajlari surekli izler.
     * Her yeni incoming mesaj icin:
     * 1. Veritabaninda READ olarak isaretler
     * 2. Karsi tarafa READ receipt gonderir (mavi cift tik)
     *
     * Room Flow uzerinden calisir — ilk emisyon mevcut mesajlari,
     * sonraki emisyonlar yeni gelen mesajlari icerir.
     */
    private suspend fun markIncomingMessagesAsRead() {
        val localUserId = userSession.userId ?: return
        // observeMessagesUseCase ve foreground state'ini combine et — sadece foreground=true
        // iken READ marking yap. Foreground'a tekrar gecince de bekleyen mesajlari yakalar.
        kotlinx.coroutines.flow.combine(
            observeMessagesUseCase(conversationId),
            IncomingMessageHandler.isAppInForegroundFlow
        ) { messageList, isForeground -> messageList to isForeground }
            .collect { (messageList, isForeground) ->
                if (!isForeground) return@collect

                val unreadIncoming = messageList.filter {
                    !it.isOutgoing && it.status != MessageStatus.READ && it.id !in readReceiptSentIds
                }
                if (unreadIncoming.isEmpty()) return@collect

                // ID'leri hemen rezerv et — Flow bu collector'i yeniden tetiklerse
                // (DB updateMessageStatus emit'i) ayni mesajlar tekrar islenmesin.
                for (msg in unreadIncoming) readReceiptSentIds.add(msg.id)

                // DELIVERED tikinin gonderici tarafindan gozlenebilmesi icin minik bekleme.
                // IncomingMessageHandler mesaj geldiginde DELIVERED receipt'i anlik gonderir;
                // bu delay olmadan READ receipt 10-50ms sonra giderdi ve gonderici tarafta
                // gri cift tik hic gorunmeden direkt maviye gecerdi. Local network'te dogal
                // latency yok, o yuzden kasitli bir pencere koyuyoruz (WhatsApp ~500-800ms).
                kotlinx.coroutines.delay(800)

                for (msg in unreadIncoming) {
                    messageRepository.updateMessageStatus(msg.id, MessageStatus.READ)
                    signalingClient.sendSignal(
                        SignalMessage.DeliveryReceipt(
                            senderId = localUserId,
                            recipientId = msg.senderId,
                            timestamp = System.currentTimeMillis(),
                            messageId = msg.id,
                            status = "READ"
                        )
                    )
                }
            }
    }

    /**
     * SENDING durumunda takilmis mesajlari kurtarir.
     * 2 dakikadan eski SENDING mesajlar FAILED olarak isaretlenir.
     */
    private suspend fun recoverStuckSendingMessages() {
        try {
            val stuckMessages = messageRepository.getStuckSendingMessages(STUCK_MESSAGE_THRESHOLD_MS)
            for (msg in stuckMessages) {
                messageRepository.updateMessageStatus(msg.id, MessageStatus.FAILED)
            }
            if (stuckMessages.isNotEmpty()) {
                android.util.Log.w("ChatViewModel", "Takili ${stuckMessages.size} mesaj FAILED yapildi")
            }
        } catch (e: Exception) {
            android.util.Log.e("ChatViewModel", "Takilmis mesaj kurtarma hatasi", e)
        }
    }

    private suspend fun loadConversationInfo() {
        val entity = conversationDao.getById(conversationId)
        if (entity != null) {
            val members = entity.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            // Grup uyelerinin goruntuleme adlarini tek sorguda coz (N+1 fix)
            val memberNames = mutableMapOf<String, String>()
            if (members.isNotEmpty()) {
                val memberConvs = conversationDao.getByPeerIds(members)
                val convByPeerId = memberConvs.associateBy { it.peerId }
                for (memberId in members) {
                    val memberConv = convByPeerId[memberId]
                    if (memberConv != null && memberConv.peerName.isNotBlank() && memberConv.peerName != memberId) {
                        memberNames[memberId] = memberConv.peerName
                    } else {
                        try {
                            val resolved = contactNameResolver.resolveDisplayName(memberId)
                            if (resolved != memberId) memberNames[memberId] = resolved
                        } catch (_: Exception) { }
                    }
                }
            }

            // Eger isim hala UUID gibi gorunuyorsa, cozumlemeyi dene
            var displayName = entity.peerName
            if (displayName == entity.peerId || displayName.isBlank()) {
                try {
                    val resolved = contactNameResolver.resolveDisplayName(entity.peerId)
                    if (resolved != entity.peerId) {
                        displayName = resolved
                        conversationDao.updatePeerName(conversationId, resolved)
                    }
                } catch (_: Exception) { }
            }

            // Birebir sohbette peer'i de memberNames'e ekle — reply bubble UUID yerine isim gostersin
            if (!entity.isGroup) {
                memberNames[entity.peerId] = displayName
            }

            // peerPhone bozuk olabilir: UUID veya isim kaydedilmis olabilir
            var phoneNumber = entity.peerPhone
            val isBroken = phoneNumber == entity.peerId
                || (phoneNumber == entity.peerName && !phoneNumber.startsWith("+"))
                || phoneNumber.isBlank()
            if (isBroken) {
                // contactNameResolver ile gercek numarayi coz
                val resolved = contactNameResolver.resolvePhoneNumber(entity.peerId)
                phoneNumber = resolved.ifBlank {
                    if (displayName.startsWith("+")) displayName else ""
                }
                if (phoneNumber != entity.peerPhone) {
                    conversationDao.update(entity.copy(peerPhone = phoneNumber))
                }
            }

            _conversationInfo.value = ConversationInfo(
                name = displayName,
                phoneNumber = phoneNumber,
                isGroup = entity.isGroup,
                memberCount = members.size,
                members = members,
                memberNames = memberNames,
                isMuted = entity.isMuted
            )
        } else {
            // Konusma DB'de yok — rehberden yeni acilan sohbet.
            // ContactNameResolver ile ismi coz ve goster.
            try {
                val resolved = contactNameResolver.resolveDisplayName(conversationId)
                val displayName = if (resolved != conversationId) resolved else conversationId
                _conversationInfo.value = ConversationInfo(
                    name = displayName,
                    phoneNumber = if (displayName.startsWith("+")) displayName else "",
                    isGroup = false,
                    memberCount = 0,
                    members = emptyList(),
                    memberNames = mapOf(conversationId to displayName)
                )
            } catch (_: Exception) {
                _conversationInfo.value = ConversationInfo(
                    name = conversationId,
                    phoneNumber = "",
                    isGroup = false,
                    memberCount = 0,
                    members = emptyList(),
                    memberNames = emptyMap()
                )
            }
        }
    }

    /**
     * Yeni bir metin mesaji gonderir.
     *
     * @param content Mesaj icerigi
     */
    fun sendMessage(content: String, replyToId: String? = null, isViewOnce: Boolean = false) {
        viewModelScope.launch {
            sendMessageUseCase(conversationId, content, replyToId, isViewOnce = isViewOnce)
        }
    }

    /**
     * Gonderimi basarisiz olan mesaji tekrar gondermeyi dener.
     * Metin mesajlari SendMessageUseCase uzerinden, dosya mesajlari
     * FileTransferManager uzerinden yeniden gonderilir.
     * Onceki basarisiz mesaj silinir ve yeni mesaj olusturulur.
     */
    fun retryMessage(messageId: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val failedMessage = messageRepository.getMessageById(messageId) ?: return@launch
            if (failedMessage.status != MessageStatus.FAILED) return@launch

            if (failedMessage.isFileMessage) {
                // Dosya mesaji — lokal kopyadan tekrar gonder
                val filePath = failedMessage.filePath
                if (filePath.isNullOrBlank()) {
                    _fileTransferEvent.emit("Dosya bulunamadi, tekrar gonderilemez")
                    return@launch
                }
                val file = java.io.File(filePath)
                if (!file.exists()) {
                    _fileTransferEvent.emit("Dosya bulunamadi, tekrar gonderilemez")
                    return@launch
                }
                // Onceki basarisiz mesaji sil
                messageRepository.deleteMessage(messageId)
                // Dosyayi tekrar gonder (lokal path'ten Uri olustur)
                val uri = android.net.Uri.fromFile(file)
                sendFile(uri)
            } else {
                // Metin mesaji — onceki basarisiz mesaji sil ve tekrar gonder
                val content = failedMessage.content
                val replyToId = failedMessage.replyToId
                messageRepository.deleteMessage(messageId)
                sendMessageUseCase(conversationId, content, replyToId)
            }
        }
    }

    /**
     * Tek gosterimlik medyayi goruntulendi olarak isaretler.
     * Yerel DB guncellenir ve gondericiye karsi tarafin gordugu bilgisi
     * delivery receipt mantigiyla iletilir.
     */
    fun markViewOnceAsViewed(messageId: String) {
        viewModelScope.launch {
            messageRepository.markViewOnceAsViewed(messageId)
        }
    }

    /**
     * Anket mesaji gonderir. SendMessageUseCase uzerinden retry destekli gonderim yapar.
     */
    fun sendPollMessage(pollJson: String) {
        viewModelScope.launch {
            sendMessageUseCase(conversationId, pollJson, contentType = MessageContentType.POLL)
        }
    }

    /**
     * Ankete oy verir. Lokal mesaji gunceller ve karsi tarafa POLLVOTE iletir.
     *
     * Envelope formati: MSGID:<voteId>:POLLVOTE:<pollMsgId>:<optionIndex>
     */
    fun votePoll(pollMessageId: String, optionIndex: Int) {
        viewModelScope.launch {
            val senderId = userSession.userId ?: "unknown"
            val pollMessage = messageRepository.getMessageById(pollMessageId) ?: return@launch

            // Mevcut poll JSON'unu parse et ve oyu ekle
            val json = try { JSONObject(pollMessage.content) } catch (_: Exception) { return@launch }
            val votesObj = json.optJSONObject("votes") ?: JSONObject()
            val singleChoice = json.optBoolean("singleChoice", true)

            // Tek secimde onceki oyu kaldir
            if (singleChoice) {
                val keys = votesObj.keys().asSequence().toList()
                for (key in keys) {
                    val arr = votesObj.optJSONArray(key) ?: continue
                    val filtered = JSONArray()
                    for (i in 0 until arr.length()) {
                        if (arr.getString(i) != senderId) filtered.put(arr.getString(i))
                    }
                    votesObj.put(key, filtered)
                }
            }

            // Secilen secenege oyu ekle (toggle — zaten varsa kaldir)
            val optKey = optionIndex.toString()
            val optArr = votesObj.optJSONArray(optKey) ?: JSONArray()
            val voters = (0 until optArr.length()).map { optArr.getString(it) }
            if (senderId in voters) {
                // Oy geri cek
                val filtered = JSONArray()
                voters.filter { it != senderId }.forEach { filtered.put(it) }
                votesObj.put(optKey, filtered)
            } else {
                optArr.put(senderId)
                votesObj.put(optKey, optArr)
            }

            json.put("votes", votesObj)
            val updatedContent = json.toString()

            // Lokal mesaji guncelle
            messageRepository.updateMessageContent(pollMessageId, updatedContent, MessageContentType.POLL.name)

            // Karsi tarafa oy bilgisini gonder
            val timestamp = System.currentTimeMillis()
            val voteEnvelope = "MSGID:${UUID.randomUUID()}:POLLVOTE:$pollMessageId:$optionIndex"

            val conversation = conversationDao.getById(conversationId)
            val isGroup = conversation?.isGroup == true

            if (isGroup) {
                val groupName = conversation?.peerName ?: ""
                val members = conversation?.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                val payloads = members.associateWith { "GROUP:$conversationId:$groupName:$voteEnvelope" }
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
                        envelope = voteEnvelope
                    )
                )
            }
        }
    }

    /**
     * Secilen dosyayi karsi tarafa gonderir.
     *
     * Islem sirasi:
     * 1. Dosya meta bilgileri (ad, boyut, tip) okunur
     * 2. Boyut kontrolu yapilir (maks 5MB)
     * 3. Yerel mesaj olarak kaydedilir (SENDING durumunda)
     * 4. FileTransferManager ile gonderilir
     * 5. Gonderim sonucuna gore mesaj durumu guncellenir
     *
     * @param uri Gonderilecek dosyanin content URI'si
     */
    fun sendFile(uri: Uri, caption: String? = null, isViewOnce: Boolean = false) {
        viewModelScope.launch(Dispatchers.IO) {
            // Esanli gonderim siniri — maks 3 dosya ayni anda (UI donmasini onler)
            fileUploadSemaphore.acquire()
            try {
                android.util.Log.d("ChatVM", "sendFile basladi: $uri caption=${caption?.take(20)} viewOnce=$isViewOnce")
                val senderId = userSession.userId ?: "unknown"
                val fileName = fileTransferManager.getFileName(uri) ?: "dosya"
                val fileSize = fileTransferManager.getFileSize(uri) ?: 0L
                val mimeType = fileTransferManager.getMimeType(uri)

                // Boyut kontrolu
                if (fileSize > FileTransferManager.MAX_FILE_SIZE) {
                    _fileTransferEvent.emit("Dosya boyutu cok buyuk (maksimum 1GB)")
                    fileUploadSemaphore.release()
                    return@launch
                }

                // Icerik tipini belirle — resim dosyalari IMAGE, digerleri FILE
                val contentType = if (mimeType.startsWith("image/")) {
                    MessageContentType.IMAGE
                } else {
                    MessageContentType.FILE
                }

                // Giden dosyayi da yerel kopyasini olustur - daha sonra acilabilmesi icin
                val localFilePath = fileTransferManager.copySentFile(uri, fileName) ?: uri.toString()

                val fileContent = LocalMessage.buildFileContent(
                    fileName = fileName,
                    mimeType = mimeType,
                    fileSize = fileSize,
                    filePath = localFilePath
                )

                // Sureli mesaj kontrolu — konusmada sureli mesaj aktifse expiresAt hesapla
                val fileTimestamp = System.currentTimeMillis()
                val fileDuration = conversationDao.getById(conversationId)?.disappearingDuration ?: 0
                val fileExpiresAt = if (fileDuration > 0) fileTimestamp + fileDuration else null

                // Onceden yerel mesaj kaydet (SENDING durumunda)
                val messageId = UUID.randomUUID().toString()
                val trimmedCaption = caption?.trim()?.takeIf { it.isNotBlank() }
                val message = LocalMessage(
                    id = messageId,
                    conversationId = conversationId,
                    senderId = senderId,
                    peerId = conversationId,
                    content = fileContent,
                    contentType = contentType,
                    timestamp = fileTimestamp,
                    status = MessageStatus.SENDING,
                    isOutgoing = true,
                    expiresAt = fileExpiresAt,
                    caption = trimmedCaption,
                    isViewOnce = isViewOnce
                )
                messageRepository.saveMessage(message)

                // Upload progress izleme — arka planda transferProgress'i dinle
                val progressJob = launch {
                    fileTransferManager.transferProgress.collect { progress ->
                        if (progress != null) {
                            _uploadProgress.value = _uploadProgress.value + (messageId to progress.percent)
                        }
                    }
                }

                // Grup bilgisini al
                val conversation = conversationDao.getById(conversationId)
                val isGroup = conversation?.isGroup == true
                val members = conversation?.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()

                // Dosya gonder — sureli mesaj icin mutlak expiresAt'i tasi (Asama 3)
                val result = fileTransferManager.sendFile(
                    localUserId = senderId,
                    recipientId = conversationId,
                    uri = uri,
                    isGroup = isGroup,
                    groupMembers = members,
                    groupName = if (isGroup) conversation?.peerName else null,
                    caption = trimmedCaption,
                    isViewOnce = isViewOnce,
                    originalMessageId = messageId,
                    absoluteExpiresAt = fileExpiresAt
                )

                // Progress izlemeyi durdur ve temizle
                progressJob.cancel()
                _uploadProgress.value = _uploadProgress.value - messageId

                android.util.Log.d("ChatVM", "sendFile sonucu: $result")
                when (result) {
                    is FileTransferResult.Success -> {
                        messageRepository.updateMessageStatus(messageId, MessageStatus.SENT)
                    }
                    is FileTransferResult.Error -> {
                        android.util.Log.e("ChatVM", "Dosya gonderim hatasi: ${result.message}")
                        messageRepository.updateMessageStatus(messageId, MessageStatus.FAILED)
                        _fileTransferEvent.emit(result.message)
                    }
                }
            } finally {
                fileUploadSemaphore.release()
            }
        }
    }

    /**
     * Mesaji sadece yerel cihazdan siler (benden sil).
     * Silme sonrasi konusma onizlemesini yeniden hesaplar.
     */
    fun deleteMessage(messageId: String) {
        viewModelScope.launch {
            messageRepository.deleteMessage(messageId, conversationId)
        }
    }

    /**
     * Mesaji herkesten siler — yerel olarak siler ve karsi tarafa silme bildirimi gonderir.
     * Baglanti yoksa silme islemini kuyruga alir, baglanti kuruldugunda gonderir.
     */
    fun deleteMessageForEveryone(messageId: String) {
        viewModelScope.launch {
            val userId = userSession.userId ?: return@launch
            val conv = conversationDao.getById(conversationId) ?: return@launch
            val isConnected = signalingClient.connectionState.value is ConnectionState.Connected

            if (isConnected) {
                sendDeleteSignals(userId, conv, messageId)
            } else {
                savePendingDelete(messageId, conv.peerId)
                android.util.Log.d("ChatViewModel", "Silme sinyali kuyruga alindi (cevrimdisi): $messageId")
            }

            // Yerel olarak da "silindi" olarak isaretle
            messageRepository.updateMessageContent(messageId, "Bu mesaj silindi", "DELETED")
            // Konusma onizlemesini guncelle
            messageRepository.recalculateLastMessage(conversationId)
        }
    }

    /** Silme sinyallerini karsi tarafa (veya grup uyelerine) gonderir. */
    private suspend fun sendDeleteSignals(
        userId: String,
        conv: com.securechat.storage.entity.ConversationEntity,
        messageId: String
    ) {
        if (conv.isGroup) {
            val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            for (memberId in members) {
                if (memberId == userId) continue
                signalingClient.sendSignal(
                    SignalMessage.MessageDelete(
                        senderId = userId,
                        recipientId = memberId,
                        timestamp = System.currentTimeMillis(),
                        messageId = messageId
                    )
                )
            }
        } else {
            signalingClient.sendSignal(
                SignalMessage.MessageDelete(
                    senderId = userId,
                    recipientId = conv.peerId,
                    timestamp = System.currentTimeMillis(),
                    messageId = messageId
                )
            )
        }
    }

    /** Cevrimdisi silme islemini SharedPreferences'a kaydeder. */
    private fun savePendingDelete(messageId: String, recipientId: String) {
        val jsonStr = sharedPreferences.getString(PREF_PENDING_DELETES, "[]") ?: "[]"
        val arr = JSONArray(jsonStr)
        arr.put(JSONObject().apply {
            put("messageId", messageId)
            put("recipientId", recipientId)
        })
        sharedPreferences.edit().putString(PREF_PENDING_DELETES, arr.toString()).apply()
    }

    /** Bekleyen silme islemlerini gonderir. Basarili olanlari kuyruktan cikarir. */
    private suspend fun flushPendingDeletes() {
        val userId = userSession.userId ?: return
        val jsonStr = sharedPreferences.getString(PREF_PENDING_DELETES, "[]") ?: "[]"
        val arr = JSONArray(jsonStr)
        if (arr.length() == 0) return

        val remaining = JSONArray()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i)
            val messageId = obj.getString("messageId")
            val recipientId = obj.getString("recipientId")
            val sent = signalingClient.sendSignal(
                SignalMessage.MessageDelete(
                    senderId = userId,
                    recipientId = recipientId,
                    timestamp = System.currentTimeMillis(),
                    messageId = messageId
                )
            )
            if (!sent) remaining.put(obj)
        }
        sharedPreferences.edit().putString(PREF_PENDING_DELETES, remaining.toString()).apply()
        android.util.Log.d("ChatViewModel", "Bekleyen silme: ${arr.length() - remaining.length()} gonderildi")
    }

    /**
     * Mesaji duzenler (15 dakika icinde gonderilmis olmali).
     * Yerel DB'de gunceller ve karsi tarafa sinyal gonderir.
     */
    fun editMessage(messageId: String, newContent: String) {
        viewModelScope.launch {
            val userId = userSession.userId ?: return@launch
            val msg = messageRepository.getMessageById(messageId) ?: return@launch

            // 15 dakika kontrolu
            val fifteenMinutes = 15 * 60 * 1000L
            if (System.currentTimeMillis() - msg.timestamp > fifteenMinutes) return@launch
            if (!msg.isOutgoing) return@launch

            val editedAt = System.currentTimeMillis()

            // Yerel DB guncelle
            messageRepository.editMessage(messageId, newContent, editedAt)

            // Karsi tarafa bildir
            val conv = conversationDao.getById(conversationId) ?: return@launch
            if (conv.isGroup) {
                val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                for (memberId in members) {
                    if (memberId == userId) continue
                    signalingClient.sendSignal(
                        SignalMessage.MessageEdit(
                            senderId = userId,
                            recipientId = memberId,
                            timestamp = editedAt,
                            messageId = messageId,
                            newContent = newContent
                        )
                    )
                }
            } else {
                signalingClient.sendSignal(
                    SignalMessage.MessageEdit(
                        senderId = userId,
                        recipientId = conv.peerId,
                        timestamp = editedAt,
                        messageId = messageId,
                        newContent = newContent
                    )
                )
            }
        }
    }

    /**
     * Mesajı yıldızlı olarak işaretler veya yıldızdan çıkarır.
     *
     * @param messageId Yıldızlama durumu değiştirilecek mesaj ID'si
     * @param isStarred Yıldızlı olup olmayacağı
     */
    fun toggleMessageStarred(messageId: String, isStarred: Boolean) {
        viewModelScope.launch {
            try {
                messageRepository.updateMessageStarred(messageId, isStarred)
                android.util.Log.d("ChatViewModel", "Mesaj yıldızlama güncellendi: $messageId -> $isStarred")
            } catch (e: Exception) {
                android.util.Log.e("ChatViewModel", "Mesaj yıldızlama hatası", e)
            }
        }
    }

    /**
     * Metin alani doluluk durumuna gore typing sinyali gonderir.
     * Sadece durum degistiginde sinyal gider — her tuslamada degil.
     */
    fun updateTypingState(hasText: Boolean) {
        if (hasText == isCurrentlyTyping) return
        isCurrentlyTyping = hasText
        val userId = userSession.userId ?: return
        viewModelScope.launch {
            val conv = conversationDao.getById(conversationId) ?: return@launch
            if (conv.isGroup) {
                // Grup: tum uyelere ayri ayri gonder
                val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                for (memberId in members) {
                    if (memberId == userId) continue
                    signalingClient.sendSignal(
                        SignalMessage.TypingIndicator(
                            senderId = userId, recipientId = memberId,
                            timestamp = System.currentTimeMillis(), isTyping = hasText
                        )
                    )
                }
            } else {
                signalingClient.sendSignal(
                    SignalMessage.TypingIndicator(
                        senderId = userId, recipientId = conv.peerId,
                        timestamp = System.currentTimeMillis(), isTyping = hasText
                    )
                )
            }
        }
    }

    /**
     * Sureli mesaj suresini ayarlar ve karsi tarafa bildirir.
     * @param duration Milisaniye cinsinden sure, 0 = kapali
     */
    fun toggleMuted() {
        viewModelScope.launch {
            val current = _conversationInfo.value?.isMuted ?: false
            val newMuted = !current
            messageRepository.updateConversationMuted(conversationId, newMuted)
            _conversationInfo.value = _conversationInfo.value?.copy(isMuted = newMuted)
        }
    }

    fun setDisappearingDuration(duration: Long) {
        viewModelScope.launch {
            _disappearingDuration.value = duration
            messageRepository.updateDisappearingDuration(conversationId, duration)

            // Karsi tarafa (veya grup uyelerine) bildir
            val userId = userSession.userId ?: return@launch
            val conv = conversationDao.getById(conversationId) ?: return@launch

            if (conv.isGroup) {
                // Grup: tum uyelere ayri ayri gonder
                val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                for (memberId in members) {
                    if (memberId == userId) continue
                    signalingClient.sendSignal(
                        SignalMessage.DisappearingTimer(
                            senderId = userId,
                            recipientId = memberId,
                            timestamp = System.currentTimeMillis(),
                            duration = duration,
                            conversationId = conversationId
                        )
                    )
                }
            } else {
                // Birebir: tek aliciya gonder
                signalingClient.sendSignal(
                    SignalMessage.DisappearingTimer(
                        senderId = userId,
                        recipientId = conv.peerId,
                        timestamp = System.currentTimeMillis(),
                        duration = duration,
                        conversationId = conversationId
                    )
                )
            }
        }
    }

    // --- Sohbet ici arama fonksiyonlari ---

    /**
     * Sohbet ici arama yapar. Mevcut mesajlari query ile filtreler.
     * Sonuclar ters kronolojik sirada (en yeniden en eskiye) doner.
     * Ilk sonuc otomatik olarak en yeni eslesen mesaja gider.
     */
    fun searchInChat(query: String) {
        _searchQuery.value = query
        if (query.isBlank()) {
            _searchResultIds.value = emptyList()
            _currentSearchIndex.value = -1
            _highlightedMessageId.value = null
            return
        }
        val lowerQuery = query.lowercase()
        // En yeniden en eskiye sirala — ilk sonuc en guncel eslesen mesaj
        val results = messages.value
            .filter {
                !it.isFileMessage && it.content.lowercase().contains(lowerQuery)
            }
            .sortedByDescending { it.timestamp }
            .map { it.id }
        _searchResultIds.value = results
        if (results.isNotEmpty()) {
            _currentSearchIndex.value = 0
            navigateToResult(results[0])
        } else {
            _currentSearchIndex.value = -1
            _highlightedMessageId.value = null
        }
    }

    /**
     * Asagi ok: bir sonraki arama sonucuna gider (daha eski mesaj).
     */
    fun nextSearchResult() {
        val results = _searchResultIds.value
        if (results.isEmpty()) return
        val nextIndex = (_currentSearchIndex.value + 1).coerceAtMost(results.size - 1)
        _currentSearchIndex.value = nextIndex
        navigateToResult(results[nextIndex])
    }

    /**
     * Yukari ok: bir onceki arama sonucuna gider (daha yeni mesaj).
     */
    fun prevSearchResult() {
        val results = _searchResultIds.value
        if (results.isEmpty()) return
        val prevIndex = (_currentSearchIndex.value - 1).coerceAtLeast(0)
        _currentSearchIndex.value = prevIndex
        navigateToResult(results[prevIndex])
    }

    private fun navigateToResult(messageId: String) {
        _highlightedMessageId.value = messageId
        viewModelScope.launch { _scrollToMessageId.emit(messageId) }
    }

    /**
     * Arama modunu temizler.
     */
    fun clearChatSearch() {
        _searchQuery.value = ""
        _searchResultIds.value = emptyList()
        _currentSearchIndex.value = -1
        _highlightedMessageId.value = null
    }

    /**
     * Mesaji baska bir konusmaya iletir.
     */
    fun forwardMessage(targetConversationId: String, content: String) {
        viewModelScope.launch {
            sendMessageUseCase(targetConversationId, content)
        }
    }

    /**
     * Tum konusmalari getirir — iletme hedef secimi icin.
     */
    fun getConversationsFlow() = messageRepository.getConversations()

    // --- Sohbet disa aktarma ---

    private val _exportText = MutableSharedFlow<String>()
    val exportText: SharedFlow<String> = _exportText.asSharedFlow()

    /**
     * Tum sohbet mesajlarini metin formatinda disa aktarir.
     * Sonuc exportText SharedFlow uzerinden yayilir.
     */
    fun exportConversation() {
        viewModelScope.launch(Dispatchers.IO) {
            val messages = messageRepository.getAllMessagesForConversation(conversationId)
            val info = _conversationInfo.value
            val peerName = info?.name ?: conversationId
            val memberNames = info?.memberNames ?: emptyMap()
            val dateFormat = java.text.SimpleDateFormat("dd.MM.yyyy HH:mm", java.util.Locale("tr"))

            val sb = StringBuilder()
            sb.appendLine("elçim — Sohbet Dışa Aktarımı")
            sb.appendLine("Sohbet: $peerName")
            sb.appendLine("Tarih: ${dateFormat.format(java.util.Date())}")
            sb.appendLine("Mesaj sayısı: ${messages.size}")
            sb.appendLine("─".repeat(40))
            sb.appendLine()

            messages.forEach { msg ->
                val time = dateFormat.format(java.util.Date(msg.timestamp))
                val sender = when {
                    msg.isOutgoing -> "Ben"
                    msg.senderId.isNotBlank() -> memberNames[msg.senderId] ?: msg.senderId
                    else -> peerName
                }
                val content = when {
                    msg.isSystemMessage -> "[${msg.content}]"
                    msg.isDeleted -> "[Silinen mesaj]"
                    msg.isFileMessage -> "[Dosya: ${msg.fileName ?: "dosya"}]"
                    msg.contentType == com.securechat.storage.model.MessageContentType.VOICE_NOTE -> "[Sesli mesaj]"
                    msg.contentType == com.securechat.storage.model.MessageContentType.POLL -> "[Anket]"
                    else -> msg.content
                }
                sb.appendLine("[$time] $sender: $content")
            }

            _exportText.emit(sb.toString())

            // Grup sohbetinde export olayini admin'lere E2EE log olarak gonder.
            // Server icerigi goremez; non-admin client'lar sessizce filtreler.
            // 1:1 sohbet veya admin'i olmayan gruplarda no-op.
            if (_isGroupChat.value && _isExportEnabled.value) {
                val firstTs = messages.minByOrNull { it.timestamp }?.timestamp
                val lastTs = messages.maxByOrNull { it.timestamp }?.timestamp
                runCatching {
                    recordExportEventUseCase(
                        groupId = conversationId,
                        eventType = "EXPORT",
                        messageCount = messages.size,
                        firstMsgTs = firstTs,
                        lastMsgTs = lastTs
                    )
                }.onFailure { e ->
                    android.util.Log.w("ChatViewModel", "Export log kaydi basarisiz", e)
                }
            }
        }
    }

    // --- Mesaj reaksiyonlari ---

    /**
     * Mesaja emoji reaksiyonu ekler veya kaldirir.
     * Ayni emoji zaten varsa kaldirir (toggle), yoksa ekler.
     * Karsi tarafa SignalMessage.MessageReaction gonderir.
     */
    fun toggleReaction(messageId: String, emoji: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val userId = userSession.userId ?: return@launch
            val message = messageRepository.getMessageById(messageId) ?: return@launch

            // Mevcut reaksiyonlari parse et
            val reactionsMap = parseReactions(message.reactions)
            val usersForEmoji = reactionsMap.getOrDefault(emoji, mutableListOf())
            val isRemoving = userId in usersForEmoji

            if (isRemoving) {
                usersForEmoji.remove(userId)
                if (usersForEmoji.isEmpty()) reactionsMap.remove(emoji)
            } else {
                usersForEmoji.add(userId)
                reactionsMap[emoji] = usersForEmoji
            }

            // JSON'a cevir ve kaydet
            val json = if (reactionsMap.isEmpty()) null else {
                val obj = org.json.JSONObject()
                reactionsMap.forEach { (e, users) ->
                    obj.put(e, org.json.JSONArray(users))
                }
                obj.toString()
            }
            messageRepository.updateMessageReactions(messageId, json)

            // Karsi tarafa gonder
            val conv = conversationDao.getById(conversationId) ?: return@launch
            if (conv.isGroup) {
                val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                for (memberId in members) {
                    if (memberId == userId) continue
                    signalingClient.sendSignal(
                        SignalMessage.MessageReaction(
                            senderId = userId,
                            recipientId = memberId,
                            timestamp = System.currentTimeMillis(),
                            messageId = messageId,
                            emoji = emoji,
                            remove = isRemoving,
                            groupId = conversationId
                        )
                    )
                }
            } else {
                signalingClient.sendSignal(
                    SignalMessage.MessageReaction(
                        senderId = userId,
                        recipientId = conv.peerId,
                        timestamp = System.currentTimeMillis(),
                        messageId = messageId,
                        emoji = emoji,
                        remove = isRemoving
                    )
                )
            }
        }
    }

    /**
     * Belirtilen mesaja scroll eder ve kisa sure highlight eder.
     * Reply bubble tiklandiginda kullanilir.
     */
    fun navigateToMessage(messageId: String) {
        _highlightedMessageId.value = messageId
        viewModelScope.launch {
            _scrollToMessageId.emit(messageId)
            // 2 saniye sonra highlight'i kaldir
            kotlinx.coroutines.delay(2000)
            if (_highlightedMessageId.value == messageId) {
                _highlightedMessageId.value = null
            }
        }
    }
}

/** Reaksiyon JSON stringini parse eder. */
fun parseReactions(json: String?): MutableMap<String, MutableList<String>> {
    if (json.isNullOrBlank()) return mutableMapOf()
    return try {
        val obj = org.json.JSONObject(json)
        val map = mutableMapOf<String, MutableList<String>>()
        obj.keys().forEach { emoji ->
            val arr = obj.getJSONArray(emoji)
            val users = mutableListOf<String>()
            for (i in 0 until arr.length()) users.add(arr.getString(i))
            map[emoji] = users
        }
        map
    } catch (_: Exception) {
        mutableMapOf()
    }
}

/**
 * Konusma bilgi modeli. Grup/birebir ayrimini ve uye bilgisini tasir.
 */
data class ConversationInfo(
    val name: String,
    val phoneNumber: String = "",
    val isGroup: Boolean,
    val memberCount: Int,
    val members: List<String>,
    /** Uye kimliklerinden goruntuleme adlarina esleme. Grup sohbetlerinde gonderen ismi gostermek icin kullanilir. */
    val memberNames: Map<String, String> = emptyMap(),
    val isMuted: Boolean = false
)
