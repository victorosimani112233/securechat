package com.securechat.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securechat.app.scheduler.ScheduledMessageAlarmScheduler
import com.securechat.storage.dao.ScheduledMessageDao
import com.securechat.storage.domain.Conversation
import com.securechat.storage.entity.ScheduledMessageEntity
import com.securechat.storage.repository.MessageRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.UUID
import javax.inject.Inject

/** Planli mesaj UI modeli. */
data class ScheduledMessageItem(
    val id: String,
    val messageContent: String,
    val repeatType: String,       // ONCE, DAILY, CUSTOM
    val repeatDays: List<Int>,    // 1=Pzt...7=Paz
    val hour: Int,
    val minute: Int,
    val recipientIds: List<String>,
    val recipientNames: List<String>,
    val isEnabled: Boolean,
    val nextTriggerTime: Long,
    val createdAt: Long
)

/** Tekrar tipi enumlari. */
enum class RepeatType(val label: String) {
    ONCE("Tek Seferlik"),
    DAILY("Her Gün"),
    CUSTOM("Özel Gün Seçimi")
}

@HiltViewModel
class ScheduledMessageViewModel @Inject constructor(
    private val scheduledMessageDao: ScheduledMessageDao,
    private val messageRepository: MessageRepository,
    private val alarmScheduler: ScheduledMessageAlarmScheduler
) : ViewModel() {

    /** Mevcut konusmalar — kisi secici icin kullanilir. */
    val conversations: StateFlow<List<Conversation>> = messageRepository.getConversations()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val scheduledMessages: StateFlow<List<ScheduledMessageItem>> = scheduledMessageDao.getAll()
        .map { list ->
            list.map { it.toItem() }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    // Duzenlenecek mesaj id'si (null ise yeni olusturma modu)
    private val _editingId = MutableStateFlow<String?>(null)
    val editingId: StateFlow<String?> = _editingId.asStateFlow()

    // Form alanlari
    private val _messageContent = MutableStateFlow("")
    val messageContent: StateFlow<String> = _messageContent.asStateFlow()

    private val _repeatType = MutableStateFlow(RepeatType.ONCE)
    val repeatType: StateFlow<RepeatType> = _repeatType.asStateFlow()

    private val _selectedDays = MutableStateFlow(emptySet<Int>())
    val selectedDays: StateFlow<Set<Int>> = _selectedDays.asStateFlow()

    private val _hour = MutableStateFlow(9)
    val hour: StateFlow<Int> = _hour.asStateFlow()

    private val _minute = MutableStateFlow(0)
    val minute: StateFlow<Int> = _minute.asStateFlow()

    private val _selectedRecipientIds = MutableStateFlow(emptyList<String>())
    val selectedRecipientIds: StateFlow<List<String>> = _selectedRecipientIds.asStateFlow()

    private val _selectedRecipientNames = MutableStateFlow(emptyList<String>())
    val selectedRecipientNames: StateFlow<List<String>> = _selectedRecipientNames.asStateFlow()

    fun setMessageContent(value: String) { _messageContent.value = value }
    fun setRepeatType(value: RepeatType) { _repeatType.value = value }
    fun toggleDay(day: Int) {
        _selectedDays.value = _selectedDays.value.let {
            if (day in it) it - day else it + day
        }
    }
    fun setTime(h: Int, m: Int) { _hour.value = h; _minute.value = m }

    fun addRecipient(id: String, name: String) {
        if (id !in _selectedRecipientIds.value) {
            _selectedRecipientIds.value = _selectedRecipientIds.value + id
            _selectedRecipientNames.value = _selectedRecipientNames.value + name
        }
    }

    fun removeRecipient(id: String) {
        val idx = _selectedRecipientIds.value.indexOf(id)
        if (idx >= 0) {
            _selectedRecipientIds.value = _selectedRecipientIds.value.toMutableList().apply { removeAt(idx) }
            _selectedRecipientNames.value = _selectedRecipientNames.value.toMutableList().apply { removeAt(idx) }
        }
    }

    fun clearForm() {
        _editingId.value = null
        _messageContent.value = ""
        _repeatType.value = RepeatType.ONCE
        _selectedDays.value = emptySet()
        _hour.value = 9
        _minute.value = 0
        _selectedRecipientIds.value = emptyList()
        _selectedRecipientNames.value = emptyList()
    }

    /** Mevcut bir planli mesaji duzenleme formuna yukle. */
    fun loadForEditing(item: ScheduledMessageItem) {
        _editingId.value = item.id
        _messageContent.value = item.messageContent
        _repeatType.value = RepeatType.valueOf(item.repeatType)
        _selectedDays.value = item.repeatDays.toSet()
        _hour.value = item.hour
        _minute.value = item.minute
        _selectedRecipientIds.value = item.recipientIds
        _selectedRecipientNames.value = item.recipientNames
    }

    /** Kaydet (yeni veya guncelle). */
    fun save() {
        val content = _messageContent.value.trim()
        if (content.isBlank() || _selectedRecipientIds.value.isEmpty()) return

        val id = _editingId.value ?: UUID.randomUUID().toString()
        val repeatTypeStr = _repeatType.value.name
        val days = if (_repeatType.value == RepeatType.CUSTOM) {
            _selectedDays.value.sorted().joinToString(",")
        } else null
        val nextTrigger = calculateNextTrigger(
            _hour.value, _minute.value, _repeatType.value, _selectedDays.value
        )

        val entity = ScheduledMessageEntity(
            id = id,
            messageContent = content,
            repeatType = repeatTypeStr,
            repeatDays = days,
            hour = _hour.value,
            minute = _minute.value,
            recipientIds = _selectedRecipientIds.value.joinToString(","),
            recipientNames = _selectedRecipientNames.value.joinToString(","),
            isEnabled = true,
            nextTriggerTime = nextTrigger
        )

        viewModelScope.launch {
            scheduledMessageDao.insert(entity)
            // ALARM KUR — kullanici "ekstra is" beklemez, set ettigi saatte mesaji gonderir.
            alarmScheduler.schedule(entity)
            clearForm()
        }
    }

    fun toggleEnabled(id: String) {
        viewModelScope.launch {
            val entity = scheduledMessageDao.getById(id) ?: return@launch
            val updated = entity.copy(isEnabled = !entity.isEnabled)
            scheduledMessageDao.update(updated)
            // Toggle on → alarm kur, off → iptal
            if (updated.isEnabled) alarmScheduler.schedule(updated)
            else alarmScheduler.cancel(id)
        }
    }

    fun delete(id: String) {
        viewModelScope.launch {
            alarmScheduler.cancel(id)
            scheduledMessageDao.deleteById(id)
        }
    }

    private fun ScheduledMessageEntity.toItem() = ScheduledMessageItem(
        id = id,
        messageContent = messageContent,
        repeatType = repeatType,
        repeatDays = repeatDays?.split(",")?.mapNotNull { it.trim().toIntOrNull() } ?: emptyList(),
        hour = hour,
        minute = minute,
        recipientIds = recipientIds.split(",").filter { it.isNotBlank() },
        recipientNames = recipientNames.split(",").filter { it.isNotBlank() },
        isEnabled = isEnabled,
        nextTriggerTime = nextTriggerTime,
        createdAt = createdAt
    )

    companion object {
        fun calculateNextTrigger(hour: Int, minute: Int, repeatType: RepeatType, days: Set<Int>): Long {
            val now = Calendar.getInstance()
            val target = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            when (repeatType) {
                RepeatType.ONCE, RepeatType.DAILY -> {
                    if (target.timeInMillis <= now.timeInMillis) {
                        target.add(Calendar.DAY_OF_YEAR, 1)
                    }
                }
                RepeatType.CUSTOM -> {
                    if (days.isEmpty()) {
                        if (target.timeInMillis <= now.timeInMillis) {
                            target.add(Calendar.DAY_OF_YEAR, 1)
                        }
                    } else {
                        // Bugunun dayOfWeek'ini Calendar formatindan donustur (Calendar: 1=Paz, 2=Pzt ... 7=Cmt)
                        // Bizim format: 1=Pzt ... 7=Paz
                        fun calendarDayToOurs(calDay: Int): Int = when (calDay) {
                            Calendar.MONDAY -> 1; Calendar.TUESDAY -> 2
                            Calendar.WEDNESDAY -> 3; Calendar.THURSDAY -> 4
                            Calendar.FRIDAY -> 5; Calendar.SATURDAY -> 6
                            Calendar.SUNDAY -> 7; else -> 1
                        }
                        fun ourDayToCalendar(ourDay: Int): Int = when (ourDay) {
                            1 -> Calendar.MONDAY; 2 -> Calendar.TUESDAY
                            3 -> Calendar.WEDNESDAY; 4 -> Calendar.THURSDAY
                            5 -> Calendar.FRIDAY; 6 -> Calendar.SATURDAY
                            7 -> Calendar.SUNDAY; else -> Calendar.MONDAY
                        }

                        val todayOur = calendarDayToOurs(now.get(Calendar.DAY_OF_WEEK))
                        val sortedDays = days.sorted()

                        // Bugun secili gunlerden biri mi ve saat gecmediyse
                        if (todayOur in sortedDays && target.timeInMillis > now.timeInMillis) {
                            // target zaten dogru
                        } else {
                            // Sonraki secili gunu bul
                            val nextDay = sortedDays.firstOrNull { it > todayOur }
                                ?: sortedDays.first()
                            val daysAhead = if (nextDay > todayOur) {
                                nextDay - todayOur
                            } else {
                                7 - todayOur + nextDay
                            }
                            target.add(Calendar.DAY_OF_YEAR, daysAhead)
                        }
                    }
                }
            }
            return target.timeInMillis
        }
    }
}
