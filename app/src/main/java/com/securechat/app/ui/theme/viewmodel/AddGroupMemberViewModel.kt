package com.securechat.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.AddGroupMemberUseCase
import com.securechat.contacts.ContactSearchManager
import com.securechat.contacts.DiscoveryApiService
import com.securechat.contacts.PhoneNumberNormalizer
import com.securechat.contacts.UserDiscoveryService
import com.securechat.contacts.model.CheckUsersRequest
import com.securechat.storage.dao.ConversationDao
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Mevcut gruba uye ekleme ekrani ViewModel'i.
 * Kayitli kisileri gosterir, mevcut grup uyelerini filtreler.
 * Telefon numarasiyla ekleme destegi var.
 */
@HiltViewModel
class AddGroupMemberViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val conversationDao: ConversationDao,
    private val userSession: UserSession,
    private val addGroupMemberUseCase: AddGroupMemberUseCase,
    private val contactSearchManager: ContactSearchManager,
    private val userDiscoveryService: UserDiscoveryService,
    private val discoveryApiService: DiscoveryApiService
) : ViewModel() {

    companion object {
        /** Bir grubun icerebilecegi maksimum uye sayisi */
        const val MAX_MEMBERS = 256
    }

    val groupId: String = savedStateHandle["groupId"] ?: ""

    private val _contacts = MutableStateFlow<List<SelectableContact>>(emptyList())

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    /** Mevcut grup uyeleri — bunlar listede gosterilmez */
    private val _existingMembers = MutableStateFlow<Set<String>>(emptySet())

    /** Arama sorgusuna gore filtrelenmis kisi listesi (mevcut uyeler haric) */
    val contacts: StateFlow<List<SelectableContact>> = combine(
        _contacts, _searchQuery, _existingMembers
    ) { allContacts, query, existing ->
        val filtered = allContacts.filter { it.userId !in existing }
        if (query.isBlank()) filtered
        else {
            val lower = query.lowercase()
            filtered.filter {
                it.displayName.lowercase().contains(lower) ||
                it.phoneNumber.contains(query)
            }
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), emptyList())

    val selectedMembers: StateFlow<List<String>> = _contacts.map { contacts ->
        contacts.filter { it.isSelected }.map { it.userId }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), emptyList())

    /** Gruba eklenebilecek kalan uye kapasitesi */
    val remainingCapacity: StateFlow<Int> = combine(
        _existingMembers, _contacts.map { c -> c.count { it.isSelected } }
    ) { existing, selectedCount ->
        MAX_MEMBERS - existing.size - selectedCount
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(), MAX_MEMBERS)

    private val _isLoadingContacts = MutableStateFlow(false)
    val isLoadingContacts: StateFlow<Boolean> = _isLoadingContacts.asStateFlow()

    private val _isAdding = MutableStateFlow(false)
    val isAdding: StateFlow<Boolean> = _isAdding.asStateFlow()

    private val _addComplete = MutableStateFlow(false)
    val addComplete: StateFlow<Boolean> = _addComplete.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _phoneInput = MutableStateFlow("")
    val phoneInput: StateFlow<String> = _phoneInput.asStateFlow()

    private val _isResolvingPhone = MutableStateFlow(false)
    val isResolvingPhone: StateFlow<Boolean> = _isResolvingPhone.asStateFlow()

    private val _phoneNotFound = MutableStateFlow<String?>(null)
    val phoneNotFound: StateFlow<String?> = _phoneNotFound.asStateFlow()

    private val _groupName = MutableStateFlow("")
    val groupName: StateFlow<String> = _groupName.asStateFlow()

    init {
        loadExistingMembers()
        discoverAndLoadContacts()
    }

    private fun loadExistingMembers() {
        viewModelScope.launch {
            val conversation = conversationDao.getById(groupId)
            if (conversation != null) {
                _groupName.value = conversation.peerName
                val members = conversation.groupMembers?.split(",")
                    ?.filter { it.isNotBlank() }?.toSet() ?: emptySet()
                _existingMembers.value = members
            }
        }
    }

    private fun discoverAndLoadContacts() {
        viewModelScope.launch {
            _isLoadingContacts.value = true
            try {
                userDiscoveryService.discoverRegisteredUsers()
            } catch (e: Exception) {
                android.util.Log.e("AddGroupMemberVM", "Kisi kesfi hatasi: ${e.message}")
            }
            loadContacts()
        }
    }

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
                android.util.Log.e("AddGroupMemberVM", "Kisi yukleme hatasi", e)
                _error.value = "Kişiler yüklenirken hata oluştu"
                _isLoadingContacts.value = false
            }
        }
    }

    fun onSearchQueryChanged(query: String) {
        _searchQuery.value = query
    }

    fun toggleContactSelection(userId: String) {
        val contact = _contacts.value.find { it.userId == userId } ?: return
        // Secim aciliyorsa limit kontrolu yap (mevcut uyeler + secili uyeler)
        if (!contact.isSelected) {
            val existingCount = _existingMembers.value.size
            val selectedCount = _contacts.value.count { it.isSelected }
            if (existingCount + selectedCount >= MAX_MEMBERS) {
                _error.value = "Grup en fazla $MAX_MEMBERS \u00FCye i\u00E7erebilir"
                return
            }
        }
        _contacts.value = _contacts.value.map {
            if (it.userId == userId) it.copy(isSelected = !it.isSelected) else it
        }
    }

    fun onPhoneInputChanged(phone: String) {
        _phoneInput.value = phone
    }

    fun consumePhoneNotFound() {
        _phoneNotFound.value = null
    }

    fun clearError() {
        _error.value = null
    }

    /**
     * Telefon numarasiyla kullanici cozumler ve secili listeye ekler.
     */
    fun addMemberByPhone(countryCode: String = "+90") {
        val rawPhone = _phoneInput.value.trim()
        if (rawPhone.isBlank()) return

        val phone = if (rawPhone.startsWith("+")) rawPhone
                    else "$countryCode$rawPhone"

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
                    if (userId in _existingMembers.value) {
                        _error.value = "Bu kişi zaten grupta"
                    } else if (_contacts.value.any { it.userId == userId && it.isSelected }) {
                        _error.value = "Bu kişi zaten seçili"
                    } else if (_existingMembers.value.size + _contacts.value.count { it.isSelected } >= MAX_MEMBERS) {
                        _error.value = "Grup en fazla $MAX_MEMBERS \u00FCye i\u00E7erebilir"
                    } else {
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
                android.util.Log.e("AddGroupMemberVM", "Telefon cozumleme hatasi", e)
                _phoneNotFound.value = phone
            } finally {
                _isResolvingPhone.value = false
            }
        }
    }

    /**
     * Secili kisileri gruba ekler. Her biri icin AddGroupMemberUseCase cagrilir.
     */
    fun addSelectedMembers() {
        val memberIds = selectedMembers.value
        if (memberIds.isEmpty()) {
            _error.value = "En az 1 kişi seçmelisiniz"
            return
        }
        // Toplam uye sayisi limiti kontrol et
        val totalAfterAdd = _existingMembers.value.size + memberIds.size
        if (totalAfterAdd > MAX_MEMBERS) {
            _error.value = "Grup en fazla $MAX_MEMBERS \u00FCye i\u00E7erebilir. Kalan kapasite: ${MAX_MEMBERS - _existingMembers.value.size}"
            return
        }

        viewModelScope.launch {
            _isAdding.value = true
            var successCount = 0
            for (memberId in memberIds) {
                try {
                    addGroupMemberUseCase(groupId, memberId)
                    successCount++
                } catch (e: Exception) {
                    android.util.Log.e("AddGroupMemberVM", "Uye ekleme hatasi: $memberId", e)
                    _error.value = e.message ?: "Üye eklenemedi"
                }
            }
            _isAdding.value = false
            if (successCount > 0) {
                _addComplete.value = true
            }
        }
    }
}
