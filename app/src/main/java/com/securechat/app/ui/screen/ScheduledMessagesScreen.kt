package com.securechat.app.ui.screen

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.TabRowDefaults.SecondaryIndicator
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.LocalContentColor
import com.securechat.app.ui.viewmodel.RepeatType
import com.securechat.app.ui.viewmodel.ScheduledMessageItem
import com.securechat.app.ui.viewmodel.ScheduledMessageViewModel
import com.securechat.storage.domain.Conversation
private val DAY_LABELS_SHORT = listOf("P", "S", "Ç", "P", "C", "C", "P")
private val DAY_LABELS_LONG = listOf("Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduledMessagesScreen(
    onBackClick: () -> Unit,
    initialTab: Int = 0,
    viewModel: ScheduledMessageViewModel = hiltViewModel()
) {
    val dark = LocalDarkTheme.current
    val messages by viewModel.scheduledMessages.collectAsStateWithLifecycle()
    val conversations by viewModel.conversations.collectAsStateWithLifecycle()
    var selectedTab by remember { mutableIntStateOf(initialTab) }

    // Form state
    val messageContent by viewModel.messageContent.collectAsStateWithLifecycle()
    val repeatType by viewModel.repeatType.collectAsStateWithLifecycle()
    val selectedDays by viewModel.selectedDays.collectAsStateWithLifecycle()
    val hour by viewModel.hour.collectAsStateWithLifecycle()
    val minute by viewModel.minute.collectAsStateWithLifecycle()
    val recipientIds by viewModel.selectedRecipientIds.collectAsStateWithLifecycle()
    val recipientNames by viewModel.selectedRecipientNames.collectAsStateWithLifecycle()
    val editingId by viewModel.editingId.collectAsStateWithLifecycle()

    var showTimePicker by remember { mutableStateOf(false) }
    var showDayPicker by remember { mutableStateOf(false) }
    var showContactPicker by remember { mutableStateOf(false) }
    var deleteTarget by remember { mutableStateOf<ScheduledMessageItem?>(null) }

    // Silme diyalogu
    deleteTarget?.let { item ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("Planlı Mesajı Sil") },
            text = { Text("Bu planlı mesaj kalıcı olarak silinecektir.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.delete(item.id)
                    deleteTarget = null
                }) {
                    Text("Sil", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("İptal") }
            }
        )
    }

    // Saat secici diyalogu
    if (showTimePicker) {
        TimePickerDialog(
            initialHour = hour,
            initialMinute = minute,
            onConfirm = { h, m ->
                viewModel.setTime(h, m)
                showTimePicker = false
            },
            onDismiss = { showTimePicker = false }
        )
    }

    // Gun secimi diyalogu
    if (showDayPicker) {
        DayPickerDialog(
            currentRepeatType = repeatType,
            selectedDays = selectedDays,
            onRepeatTypeChange = { viewModel.setRepeatType(it) },
            onDayToggle = { viewModel.toggleDay(it) },
            onDismiss = { showDayPicker = false }
        )
    }

    // Kisi secici diyalogu
    if (showContactPicker) {
        ContactPickerDialog(
            conversations = conversations,
            selectedIds = recipientIds.toSet(),
            onToggle = { conv ->
                if (conv.peerId in recipientIds) {
                    viewModel.removeRecipient(conv.peerId)
                } else {
                    viewModel.addRecipient(conv.peerId, conv.peerName)
                }
            },
            onDismiss = { showContactPicker = false }
        )
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Planlı Mesajlar", color = MaterialTheme.colorScheme.onSurface) },
                    navigationIcon = {
                        IconButton(onClick = onBackClick) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri", tint = MaterialTheme.colorScheme.onSurface)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent),
                    windowInsets = WindowInsets(0)
                )
            },
            containerColor = Color.Transparent,
            contentWindowInsets = WindowInsets(0)
        ) { padding ->
            CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
            Column(modifier = Modifier.padding(padding)) {
                // Tab row
                TabRow(
                    selectedTabIndex = selectedTab,
                    containerColor = Color.Transparent,
                    contentColor = MaterialTheme.colorScheme.primary,
                    indicator = { tabPositions ->
                        SecondaryIndicator(
                            Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                            color = MaterialTheme.colorScheme.primary
                        )
                    },
                    divider = {}
                ) {
                    Tab(
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 },
                        text = { Text("Oluştur", fontSize = 14.sp) },
                        selectedContentColor = MaterialTheme.colorScheme.primary,
                        unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Tab(
                        selected = selectedTab == 1,
                        onClick = { selectedTab = 1 },
                        text = { Text("Mevcut Planlananlar", fontSize = 14.sp) },
                        selectedContentColor = MaterialTheme.colorScheme.primary,
                        unselectedContentColor = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                when (selectedTab) {
                    0 -> CreateTab(
                        dark = dark,
                        messageContent = messageContent,
                        repeatType = repeatType,
                        selectedDays = selectedDays,
                        hour = hour,
                        minute = minute,
                        recipientNames = recipientNames,
                        recipientIds = recipientIds,
                        editingId = editingId,
                        onMessageChange = viewModel::setMessageContent,
                        onTimeClick = { showTimePicker = true },
                        onDayClick = { showDayPicker = true },
                        onContactClick = { showContactPicker = true },
                        onRemoveRecipient = viewModel::removeRecipient,
                        onSave = {
                            viewModel.save()
                            selectedTab = 1
                        },
                        onClear = viewModel::clearForm
                    )
                    1 -> ListTab(
                        dark = dark,
                        messages = messages,
                        onEdit = { item ->
                            viewModel.loadForEditing(item)
                            selectedTab = 0
                        },
                        onDelete = { deleteTarget = it },
                        onToggleEnabled = { viewModel.toggleEnabled(it.id) }
                    )
                }
            }
            } // CompositionLocalProvider
        }
    }
}

// ─── Olustur sekmesi ────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CreateTab(
    dark: Boolean,
    messageContent: String,
    repeatType: RepeatType,
    selectedDays: Set<Int>,
    hour: Int,
    minute: Int,
    recipientNames: List<String>,
    recipientIds: List<String>,
    editingId: String?,
    onMessageChange: (String) -> Unit,
    onTimeClick: () -> Unit,
    onDayClick: () -> Unit,
    onContactClick: () -> Unit,
    onRemoveRecipient: (String) -> Unit,
    onSave: () -> Unit,
    onClear: () -> Unit
) {
    val isValid = messageContent.isNotBlank() && recipientIds.isNotEmpty()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Baslik
        if (editingId != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "Düzenleme Modu",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Medium
                )
                TextButton(onClick = onClear) {
                    Text("İptal", color = MaterialTheme.colorScheme.error)
                }
            }
        }

        // 1. Gun Secimi
        SectionCard(
            dark = dark,
            icon = { Icon(Icons.Default.CalendarMonth, null, tint = MaterialTheme.colorScheme.primary) },
            title = "Gün Seçimi",
            subtitle = getDaySubtitle(repeatType, selectedDays),
            onClick = onDayClick
        )

        // 2. Saat Secimi
        SectionCard(
            dark = dark,
            icon = { Icon(Icons.Default.AccessTime, null, tint = MaterialTheme.colorScheme.primary) },
            title = "Saat Seçimi",
            subtitle = String.format("%02d:%02d", hour, minute),
            onClick = onTimeClick
        )

        // 3. Mesaj Icerigi
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                .padding(16.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    "Mesaj İçeriği",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(
                value = messageContent,
                onValueChange = onMessageChange,
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Mesajınızı yazın...") },
                minLines = 3,
                maxLines = 6,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                    cursorColor = MaterialTheme.colorScheme.primary
                )
            )
        }

        // 4. Kisi Secimi
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Default.Person,
                        null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "Alıcılar",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
                IconButton(onClick = onContactClick, modifier = Modifier.size(32.dp)) {
                    Icon(
                        Icons.Default.PersonAdd,
                        "Kişi Ekle",
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }

            if (recipientNames.isEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    "Henüz alıcı seçilmedi",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                )
            } else {
                Spacer(Modifier.height(12.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    recipientNames.forEachIndexed { index, name ->
                        val id = recipientIds.getOrNull(index) ?: return@forEachIndexed
                        RecipientChip(
                            name = name,
                            onRemove = { onRemoveRecipient(id) }
                        )
                    }
                }
            }
        }

        // Kaydet butonu
        TextButton(
            onClick = onSave,
            enabled = isValid,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .background(
                    if (isValid) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.2f),
                    RoundedCornerShape(12.dp)
                )
        ) {
            Text(
                if (editingId != null) "Güncelle" else "Kaydet",
                color = if (isValid) Color.White
                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                fontWeight = FontWeight.SemiBold
            )
        }

        Spacer(Modifier.height(16.dp))
    }
}

// ─── Mevcut Planlananlar sekmesi ─────────────────────────────────

@Composable
private fun ListTab(
    dark: Boolean,
    messages: List<ScheduledMessageItem>,
    onEdit: (ScheduledMessageItem) -> Unit,
    onDelete: (ScheduledMessageItem) -> Unit,
    onToggleEnabled: (ScheduledMessageItem) -> Unit
) {
    if (messages.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    Icons.Default.Schedule,
                    null,
                    modifier = Modifier.size(64.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                )
                Spacer(Modifier.height(16.dp))
                Text(
                    "Henüz planlı mesaj yok",
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                )
            }
        }
    } else {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item { Spacer(Modifier.height(8.dp)) }
            items(messages, key = { it.id }) { item ->
                ScheduledMessageCard(
                    item = item,
                    dark = dark,
                    onEdit = { onEdit(item) },
                    onDelete = { onDelete(item) },
                    onToggleEnabled = { onToggleEnabled(item) }
                )
            }
            item { Spacer(Modifier.height(8.dp)) }
        }
    }
}

// ─── Tek bir planli mesaj karti ──────────────────────────────────

@Composable
private fun ScheduledMessageCard(
    item: ScheduledMessageItem,
    dark: Boolean,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onToggleEnabled: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark = dark, shape = RoundedCornerShape(16.dp))
            .padding(16.dp)
    ) {
        // Ust satir: zaman + acik/kapali
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Default.AccessTime,
                    null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    String.format("%02d:%02d", item.hour, item.minute),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    getDaySubtitle(
                        try { RepeatType.valueOf(item.repeatType) } catch (_: Exception) { RepeatType.ONCE },
                        item.repeatDays.toSet()
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Switch(
                checked = item.isEnabled,
                onCheckedChange = { onToggleEnabled() },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = MaterialTheme.colorScheme.primary,
                    checkedTrackColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f),
                    uncheckedTrackColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                    uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    uncheckedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                )
            )
        }

        Spacer(Modifier.height(8.dp))

        // Mesaj icerigi
        Text(
            item.messageContent,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(Modifier.height(8.dp))

        // Alicilar
        Text(
            "Alıcılar: ${item.recipientNames.joinToString(", ")}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )

        Spacer(Modifier.height(8.dp))
        HorizontalDivider(color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.15f))
        Spacer(Modifier.height(8.dp))

        // Alt aksiyon butonlari
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically
        ) {
            TextButton(onClick = onEdit) {
                Icon(Icons.Default.Edit, null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("Düzenle", fontSize = 13.sp)
            }
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = onDelete) {
                Icon(
                    Icons.Default.Delete, null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.error
                )
                Spacer(Modifier.width(4.dp))
                Text("Sil", fontSize = 13.sp, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

// ─── Section Card ───────────────────────────────────────────────

@Composable
private fun SectionCard(
    dark: Boolean,
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark = dark, shape = RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(modifier = Modifier.size(20.dp)) { icon() }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Icon(
            Icons.Default.Edit,
            null,
            modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
        )
    }
}

// ─── Alici chipi ────────────────────────────────────────────────

@Composable
private fun RecipientChip(name: String, onRemove: () -> Unit) {
    Row(
        modifier = Modifier
            .background(
                MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                RoundedCornerShape(20.dp)
            )
            .border(
                1.dp,
                MaterialTheme.colorScheme.primary.copy(alpha = 0.3f),
                RoundedCornerShape(20.dp)
            )
            .padding(start = 10.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            name,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary
        )
        IconButton(onClick = onRemove, modifier = Modifier.size(20.dp)) {
            Icon(
                Icons.Default.Close,
                "Kaldır",
                modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }
    }
}

// ─── TimePicker Dialog ──────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimePickerDialog(
    initialHour: Int,
    initialMinute: Int,
    onConfirm: (Int, Int) -> Unit,
    onDismiss: () -> Unit
) {
    val timePickerState = rememberTimePickerState(
        initialHour = initialHour,
        initialMinute = initialMinute,
        is24Hour = true
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Saat Seçin") },
        text = {
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                TimePicker(state = timePickerState)
            }
        },
        confirmButton = {
            TextButton(onClick = {
                onConfirm(timePickerState.hour, timePickerState.minute)
            }) { Text("Tamam") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("İptal") }
        }
    )
}

// ─── DayPicker Dialog ───────────────────────────────────────────

@Composable
private fun DayPickerDialog(
    currentRepeatType: RepeatType,
    selectedDays: Set<Int>,
    onRepeatTypeChange: (RepeatType) -> Unit,
    onDayToggle: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Gün Seçimi") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // Tekrar tipi secimi
                RepeatType.entries.forEach { type ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .clickable { onRepeatTypeChange(type) }
                            .background(
                                if (currentRepeatType == type)
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
                                else Color.Transparent,
                                RoundedCornerShape(10.dp)
                            )
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(20.dp)
                                .border(
                                    2.dp,
                                    if (currentRepeatType == type) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                                    CircleShape
                                )
                                .then(
                                    if (currentRepeatType == type) Modifier.background(
                                        MaterialTheme.colorScheme.primary,
                                        CircleShape
                                    ).padding(4.dp).background(Color.White, CircleShape)
                                    else Modifier
                                )
                        )
                        Spacer(Modifier.width(12.dp))
                        Text(
                            type.label,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = if (currentRepeatType == type) FontWeight.Medium else FontWeight.Normal
                        )
                    }
                }

                // Ozel gun secimi
                AnimatedVisibility(visible = currentRepeatType == RepeatType.CUSTOM) {
                    Column {
                        Spacer(Modifier.height(4.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly
                        ) {
                            DAY_LABELS_LONG.forEachIndexed { index, label ->
                                val day = index + 1  // 1=Pzt ... 7=Paz
                                val isSelected = day in selectedDays
                                Box(
                                    modifier = Modifier
                                        .size(40.dp)
                                        .clip(CircleShape)
                                        .background(
                                            if (isSelected) MaterialTheme.colorScheme.primary
                                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.1f),
                                            CircleShape
                                        )
                                        .clickable { onDayToggle(day) },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        label,
                                        fontSize = 12.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = if (isSelected) Color.White
                                        else MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Tamam") }
        }
    )
}

// ─── Kisi Secici Dialog ─────────────────────────────────────────

@Composable
private fun ContactPickerDialog(
    conversations: List<Conversation>,
    selectedIds: Set<String>,
    onToggle: (Conversation) -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Alıcı Seç") },
        text = {
            if (conversations.isEmpty()) {
                Text(
                    "Henüz sohbet geçmişi yok",
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                )
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.height(400.dp)
                ) {
                    // Tumunu sec / Secimi kaldir
                    item {
                        val allSelected = conversations.all { it.peerId in selectedIds }
                        TextButton(
                            onClick = {
                                conversations.forEach { conv ->
                                    if (allSelected) {
                                        if (conv.peerId in selectedIds) onToggle(conv)
                                    } else {
                                        if (conv.peerId !in selectedIds) onToggle(conv)
                                    }
                                }
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(
                                if (allSelected) "Seçimi Kaldır" else "Tümünü Seç",
                                color = MaterialTheme.colorScheme.primary,
                                fontSize = 13.sp
                            )
                        }
                    }
                    items(conversations, key = { it.id }) { conv ->
                        val isSelected = conv.peerId in selectedIds
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .clickable { onToggle(conv) }
                                .background(
                                    if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
                                    else Color.Transparent,
                                    RoundedCornerShape(10.dp)
                                )
                                .padding(horizontal = 8.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            GeneratedAvatar(name = conv.peerName, size = 36.dp)
                            Spacer(Modifier.width(12.dp))
                            Text(
                                conv.peerName,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.weight(1f),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (isSelected) {
                                Icon(
                                    Icons.Default.Close,
                                    null,
                                    modifier = Modifier.size(18.dp),
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Tamam") }
        }
    )
}

// ─── Yardimci fonksiyonlar ──────────────────────────────────────

private fun getDaySubtitle(repeatType: RepeatType, selectedDays: Set<Int>): String {
    return when (repeatType) {
        RepeatType.ONCE -> "Tek Seferlik"
        RepeatType.DAILY -> "Her Gün"
        RepeatType.CUSTOM -> {
            if (selectedDays.isEmpty()) "Gün seçilmedi"
            else selectedDays.sorted().joinToString(",") { dayNum ->
                DAY_LABELS_SHORT.getOrElse(dayNum - 1) { "?" }
            }
        }
    }
}
