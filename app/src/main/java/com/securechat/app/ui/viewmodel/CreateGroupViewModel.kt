package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.contacts.ContactSearchManager
import com.securechat.contacts.DiscoveryApiService
import com.securechat.contacts.PhoneNumberNormalizer
import com.securechat.contacts.UserDiscoveryService
import com.securechat.contacts.model.CheckUsersRequest
import com.securechat.contacts.model.RegisteredContact
import com.securechat.network.SignalingClient
import com.securechat.network.SignalMessage
import com.securechat.network.model.GroupAction
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.entity.ConversationEntity
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

/**
 * Grup oluşturma için kullanıcı seçim data modeli.
 * Sadece kayitli (SecureChat kullanan) kisileri gosterir.
 */
data class SelectableContact(
    val userId: String,
    val displayName: String,
    val phoneNumber: String,
    val avatarUri: String? = null,
    val isSelected: Boolean = false
)

/**
 * Grup olusturma ekrani ViewModel'i.
 * Grup adi, kayitli kisi secimi ve olusturma islemini yonetir.
 * Sadece SecureChat'e kayitli kisiler gosterilir — grup mesajlari
 * userId (UUID) uzerinden yonlendirilir.
 */
@HiltViewModel
class CreateGroupViewModel @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val contactSearchManager: ContactSearchManager,
    private val userDiscoveryService: UserDiscoveryService,
    private val discoveryApiService: DiscoveryApiService
) : ViewModel() {

    private val _groupName = MutableStateFlow("")
    val groupName: StateFlow<String> = _groupName.asStateFlow()

    private val _contacts = MutableStateFlow<List<SelectableContact>>(emptyList())

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    /** Arama sorgusuna gore filtrelenmis kisi listesi */
    val contacts: StateFlow<List<SelectableContact>> = kotlinx.coroutines.flow.combine(
        _contacts, _searchQuery
    ) { allContacts, query ->
        if (query.isBlank()) allContacts
        else {
            val lower = query.lowercase()
            allContacts.filter {
                it.displayName.lowercase().contains(lower) ||
                it.phoneNumber.contains(query)
            }
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), emptyList())

    private val _isLoadingContacts = MutableStateFlow(false)
    val isLoadingContacts: StateFlow<Boolean> = _isLoadingContacts.asStateFlow()

    private val _createdGroupId = MutableStateFlow<String?>(null)
    val createdGroupId: StateFlow<String?> = _createdGroupId.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _phoneInput = MutableStateFlow("")
    val phoneInput: StateFlow<String> = _phoneInput.asStateFlow()

    private val _isResolvingPhone = MutableStateFlow(false)
    val isResolvingPhone: StateFlow<Boolean> = _isResolvingPhone.asStateFlow()

    private val _phoneNotFound = MutableStateFlow<String?>(null)
    val phoneNotFound: StateFlow<String?> = _phoneNotFound.asStateFlow()

    // Secili uyelerin userId'leri (UUID)
    val selectedMembers: StateFlow<List<String>> = _contacts.map { contacts ->
        contacts.filter { it.isSelected }.map { it.userId }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), emptyList())

    init {
        IncomingMessageHandler.currentChatId = "create_group"
        discoverAndLoadContacts()
    }

    /**
     * Once sunucudan kayitli kisileri kesfeder, sonra DB'den yukler.
     * Discovery basarisiz olsa bile DB'deki mevcut kisiler gosterilir.
     */
    private fun discoverAndLoadContacts() {
        viewModelScope.launch {
            _isLoadingContacts.value = true
            // Sunucudan kisi kesfini calistir — DB'yi gunceller
            try {
                userDiscoveryService.discoverRegisteredUsers()
                android.util.Log.d("CreateGroupVM", "Kisi kesfi tamamlandi")
            } catch (e: Exception) {
                android.util.Log.e("CreateGroupVM", "Kisi kesfi hatasi (devam ediliyor): ${e.message}")
            }
            // DB'deki kayitli kisileri reactive olarak dinle
            loadContacts()
        }
    }

    /**
     * Kayitli (SecureChat kullanan) kisileri DB'den yukler.
     * Sadece userId'si bilinen kisiler grup uyesi olabilir.
     */
    private fun loadContacts() {
        viewModelScope.launch {
            try {
                contactSearchManager.getRegisteredContacts().collect { registered ->
                    val selectableContacts = registered.map { contact ->
                        SelectableContact(
                            userId = contact.userId,
                            displayName = contact.displayName,
                            phoneNumber = contact.phoneNumber,
                            avatarUri = contact.avatarUri,
                            isSelected = _contacts.value.find { it.userId == contact.userId }?.isSelected ?: false
                        )
                    }
                    _contacts.value = selectableContacts
                    _isLoadingContacts.value = false
                }
            } catch (e: Exception) {
                android.util.Log.e("CreateGroupVM", "Kisi yukleme hatasi", e)
                _error.value = "Kişiler yüklenirken hata oluştu: ${e.message}"
                _isLoadingContacts.value = false
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        IncomingMessageHandler.currentChatId = null
    }

    fun onGroupNameChanged(name: String) {
        _groupName.value = name
    }

    fun onSearchQueryChanged(query: String) {
        _searchQuery.value = query
    }

    /**
     * Belirtilen kisinin secim durumunu degistirir.
     */
    fun toggleContactSelection(userId: String) {
        _contacts.value = _contacts.value.map { selectableContact ->
            if (selectableContact.userId == userId) {
                selectableContact.copy(isSelected = !selectableContact.isSelected)
            } else {
                selectableContact
            }
        }
    }

    /**
     * Tum secimleri temizler.
     */
    fun clearAllSelections() {
        _contacts.value = _contacts.value.map { it.copy(isSelected = false) }
    }

    /**
     * Yeni grup konusmasini olusturur ve veritabanina kaydeder.
     * Grup uyeleri userId (UUID) ile tanimlanir — telefon numarasi KULLANILMAZ.
     */
    fun createGroup() {
        val name = _groupName.value.trim()
        val memberUserIds = selectedMembers.value

        if (name.isBlank()) {
            _error.value = "Grup adı boş olamaz"
            return
        }
        if (memberUserIds.isEmpty()) {
            _error.value = "En az 1 kişi seçmelisiniz"
            return
        }

        viewModelScope.launch {
            val currentUserId = userSession.userId ?: "unknown"

            val otherMembers = memberUserIds.filter { it != currentUserId }
            val allMembers = listOf(currentUserId) + otherMembers

            val groupId = "group_${UUID.randomUUID()}"
            val timestamp = System.currentTimeMillis()

            // Yerel veritabanina grubu kaydet
            conversationDao.insert(
                ConversationEntity(
                    id = groupId,
                    peerId = groupId,
                    peerName = name,
                    peerPhone = "",
                    lastMessage = "Grup oluşturuldu",
                    lastMessageTimestamp = timestamp,
                    unreadCount = 0,
                    isMuted = false,
                    isPinned = false,
                    isGroup = true,
                    groupMembers = allMembers.joinToString(","),
                    groupAdmins = currentUserId
                )
            )

            android.util.Log.d("CreateGroupVM", "Grup olusturuldu: $groupId, uyeler(UUID): $allMembers, otherMembers: $otherMembers")

            // Diger uyelere grup olusturma bildirimi gonder
            for (memberId in otherMembers) {
                val notification = SignalMessage.GroupNotification(
                    senderId = currentUserId,
                    recipientId = memberId,
                    timestamp = timestamp,
                    groupId = groupId,
                    groupName = name,
                    action = GroupAction.CREATE,
                    groupMembers = allMembers
                )
                val sent = signalingClient.sendSignal(notification)
                android.util.Log.d("CreateGroupVM", "Grup bildirimi recipientId=$memberId (type=${memberId.take(8)}): sent=$sent")
            }

            _createdGroupId.value = groupId
        }
    }

    fun clearError() {
        _error.value = null
    }

    fun onPhoneInputChanged(phone: String) {
        _phoneInput.value = phone
    }

    fun consumePhoneNotFound() {
        _phoneNotFound.value = null
    }

    /**
     * Telefon numarasindan kullanici UUID'si cozumler ve secili uyelere ekler.
     */
    fun addMemberByPhone() {
        val phone = _phoneInput.value.trim()
        if (phone.isBlank()) return

        viewModelScope.launch {
            _isResolvingPhone.value = true
            try {
                val digits = PhoneNumberNormalizer.normalizeDigits(phone)
                val hash = UserDiscoveryService.hashPhoneNumber(digits)
                val response = discoveryApiService.checkRegisteredUsers(
                    CheckUsersRequest(hashes = listOf(hash))
                )
                val match = response.users.firstOrNull()
                if (match != null) {
                    val userId = match.userId
                    // Zaten secili mi kontrol et
                    val alreadySelected = _contacts.value.any { it.userId == userId && it.isSelected }
                    if (alreadySelected) {
                        _error.value = "Bu kişi zaten ekli"
                    } else {
                        // Mevcut listede varsa sec, yoksa yeni ekle
                        val existsInList = _contacts.value.any { it.userId == userId }
                        if (existsInList) {
                            _contacts.value = _contacts.value.map {
                                if (it.userId == userId) it.copy(isSelected = true) else it
                            }
                        } else {
                            _contacts.value = _contacts.value + SelectableContact(
                                userId = userId,
                                displayName = digits,
                                phoneNumber = digits,
                                isSelected = true
                            )
                        }
                        _phoneInput.value = ""
                    }
                } else {
                    _phoneNotFound.value = phone
                }
            } catch (e: Exception) {
                android.util.Log.e("CreateGroupVM", "Telefon cozumleme hatasi", e)
                _phoneNotFound.value = phone
            } finally {
                _isResolvingPhone.value = false
            }
        }
    }
}
