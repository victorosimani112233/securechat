package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.entity.MessageEntity
import com.securechat.storage.resolver.ContactNameResolver
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Sohbet bilgileri ekranı için ViewModel.
 * Kişi bilgileri, medya, doküman, yıldızlı mesajlar, arama, not ve bildirim yönetimi sağlar.
 */
@HiltViewModel
class ChatInfoViewModel @Inject constructor(
    private val messageDao: MessageDao,
    private val conversationDao: ConversationDao,
    private val contactDao: ContactDao,
    private val contactNameResolver: ContactNameResolver,
    private val signalingClient: SignalingClient,
    private val userSession: UserSession
) : ViewModel() {

    private var currentConversationId: String? = null

    private val _conversationName = MutableStateFlow("")
    val conversationName: StateFlow<String> = _conversationName.asStateFlow()

    private val _phoneNumber = MutableStateFlow("")
    val phoneNumber: StateFlow<String> = _phoneNumber.asStateFlow()

    private val _contactNote = MutableStateFlow<String?>(null)
    val contactNote: StateFlow<String?> = _contactNote.asStateFlow()

    private val _customNotificationUri = MutableStateFlow<String?>(null)
    val customNotificationUri: StateFlow<String?> = _customNotificationUri.asStateFlow()

    private val _isGroup = MutableStateFlow(false)
    val isGroup: StateFlow<Boolean> = _isGroup.asStateFlow()

    private val _mediaMessages = MutableStateFlow<List<MessageEntity>>(emptyList())
    val mediaMessages: StateFlow<List<MessageEntity>> = _mediaMessages.asStateFlow()

    private val _documentMessages = MutableStateFlow<List<MessageEntity>>(emptyList())
    val documentMessages: StateFlow<List<MessageEntity>> = _documentMessages.asStateFlow()

    private val _starredMessages = MutableStateFlow<List<MessageEntity>>(emptyList())
    val starredMessages: StateFlow<List<MessageEntity>> = _starredMessages.asStateFlow()

    private val _searchResults = MutableStateFlow<List<MessageEntity>>(emptyList())
    val searchResults: StateFlow<List<MessageEntity>> = _searchResults.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    /** Sureli mesaj suresi (ms). 0 = kapali. */
    private val _disappearingDuration = MutableStateFlow(0L)
    val disappearingDuration: StateFlow<Long> = _disappearingDuration.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    private val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    init {
        setupSearch()
    }

    /**
     * ChatInfo ekranını initialize eder ve verileri yükler.
     */
    fun initialize(conversationId: String) {
        if (currentConversationId == conversationId) return

        currentConversationId = conversationId
        _isLoading.value = true

        // Conversation bilgisini yükle
        viewModelScope.launch {
            try {
                val conversation = conversationDao.getById(conversationId)
                if (conversation != null) {
                    // Isim hala UUID gibi gorunuyorsa cozumle
                    var displayName = conversation.peerName
                    if (displayName == conversation.peerId || displayName.isBlank()) {
                        try {
                            val resolved = contactNameResolver.resolveDisplayName(conversation.peerId)
                            if (resolved != conversation.peerId) {
                                displayName = resolved
                                conversationDao.updatePeerName(conversationId, resolved)
                            }
                        } catch (_: Exception) { }
                    }

                    _conversationName.value = displayName
                    // peerPhone bozuk olabilir: UUID veya isim kaydedilmis olabilir
                    var phoneNumber = conversation.peerPhone
                    val isBroken = phoneNumber == conversation.peerId // UUID atanmis
                        || (phoneNumber == conversation.peerName && !phoneNumber.startsWith("+")) // isim atanmis
                        || phoneNumber.isBlank()
                    if (isBroken) {
                        phoneNumber = ""
                        // Contacts DB'den gercek numarayi coz
                        try {
                            val contact = contactDao.getById(conversation.peerId)
                            if (contact != null && contact.phoneNumber.isNotBlank()) {
                                phoneNumber = contact.phoneNumber
                                conversationDao.update(conversation.copy(peerPhone = phoneNumber))
                            }
                        } catch (_: Exception) { }
                        // Hala bossa ve isim numara formatindaysa onu goster
                        if (phoneNumber.isBlank() && displayName.startsWith("+")) {
                            phoneNumber = displayName
                        }
                    }
                    _phoneNumber.value = phoneNumber
                    _contactNote.value = conversation.contactNote
                    _customNotificationUri.value = conversation.customNotificationUri
                    _isGroup.value = conversation.isGroup
                    _disappearingDuration.value = conversation.disappearingDuration
                } else {
                    _conversationName.value = conversationId
                    _phoneNumber.value = conversationId
                }
            } catch (e: Exception) {
                _conversationName.value = conversationId
                android.util.Log.e("ChatInfoVM", "Conversation bilgisi yüklenemedi", e)
            }
        }

        // Medya mesajlarını yükle
        messageDao.getMediaMessages(conversationId)
            .onEach { messages -> _mediaMessages.value = messages }
            .launchIn(viewModelScope)

        // Doküman mesajlarını yükle
        messageDao.getDocumentMessages(conversationId)
            .onEach { messages -> _documentMessages.value = messages }
            .launchIn(viewModelScope)

        // Yıldızlı mesajları yükle
        messageDao.getStarredMessages(conversationId)
            .onEach { messages ->
                _starredMessages.value = messages
                _isLoading.value = false
            }
            .launchIn(viewModelScope)
    }

    /**
     * Mesajlarda arama yapar.
     */
    fun searchMessages(query: String) {
        _searchQuery.value = query.trim()
    }

    /**
     * Arama sonuçlarını temizler.
     */
    fun clearSearch() {
        _searchQuery.value = ""
        _searchResults.value = emptyList()
    }

    /**
     * Mesajı yıldızlı olarak işaretler veya yıldızdan çıkarır.
     */
    fun toggleMessageStarred(messageId: String, isStarred: Boolean) {
        viewModelScope.launch {
            try {
                messageDao.updateStarred(messageId, isStarred)
            } catch (e: Exception) {
                android.util.Log.e("ChatInfoVM", "Mesaj yıldızlama hatası", e)
            }
        }
    }

    /**
     * Kişiye not ekler veya günceller.
     */
    fun updateContactNote(note: String?) {
        val conversationId = currentConversationId ?: return
        viewModelScope.launch {
            try {
                val trimmed = note?.trim()?.ifBlank { null }
                conversationDao.updateContactNote(conversationId, trimmed)
                _contactNote.value = trimmed
            } catch (e: Exception) {
                android.util.Log.e("ChatInfoVM", "Not güncelleme hatası", e)
            }
        }
    }

    /**
     * Kişiye özel bildirim sesi ayarlar.
     */
    fun updateCustomNotification(uri: String?) {
        val conversationId = currentConversationId ?: return
        viewModelScope.launch {
            try {
                conversationDao.updateCustomNotification(conversationId, uri)
                _customNotificationUri.value = uri
            } catch (e: Exception) {
                android.util.Log.e("ChatInfoVM", "Bildirim güncelleme hatası", e)
            }
        }
    }

    /**
     * Sureli mesaj suresini ayarlar.
     * @param duration Milisaniye cinsinden sure, 0 = kapali
     */
    fun setDisappearingDuration(duration: Long) {
        val conversationId = currentConversationId ?: return
        viewModelScope.launch {
            try {
                conversationDao.updateDisappearingDuration(conversationId, duration)
                _disappearingDuration.value = duration

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
            } catch (e: Exception) {
                android.util.Log.e("ChatInfoVM", "Sureli mesaj guncelleme hatasi", e)
            }
        }
    }

    /**
     * Arama fonksiyonalitesi için debounced flow kurulumu.
     */
    @OptIn(FlowPreview::class)
    private fun setupSearch() {
        searchQuery
            .debounce(300)
            .distinctUntilChanged()
            .onEach { query ->
                val conversationId = currentConversationId
                if (conversationId != null && query.isNotBlank()) {
                    _isLoading.value = true
                    try {
                        val searchPattern = "%$query%"
                        messageDao.searchMessages(conversationId, searchPattern)
                            .onEach { results ->
                                _searchResults.value = results
                                _isLoading.value = false
                            }
                            .launchIn(viewModelScope)
                    } catch (e: Exception) {
                        android.util.Log.e("ChatInfoVM", "Arama hatası", e)
                        _isLoading.value = false
                    }
                } else {
                    _searchResults.value = emptyList()
                    _isLoading.value = false
                }
            }
            .launchIn(viewModelScope)
    }
}
