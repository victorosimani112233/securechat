package com.securechat.app.ui.viewmodel

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.data.UserSession
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.ExportLogDao
import com.securechat.storage.entity.ExportLogEntity
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Grup admin'ine ozel sohbet disa aktarma gecmisini gosterir.
 *
 * Lokal DB'den (ExportLogDao) okunur — sunucudan veri cekilmez.
 * Sadece bu cihazda decrypt edilebilmis log girdileri gozukur; yeni atanan
 * admin atanma zamanindan oncesinin loglarini GORMEZ (kasitli zero-knowledge davranis).
 */
@HiltViewModel
class ExportHistoryViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val exportLogDao: ExportLogDao,
    private val conversationDao: ConversationDao,
    private val userSession: UserSession
) : ViewModel() {

    val groupId: String = savedStateHandle.get<String>("groupId") ?: ""

    private val _isAdmin = MutableStateFlow(false)
    val isAdmin: StateFlow<Boolean> = _isAdmin.asStateFlow()

    /** Bu grubun export log girdileri, ters kronolojik. */
    val entries: StateFlow<List<ExportLogEntity>> =
        exportLogDao.observeForGroup(groupId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    init {
        viewModelScope.launch {
            val conv = conversationDao.getById(groupId) ?: return@launch
            val admins = conv.groupAdmins?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
            _isAdmin.value = (userSession.userId ?: "") in admins
        }
    }
}
