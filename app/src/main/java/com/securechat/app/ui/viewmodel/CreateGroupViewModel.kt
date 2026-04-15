package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.app.data.UserSession
import com.securechat.contacts.ContactRepository
import com.securechat.contacts.model.DeviceContact
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
 * Grup oluşturma için kullanıcı seçim data modeli
 */
data class SelectableContact(
    val contact: DeviceContact,
    val hasElcimApp: Boolean = false, // Şimdilik false, ileride user discovery ile güncellenecek
    val isSelected: Boolean = false
)

/**
 * Grup olusturma ekrani ViewModel'i.
 * Grup adi, rehber tabanlı uye secimi ve olusturma islemini yonetir.
 */
@HiltViewModel
class CreateGroupViewModel @Inject constructor(
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val contactRepository: ContactRepository
) : ViewModel() {

    private val _groupName = MutableStateFlow("")
    val groupName: StateFlow<String> = _groupName.asStateFlow()

    private val _contacts = MutableStateFlow<List<SelectableContact>>(emptyList())
    val contacts: StateFlow<List<SelectableContact>> = _contacts.asStateFlow()

    private val _isLoadingContacts = MutableStateFlow(false)
    val isLoadingContacts: StateFlow<Boolean> = _isLoadingContacts.asStateFlow()

    private val _createdGroupId = MutableStateFlow<String?>(null)
    val createdGroupId: StateFlow<String?> = _createdGroupId.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    // Seçili üyelerin telefon numaraları
    val selectedMembers: StateFlow<List<String>> = _contacts.map { contacts ->
        contacts.filter { it.isSelected }.map { it.contact.phoneNumber }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), emptyList())

    init {
        // CreateGroup ekrandayken current chat'i "create_group" olarak set et
        IncomingMessageHandler.currentChatId = "create_group"
        android.util.Log.d("CreateGroupViewModel", "Current chat set to: create_group")

        // Rehberdeki kişileri yükle
        loadContacts()
    }

    /**
     * Rehberdeki tüm kişileri yükler ve SelectableContact listesine dönüştürür.
     */
    private fun loadContacts() {
        viewModelScope.launch {
            _isLoadingContacts.value = true
            try {
                val allContacts = contactRepository.getAllDeviceContacts()

                // Her contact için SelectableContact oluştur
                val selectableContacts = allContacts.map { contact ->
                    SelectableContact(
                        contact = contact,
                        hasElcimApp = false, // Şimdilik false, ileride user discovery eklenecek
                        isSelected = false
                    )
                }

                _contacts.value = selectableContacts
                android.util.Log.d("CreateGroupVM", "Rehberden ${selectableContacts.size} kişi yüklendi")
            } catch (e: Exception) {
                android.util.Log.e("CreateGroupVM", "Rehber yükleme hatası", e)
                _error.value = "Rehber yüklenirken hata oluştu: ${e.message}"
            } finally {
                _isLoadingContacts.value = false
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        // CreateGroup ekrani kapatildiginda current chat'i temizle
        IncomingMessageHandler.currentChatId = null
        android.util.Log.d("CreateGroupViewModel", "Current chat cleared from create_group")
    }

    fun onGroupNameChanged(name: String) {
        _groupName.value = name
    }

    /**
     * Belirtilen kişinin seçim durumunu değiştirir.
     */
    fun toggleContactSelection(phoneNumber: String) {
        _contacts.value = _contacts.value.map { selectableContact ->
            if (selectableContact.contact.phoneNumber == phoneNumber) {
                selectableContact.copy(isSelected = !selectableContact.isSelected)
            } else {
                selectableContact
            }
        }

        val selectedCount = _contacts.value.count { it.isSelected }
        android.util.Log.d("CreateGroupVM", "Contact selection toggled: $phoneNumber, selected: $selectedCount")
    }

    /**
     * Tüm seçimleri temizler.
     */
    fun clearAllSelections() {
        _contacts.value = _contacts.value.map { it.copy(isSelected = false) }
    }

    /**
     * Yeni grup konusmasini olusturur ve veritabanina kaydeder.
     * Basarili olursa createdGroupId guncellenir ve navigate edilir.
     */
    fun createGroup() {
        val name = _groupName.value.trim()
        val memberList = selectedMembers.value

        if (name.isBlank()) {
            _error.value = "Grup adi bos olamaz"
            return
        }
        if (memberList.size < 1) {
            _error.value = "En az 1 kişi seçmelisiniz (siz otomatik dahil edileceksiniz)"
            return
        }

        viewModelScope.launch {
            val currentUserId = userSession.userId ?: "unknown"

            // CRITICAL FIX: Creator'ı her zaman en başa ekle (admin olarak)
            // Diğer üyelerin listesine de creator'ı ekle ama duplicate kontrolü yap
            val otherMembers = memberList.filter { it != currentUserId }
            val allMembers = listOf(currentUserId) + otherMembers

            val groupId = "group_${UUID.randomUUID()}"
            val timestamp = System.currentTimeMillis()

            // Yerel veritabanına grup oluştur - creator mutlaka dahil
            conversationDao.insert(
                ConversationEntity(
                    id = groupId,
                    peerId = groupId,
                    peerName = name,
                    peerPhone = "",
                    lastMessage = "$currentUserId grubu oluşturdu",
                    lastMessageTimestamp = timestamp,
                    unreadCount = 0,
                    isMuted = false,
                    isPinned = false,
                    isGroup = true,
                    groupMembers = allMembers.joinToString(","),
                    groupAdmins = currentUserId // Grup kurucusu ilk admin
                )
            )

            android.util.Log.d("CreateGroupVM", "Grup yerel olarak oluşturuldu: $groupId, üyeler: $allMembers")

            // PHASE 2 FIX: Tüm grup üyelerine grup oluşturma bildirimi gönder
            val groupNotification = SignalMessage.GroupNotification(
                senderId = currentUserId,
                recipientId = "", // Her üye için ayrı ayrı gönderilecek
                timestamp = timestamp,
                groupId = groupId,
                groupName = name,
                action = GroupAction.CREATE,
                groupMembers = allMembers
            )

            // Sadece diğer üyelere bildirim gönder (kendisine göndermeye gerek yok)
            // Çünkü yerel veritabanında zaten oluşturduk
            for (memberId in otherMembers) {
                signalingClient.sendSignal(
                    groupNotification.copy(recipientId = memberId)
                )
            }
            android.util.Log.d("CreateGroupVM", "Grup oluşturma bildirimi gönderildi: $groupId, üyeler: $otherMembers")

            _createdGroupId.value = groupId
        }
    }

    fun clearError() {
        _error.value = null
    }
}
