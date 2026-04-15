package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.IncomingMessageHandler
import com.securechat.contacts.ContactPermissionManager
import com.securechat.contacts.ContactSearchManager
import com.securechat.contacts.ContactsProvider
import com.securechat.contacts.UserDiscoveryService
import com.securechat.contacts.model.DeviceContact
import com.securechat.contacts.model.RegisteredContact
import com.securechat.storage.domain.Conversation
import com.securechat.storage.repository.MessageRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Kisi listesi ekrani ViewModel'i.
 * Kayitli kisileri, telefon rehberi kisilerini, arama islemini, izin durumunu
 * ve kullanici kesfini yonetir.
 * Manuel kullanici ID girisi ile izin olmadan da sohbet baslatabildigi icin
 * graceful degrade saglanir.
 */
@HiltViewModel
class ContactsViewModel @Inject constructor(
    private val contactSearchManager: ContactSearchManager,
    private val contactPermissionManager: ContactPermissionManager,
    private val userDiscoveryService: UserDiscoveryService,
    private val contactsProvider: ContactsProvider,
    private val messageRepository: MessageRepository
) : ViewModel() {

    private val _searchQuery = MutableStateFlow("")
    /** Mevcut arama sorgusu. */
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _permissionGranted = MutableStateFlow(contactPermissionManager.hasPermission())
    /** Rehber erisim izninin verilip verilmedigi. */
    val permissionGranted: StateFlow<Boolean> = _permissionGranted.asStateFlow()

    private val _isDiscovering = MutableStateFlow(false)
    /** Kullanici kesfi isleminin devam edip etmedigi. */
    val isDiscovering: StateFlow<Boolean> = _isDiscovering.asStateFlow()

    private val _manualUserId = MutableStateFlow("")
    /** Manuel olarak girilen kullanici ID'si. */
    val manualUserId: StateFlow<String> = _manualUserId.asStateFlow()

    private val _phoneContacts = MutableStateFlow<List<DeviceContact>>(emptyList())
    /** Cihaz rehberinden okunan telefon kisileri. Izin verildikten sonra yuklenir. */
    val phoneContacts: StateFlow<List<DeviceContact>> = _phoneContacts.asStateFlow()

    init {
        // Contacts ekrandayken current chat'i "contacts" olarak set et
        IncomingMessageHandler.currentChatId = "contacts"
        android.util.Log.d("ContactsViewModel", "Current chat set to: contacts")

        // Izin zaten verilmisse rehberi hemen yukle
        if (contactPermissionManager.hasPermission()) {
            loadPhoneContacts()
        }
    }

    override fun onCleared() {
        super.onCleared()
        // Contacts ekrani kapatildiginda current chat'i temizle
        IncomingMessageHandler.currentChatId = null
        android.util.Log.d("ContactsViewModel", "Current chat cleared from contacts")
    }

    /** Arama sorgusuna gore filtrelenmis kisi listesi. */
    @OptIn(ExperimentalCoroutinesApi::class)
    val contacts: StateFlow<List<RegisteredContact>> = _searchQuery
        .flatMapLatest { query ->
            if (query.isBlank()) {
                contactSearchManager.getRegisteredContacts()
            } else {
                contactSearchManager.searchContacts(query)
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Veritabanindaki mevcut konusmalari hizli erisim icin listeler. */
    val recentConversations: StateFlow<List<Conversation>> = messageRepository
        .getConversations()
        .map { conversations ->
            conversations.sortedByDescending { it.lastMessageTimestamp }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /**
     * Arama sorgusunu gunceller.
     *
     * @param query Yeni arama metni
     */
    fun onSearchQueryChanged(query: String) {
        _searchQuery.value = query
    }

    /**
     * Manuel kullanici ID'si alanini gunceller.
     *
     * @param userId Yeni kullanici ID'si
     */
    fun onManualUserIdChanged(userId: String) {
        _manualUserId.value = userId
    }

    /**
     * READ_CONTACTS izninin mevcut olup olmadigini kontrol eder.
     */
    fun hasPermission(): Boolean = contactPermissionManager.hasPermission()

    /**
     * Izin verildikten sonra cagrilir.
     * Izin durumunu gunceller ve kullanici kesfini baslatir.
     */
    fun onPermissionGranted() {
        _permissionGranted.value = true
        loadPhoneContacts()
        discoverUsers()
    }

    /**
     * Izin reddedildikten sonra cagrilir.
     * Izin durumunu gunceller.
     */
    fun onPermissionDenied() {
        _permissionGranted.value = false
    }

    /**
     * Cihaz rehberinden SecureChat kullanan kisileri kesfeder.
     * Hash tabanli eslesme kullanir, plaintext numara sunucuya GONDERILMEZ.
     */
    fun discoverUsers() {
        viewModelScope.launch {
            _isDiscovering.value = true
            try {
                userDiscoveryService.discoverRegisteredUsers()
            } catch (_: Exception) {
                // Kesif basarisiz olsa bile ekran calismaya devam eder.
                // Veritabanindaki mevcut kisiler gosterilir.
            } finally {
                _isDiscovering.value = false
            }
        }
    }

    /**
     * Cihaz rehberindeki tum kisileri yukler.
     * Izin verildikten sonra cagrilir. Kisiler dogrudan gosterilir,
     * boylece discovery API'si calismasa bile rehber erisilebilir.
     */
    fun loadPhoneContacts() {
        viewModelScope.launch {
            try {
                val contacts = contactsProvider.getAllContacts()
                android.util.Log.d("ContactsVM", "Rehberden ${contacts.size} kisi yuklendi")
                _phoneContacts.value = contacts
            } catch (e: Exception) {
                android.util.Log.e("ContactsVM", "Rehber okunamadi", e)
                _phoneContacts.value = emptyList()
            }
        }
    }
}
