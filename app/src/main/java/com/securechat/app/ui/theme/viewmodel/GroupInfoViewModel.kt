package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import com.securechat.network.model.GroupAction
import com.securechat.app.domain.usecase.AddGroupMemberUseCase
import com.securechat.app.domain.usecase.PromoteToAdminUseCase
import com.securechat.app.domain.usecase.RemoveGroupMemberUseCase
import com.securechat.app.domain.usecase.UpdateGroupNameUseCase
import com.securechat.app.ui.screen.GroupMember
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.entity.MessageEntity
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Grup bilgileri ekrani ViewModel'i.
 * Grup uye listesi, admin yetkisi kontrolu, uye ekleme/cikartma,
 * grup adi degistirme islemlerini yonetir.
 */
@HiltViewModel
class GroupInfoViewModel @Inject constructor(
    private val conversationDao: ConversationDao,
    private val messageDao: MessageDao,
    private val contactDao: com.securechat.storage.dao.ContactDao,
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val addGroupMemberUseCase: AddGroupMemberUseCase,
    private val promoteToAdminUseCase: PromoteToAdminUseCase,
    private val removeGroupMemberUseCase: RemoveGroupMemberUseCase,
    private val updateGroupNameUseCase: UpdateGroupNameUseCase,
    private val contactNameResolver: com.securechat.storage.resolver.ContactNameResolver
) : ViewModel() {

    companion object {
        /** Bir grubun icerebilecegi maksimum uye sayisi */
        const val MAX_MEMBERS = 256
    }

    private val _groupInfo = MutableStateFlow<GroupInfo?>(null)
    val groupInfo: StateFlow<GroupInfo?> = _groupInfo.asStateFlow()

    private val _isAdmin = MutableStateFlow(false)
    val isAdmin: StateFlow<Boolean> = _isAdmin.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isLocked = MutableStateFlow(false)
    val isLocked: StateFlow<Boolean> = _isLocked.asStateFlow()

    /** Sureli mesaj suresi (ms). 0 = kapali. */
    private val _disappearingDuration = MutableStateFlow(0L)
    val disappearingDuration: StateFlow<Long> = _disappearingDuration.asStateFlow()

    private val _mediaMessages = MutableStateFlow<List<MessageEntity>>(emptyList())
    val mediaMessages: StateFlow<List<MessageEntity>> = _mediaMessages.asStateFlow()

    private val _documentMessages = MutableStateFlow<List<MessageEntity>>(emptyList())
    val documentMessages: StateFlow<List<MessageEntity>> = _documentMessages.asStateFlow()

    private val _starredMessages = MutableStateFlow<List<MessageEntity>>(emptyList())
    val starredMessages: StateFlow<List<MessageEntity>> = _starredMessages.asStateFlow()

    /**
     * Belirtilen grup kimligine ait bilgileri yukler.
     * Grup uyelerini, admin durumunu ve goruntuleme adlarini alir.
     */
    fun loadGroupInfo(groupId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val conversation = conversationDao.getById(groupId)
                if (conversation == null || !conversation.isGroup) {
                    _error.value = "Grup bulunamadi"
                    return@launch
                }

                val currentUserId = userSession.userId ?: ""
                val memberIds = conversation.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()

                // Admin listesini groupAdmins sutunundan al, yoksa geriye uyumluluk icin ilk uyeyi admin kabul et
                val adminIds = conversation.groupAdmins?.split(",")?.filter { it.isNotBlank() }
                    ?: listOf(memberIds.firstOrNull() ?: "")
                val isCurrentUserAdmin = currentUserId in adminIds

                // Uye bilgilerini olustur
                val members = memberIds.map { memberId ->
                    GroupMember(
                        userId = memberId,
                        isAdmin = memberId in adminIds,
                        isCurrentUser = memberId == currentUserId
                    )
                }

                // Uye isimlerini cozumle: batch query ile (N+1 fix)
                val memberNames = mutableMapOf<String, String>()
                val otherMemberIds = memberIds.filter { it != currentUserId }
                val memberConvs = if (otherMemberIds.isNotEmpty()) {
                    conversationDao.getByPeerIds(otherMemberIds).associateBy { it.peerId }
                } else emptyMap()

                for (memberId in memberIds) {
                    if (memberId == currentUserId) {
                        val displayName = userSession.displayName
                        if (!displayName.isNullOrBlank()) {
                            memberNames[memberId] = displayName
                        }
                        continue
                    }
                    val memberConv = memberConvs[memberId]
                    if (memberConv != null && memberConv.peerName.isNotBlank() && memberConv.peerName != memberId) {
                        memberNames[memberId] = memberConv.peerName
                        continue
                    }
                    val contact = contactDao.getById(memberId)
                    if (contact != null && contact.displayName.isNotBlank() && contact.displayName != memberId) {
                        memberNames[memberId] = contact.displayName
                        continue
                    }
                    // Local'de yok — sunucudan sifreli numarayi cek ve coz (UUID yerine telefon goster)
                    val resolvedName = contactNameResolver.resolveDisplayName(memberId)
                    if (resolvedName.isNotBlank() && resolvedName != memberId) {
                        memberNames[memberId] = resolvedName
                    }
                }

                // Uye telefon numaralarini cozumle: batch query ile (N+1 fix)
                val memberPhones = mutableMapOf<String, String>()
                for (memberId in memberIds) {
                    if (memberId == currentUserId) {
                        val phone = userSession.phoneNumber
                        if (!phone.isNullOrBlank()) {
                            memberPhones[memberId] = phone
                        }
                        continue
                    }
                    val memberConv = memberConvs[memberId]
                    if (memberConv != null && memberConv.peerPhone.isNotBlank()) {
                        memberPhones[memberId] = memberConv.peerPhone
                        continue
                    }
                    val contact = contactDao.getById(memberId)
                    if (contact != null && contact.phoneNumber.isNotBlank()) {
                        memberPhones[memberId] = contact.phoneNumber
                        continue
                    }
                    // Local'de yok — sunucudan sifreli numarayi cek
                    val resolvedPhone = contactNameResolver.resolvePhoneNumber(memberId)
                    if (resolvedPhone.isNotBlank()) {
                        memberPhones[memberId] = resolvedPhone
                    }
                }

                _groupInfo.value = GroupInfo(
                    id = groupId,
                    name = conversation.peerName,
                    members = members,
                    memberNames = memberNames,
                    memberPhones = memberPhones
                )
                _isAdmin.value = isCurrentUserAdmin
                _disappearingDuration.value = conversation.disappearingDuration
                _isLocked.value = conversation.isLocked

                // Medya mesajlarini yukle
                messageDao.getMediaMessages(groupId)
                    .onEach { messages -> _mediaMessages.value = messages }
                    .launchIn(viewModelScope)

                // Dokuman mesajlarini yukle
                messageDao.getDocumentMessages(groupId)
                    .onEach { messages -> _documentMessages.value = messages }
                    .launchIn(viewModelScope)

                // Yildizli mesajlari yukle
                messageDao.getStarredMessages(groupId)
                    .onEach { messages -> _starredMessages.value = messages }
                    .launchIn(viewModelScope)

            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Grup bilgisi yuklenirken hata", e)
                _error.value = "Grup bilgileri yuklenemedi: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Grubun adini degistirir (sadece admin).
     */
    fun updateGroupName(groupId: String, newName: String) {
        viewModelScope.launch {
            try {
                updateGroupNameUseCase(groupId, newName)
                // UI'yi guncelle
                _groupInfo.value = _groupInfo.value?.copy(name = newName.trim())
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Grup adi guncellenirken hata", e)
                _error.value = e.message ?: "Grup adi guncellenemedi"
            }
        }
    }

    /**
     * Gruba yeni uye ekler (sadece admin).
     * Uye limiti kontrolu yapar — maksimum MAX_MEMBERS uye.
     */
    fun addMember(groupId: String, newMemberId: String) {
        viewModelScope.launch {
            try {
                // Mevcut uye sayisi limiti kontrol et
                val currentMemberCount = _groupInfo.value?.members?.size ?: 0
                if (currentMemberCount >= MAX_MEMBERS) {
                    _error.value = "Grup \u00FCye limiti doldu ($MAX_MEMBERS)"
                    return@launch
                }
                addGroupMemberUseCase(groupId, newMemberId)
                // UI'yi guncelle
                loadGroupInfo(groupId)
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Uye eklenirken hata", e)
                _error.value = e.message ?: "Uye eklenemedi"
            }
        }
    }

    /**
     * Gruptan uye cikarir (sadece admin, kendisini cıkaramaz).
     */
    fun removeMember(groupId: String, memberId: String) {
        viewModelScope.launch {
            try {
                removeGroupMemberUseCase(groupId, memberId)
                // UI'yi guncelle
                loadGroupInfo(groupId)
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Uye cikarilirken hata", e)
                _error.value = e.message ?: "Uye cikarilamadi"
            }
        }
    }

    /**
     * Bir grup uyesini admin olarak yukseltir (sadece mevcut admin yapabilir).
     * UPDATE_ADMIN bildirimi tum uyelere gonderilir.
     */
    fun promoteToAdmin(groupId: String, memberId: String) {
        viewModelScope.launch {
            try {
                promoteToAdminUseCase(groupId, memberId)
                // UI'yi guncelle
                loadGroupInfo(groupId)
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Admin yukseltme hatasi", e)
                _error.value = e.message ?: "Yonetici atanamadi"
            }
        }
    }

    /**
     * Bir grup uyesinin admin yetkisini alir (sadece mevcut admin yapabilir).
     * DEMOTE_ADMIN bildirimi tum uyelere gonderilir.
     */
    fun demoteFromAdmin(groupId: String, memberId: String) {
        viewModelScope.launch {
            try {
                val currentUserId = userSession.userId ?: throw IllegalStateException("Kullanici giris yapmamis")
                val conversation = conversationDao.getById(groupId)
                    ?: throw IllegalArgumentException("Grup bulunamadi")

                val currentMembers = conversation.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                val currentAdmins = conversation.groupAdmins?.split(",")?.filter { it.isNotBlank() }
                    ?: listOf(currentMembers.firstOrNull() ?: "")

                if (currentUserId !in currentAdmins) {
                    _error.value = "Sadece admin bu islemi yapabilir"
                    return@launch
                }
                if (memberId !in currentAdmins) {
                    _error.value = "Kullanici zaten admin degil"
                    return@launch
                }

                // Admin listesinden cikar
                val updatedAdmins = currentAdmins.filter { it != memberId }
                if (updatedAdmins.isEmpty()) {
                    _error.value = "Grupta en az bir admin olmalidir"
                    return@launch
                }

                conversationDao.updateGroupAdmins(groupId, updatedAdmins.joinToString(","))

                // Tum grup uyelerine DEMOTE_ADMIN bildirimi gonder
                for (member in currentMembers) {
                    if (member != currentUserId) {
                        signalingClient.sendSignal(
                            SignalMessage.GroupNotification(
                                senderId = currentUserId,
                                recipientId = member,
                                timestamp = System.currentTimeMillis(),
                                groupId = groupId,
                                groupName = conversation.peerName,
                                action = GroupAction.DEMOTE_ADMIN,
                                groupMembers = currentMembers,
                                targetMemberId = memberId
                            )
                        )
                    }
                }

                android.util.Log.d("GroupInfoVM", "Admin yetkisi alindi: $memberId -> $groupId")
                // UI'yi guncelle
                loadGroupInfo(groupId)
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Admin dusurme hatasi", e)
                _error.value = e.message ?: "Yonetici yetkisi alinamadi"
            }
        }
    }

    /**
     * Mesaji yildizli olarak isaretler veya yildizdan cikarir.
     */
    fun toggleMessageStarred(messageId: String, isStarred: Boolean) {
        viewModelScope.launch {
            try {
                messageDao.updateStarred(messageId, isStarred)
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Mesaj yildizlama hatasi", e)
            }
        }
    }

    /**
     * Kullanici kendi istegi ile gruptan ayrilir.
     * Tum kalan uyelere LEAVE_GROUP bildirimi gonderilir.
     */
    fun leaveGroup(groupId: String, onLeft: () -> Unit = {}) {
        viewModelScope.launch {
            try {
                val userId = userSession.userId ?: return@launch
                val conv = conversationDao.getById(groupId) ?: return@launch
                val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()

                // Kalan uyelere LEAVE_GROUP bildirimi gonder
                val remainingMembers = members.filter { it != userId }
                for (memberId in remainingMembers) {
                    signalingClient.sendSignal(
                        SignalMessage.GroupNotification(
                            senderId = userId,
                            recipientId = memberId,
                            timestamp = System.currentTimeMillis(),
                            groupId = groupId,
                            groupName = conv.peerName,
                            action = GroupAction.LEAVE_GROUP,
                            groupMembers = remainingMembers,
                            targetMemberId = null
                        )
                    )
                }

                // Yerel uye listesinden kendini cikar
                conversationDao.updateGroupMembers(groupId, remainingMembers.joinToString(","))

                // Konusmayi arsivle
                conversationDao.updateArchived(groupId, true)

                android.util.Log.d("GroupInfoVM", "Gruptan ayrildi: $groupId")
                onLeft()
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Gruptan ayrilirken hata", e)
                _error.value = e.message ?: "Gruptan ayrılamadı"
            }
        }
    }

    /**
     * Hata mesajini temizler.
     */
    fun clearError() {
        _error.value = null
    }

    /**
     * Grubun biyometrik kilit durumunu degistirir.
     */
    fun toggleLocked(groupId: String) {
        viewModelScope.launch {
            val newLocked = !_isLocked.value
            conversationDao.updateLocked(groupId, newLocked)
            _isLocked.value = newLocked
        }
    }

    /**
     * Sureli mesaj suresini ayarlar.
     * @param groupId Grup kimlik numarasi
     * @param duration Milisaniye cinsinden sure, 0 = kapali
     */
    fun setDisappearingDuration(groupId: String, duration: Long) {
        viewModelScope.launch {
            try {
                conversationDao.updateDisappearingDuration(groupId, duration)
                _disappearingDuration.value = duration

                // Tum grup uyelerine bildir
                val userId = userSession.userId ?: return@launch
                val conv = conversationDao.getById(groupId) ?: return@launch
                val members = conv.groupMembers?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
                for (memberId in members) {
                    if (memberId == userId) continue // Kendine gonderme
                    signalingClient.sendSignal(
                        SignalMessage.DisappearingTimer(
                            senderId = userId,
                            recipientId = memberId,
                            timestamp = System.currentTimeMillis(),
                            duration = duration,
                            conversationId = groupId
                        )
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e("GroupInfoVM", "Sureli mesaj guncelleme hatasi", e)
                _error.value = "Sureli mesaj ayarlanamadi"
            }
        }
    }
}

/**
 * Grup bilgi modeli.
 */
data class GroupInfo(
    val id: String,
    val name: String,
    val members: List<GroupMember>,
    val memberNames: Map<String, String> = emptyMap(),
    val memberPhones: Map<String, String> = emptyMap()
)