package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.UserSession
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
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
    private val userSession: UserSession,
    private val signalingClient: SignalingClient,
    private val addGroupMemberUseCase: AddGroupMemberUseCase,
    private val promoteToAdminUseCase: PromoteToAdminUseCase,
    private val removeGroupMemberUseCase: RemoveGroupMemberUseCase,
    private val updateGroupNameUseCase: UpdateGroupNameUseCase
) : ViewModel() {

    private val _groupInfo = MutableStateFlow<GroupInfo?>(null)
    val groupInfo: StateFlow<GroupInfo?> = _groupInfo.asStateFlow()

    private val _isAdmin = MutableStateFlow(false)
    val isAdmin: StateFlow<Boolean> = _isAdmin.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

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

                // Uye isimlerini konusmalardan bul
                val memberNames = mutableMapOf<String, String>()
                for (memberId in memberIds) {
                    val memberConv = conversationDao.getByPeerId(memberId)
                    if (memberConv != null && memberConv.peerName.isNotBlank() && memberConv.peerName != memberId) {
                        memberNames[memberId] = memberConv.peerName
                    }
                }

                _groupInfo.value = GroupInfo(
                    id = groupId,
                    name = conversation.peerName,
                    members = members,
                    memberNames = memberNames
                )
                _isAdmin.value = isCurrentUserAdmin
                _disappearingDuration.value = conversation.disappearingDuration

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
     */
    fun addMember(groupId: String, newMemberId: String) {
        viewModelScope.launch {
            try {
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
     * Hata mesajini temizler.
     */
    fun clearError() {
        _error.value = null
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
    val memberNames: Map<String, String> = emptyMap()
)