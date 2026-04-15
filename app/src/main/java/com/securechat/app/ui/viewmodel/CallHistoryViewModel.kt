package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.storage.dao.CallLogDao
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.entity.CallLogEntity
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CallLogItem(
    val id: String,
    val peerId: String,
    val peerName: String,
    val callType: String,       // VOICE, VIDEO
    val direction: String,      // INCOMING, OUTGOING
    val status: String,         // ANSWERED, MISSED, REJECTED, FAILED
    val timestamp: Long,
    val duration: Long
)

@HiltViewModel
class CallHistoryViewModel @Inject constructor(
    private val callLogDao: CallLogDao,
    private val conversationDao: ConversationDao
) : ViewModel() {

    val callLogs: StateFlow<List<CallLogItem>> = callLogDao.getAll()
        .map { logs ->
            logs.map { entity ->
                val name = resolveDisplayName(entity)
                CallLogItem(
                    id = entity.id,
                    peerId = entity.peerId,
                    peerName = name,
                    callType = entity.callType,
                    direction = entity.direction,
                    status = entity.status,
                    timestamp = entity.timestamp,
                    duration = entity.duration
                )
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private suspend fun resolveDisplayName(entity: CallLogEntity): String {
        val conv = conversationDao.getByPeerId(entity.peerId)
        return conv?.peerName ?: entity.peerName
    }

    fun deleteCallLog(id: String) {
        viewModelScope.launch { callLogDao.deleteById(id) }
    }

    fun clearAllHistory() {
        viewModelScope.launch { callLogDao.deleteAll() }
    }
}
