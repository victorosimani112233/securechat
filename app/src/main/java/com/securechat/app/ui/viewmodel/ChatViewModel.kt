package com.securechat.app.ui.viewmodel

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
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import com.securechat.storage.resolver.ContactNameResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
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
    private val contactNameResolver: ContactNameResolver
) : ViewModel() {

    /** Navigation argument'inden alinan konusma kimlik numarasi. */
    val conversationId: String = savedStateHandle.get<String>("conversationId") ?: ""

    /** Konusmadaki mesajlarin reaktif listesi. */
    val messages: StateFlow<List<LocalMessage>> = observeMessagesUseCase(conversationId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Konusma bilgisi — grup mu, ismi, uye sayisi vb. */
    private val _conversationInfo = MutableStateFlow<ConversationInfo?>(null)
    val conversationInfo: StateFlow<ConversationInfo?> = _conversationInfo.asStateFlow()

    /** Dosya gonderim durumu — hata mesajlari icin. */
    private val _fileTransferEvent = MutableSharedFlow<String>()
    val fileTransferEvent: SharedFlow<String> = _fileTransferEvent.asSharedFlow()

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

    private var isCurrentlyTyping = false

    /** Scroll hedefi — belirli bir mesaja scroll tetikler. */
    private val _scrollToMessageId = MutableSharedFlow<String>()
    val scrollToMessageId: SharedFlow<String> = _scrollToMessageId.asSharedFlow()

    init {
        // Ekran acildiginda konusmayi okundu olarak isaretle ve bilgilerini yukle
        viewModelScope.launch {
            markAsReadUseCase(conversationId)
            loadConversationInfo()
            sendReadReceipts()
            // Sureli mesaj ayarini yukle
            val conv = conversationDao.getById(conversationId)
            _disappearingDuration.value = conv?.disappearingDuration ?: 0
        }

        // Current chat tracking: Bu sohbet acildiginda bildirim sistemine bildir
        IncomingMessageHandler.currentChatId = conversationId
        android.util.Log.d("ChatViewModel", "Current chat set to: $conversationId")
    }

    override fun onCleared() {
        super.onCleared()
        // Chat screen kapatildiginda current chat'i temizle
        IncomingMessageHandler.currentChatId = null
        android.util.Log.d("ChatViewModel", "Current chat cleared")
    }

    /**
     * Sohbet ekrani acildiginda, gelen (okunmamis) mesajlar icin READ receipt gonderir.
     * Karsi taraf mesajin okundugunu gorur (mavi cift tik).
     */
    private suspend fun sendReadReceipts() {
        val localUserId = userSession.userId ?: return
        // Mevcut mesajlari bir kez oku ve gelen mesajlar icin READ receipt gonder
        val currentMessages = messages.value
        val incomingMessages = currentMessages.filter { !it.isOutgoing }
        for (msg in incomingMessages) {
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

    private suspend fun loadConversationInfo() {
        val entity = conversationDao.getById(conversationId)
        if (entity != null) {
            val members = entity.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            // Grup uyelerinin goruntuleme adlarini mevcut konusmalardan coz
            val memberNames = mutableMapOf<String, String>()
            for (memberId in members) {
                val memberConv = conversationDao.getByPeerId(memberId)
                if (memberConv != null && memberConv.peerName.isNotBlank() && memberConv.peerName != memberId) {
                    memberNames[memberId] = memberConv.peerName
                }
            }

            // Eger isim hala telefon numarasi gibi gorunuyorsa, rehberden cozumlemeyi dene
            var displayName = entity.peerName
            if (displayName == entity.peerId || displayName == entity.peerPhone || displayName.startsWith("+")) {
                try {
                    val resolved = contactNameResolver.resolveDisplayName(entity.peerId)
                    if (resolved != displayName && !resolved.startsWith("+")) {
                        displayName = resolved
                        conversationDao.updatePeerName(conversationId, resolved)
                    }
                } catch (_: Exception) { }
            }

            _conversationInfo.value = ConversationInfo(
                name = displayName,
                phoneNumber = entity.peerPhone,
                isGroup = entity.isGroup,
                memberCount = members.size,
                members = members,
                memberNames = memberNames
            )
        }
    }

    /**
     * Yeni bir metin mesaji gonderir.
     *
     * @param content Mesaj icerigi
     */
    fun sendMessage(content: String) {
        viewModelScope.launch {
            sendMessageUseCase(conversationId, content)
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
    fun sendFile(uri: Uri) {
        viewModelScope.launch {
            android.util.Log.d("ChatVM", "sendFile basladi: $uri")
            val senderId = userSession.userId ?: "unknown"
            val fileName = fileTransferManager.getFileName(uri) ?: "dosya"
            val fileSize = fileTransferManager.getFileSize(uri) ?: 0L
            val mimeType = fileTransferManager.getMimeType(uri)

            // Boyut kontrolu
            if (fileSize > FileTransferManager.MAX_FILE_SIZE) {
                _fileTransferEvent.emit("Dosya boyutu cok buyuk (maksimum 5MB)")
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
                expiresAt = fileExpiresAt
            )
            messageRepository.saveMessage(message)

            // Grup bilgisini al
            val conversation = conversationDao.getById(conversationId)
            val isGroup = conversation?.isGroup == true
            val members = conversation?.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()

            // Dosya gonder
            val result = fileTransferManager.sendFile(
                localUserId = senderId,
                recipientId = conversationId,
                uri = uri,
                isGroup = isGroup,
                groupMembers = members
            )

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
        }
    }

    /**
     * Belirtilen mesaji siler.
     *
     * @param messageId Silinecek mesajin kimlik numarasi
     */
    /**
     * Mesaji sadece yerel cihazdan siler (benden sil).
     */
    fun deleteMessage(messageId: String) {
        viewModelScope.launch {
            messageRepository.deleteMessage(messageId)
        }
    }

    /**
     * Mesaji herkesten siler — yerel olarak siler ve karsi tarafa silme bildirimi gonderir.
     */
    fun deleteMessageForEveryone(messageId: String) {
        viewModelScope.launch {
            // Karsi tarafa silme bildirimi gonder
            val userId = userSession.userId ?: return@launch
            val peerId = conversationDao.getById(conversationId)?.peerId ?: return@launch
            val deleteSignal = SignalMessage.MessageDelete(
                senderId = userId,
                recipientId = peerId,
                timestamp = System.currentTimeMillis(),
                messageId = messageId
            )
            signalingClient.sendSignal(deleteSignal)
            // Yerel olarak da "silindi" olarak isaretle (tamamen silme yerine)
            messageRepository.updateMessageContent(messageId, "Bu mesaj silindi", "DELETED")
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
            val peerId = conversationDao.getById(conversationId)?.peerId ?: return@launch
            signalingClient.sendSignal(
                SignalMessage.TypingIndicator(
                    senderId = userId, recipientId = peerId,
                    timestamp = System.currentTimeMillis(), isTyping = hasText
                )
            )
        }
    }

    /**
     * Sureli mesaj suresini ayarlar ve karsi tarafa bildirir.
     * @param duration Milisaniye cinsinden sure, 0 = kapali
     */
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
    val memberNames: Map<String, String> = emptyMap()
)
