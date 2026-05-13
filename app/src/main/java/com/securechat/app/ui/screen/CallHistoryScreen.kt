package com.securechat.app.ui.screen

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.CallMade
import androidx.compose.material.icons.automirrored.filled.CallMissed
import androidx.compose.material.icons.automirrored.filled.CallReceived
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.viewmodel.CallHistoryViewModel
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.viewmodel.CallLogItem
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun CallHistoryScreen(
    onBackClick: () -> Unit,
    onCallClick: (peerId: String, callType: String) -> Unit,
    viewModel: CallHistoryViewModel = hiltViewModel()
) {
    val dark = LocalDarkTheme.current
    val callLogs by viewModel.callLogs.collectAsStateWithLifecycle()

    // Coklu secim modu
    var selectedIds by remember { mutableStateOf(setOf<String>()) }
    val isSelectMode = selectedIds.isNotEmpty()

    // Silme onay diyalogu
    var showDeleteDialog by remember { mutableStateOf(false) }

    if (showDeleteDialog) {
        val count = selectedIds.size
        val allSelected = count == callLogs.size
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text(if (allSelected) "Tüm Arama Geçmişini Sil" else "Seçili Kayıtları Sil") },
            text = {
                Text(
                    if (allSelected) "Tüm arama kayıtları kalıcı olarak silinecektir."
                    else "$count arama kaydı kalıcı olarak silinecektir."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    if (allSelected) {
                        viewModel.clearAllHistory()
                    } else {
                        selectedIds.forEach { viewModel.deleteCallLog(it) }
                    }
                    selectedIds = emptySet()
                    showDeleteDialog = false
                }) {
                    Text("Sil", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) { Text("İptal") }
            },
            icon = {
                Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            }
        )
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        if (isSelectMode) {
                            Text("${selectedIds.size} seçili")
                        } else {
                            Text("Arama Geçmişi")
                        }
                    },
                    navigationIcon = {
                        if (isSelectMode) {
                            IconButton(onClick = { selectedIds = emptySet() }) {
                                Icon(Icons.Default.Close, "İptal")
                            }
                        } else {
                            IconButton(onClick = onBackClick) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri")
                            }
                        }
                    },
                    actions = {
                        if (isSelectMode) {
                            // Tümünü seç
                            TextButton(onClick = {
                                selectedIds = if (selectedIds.size == callLogs.size) {
                                    emptySet()
                                } else {
                                    callLogs.map { it.id }.toSet()
                                }
                            }) {
                                Text(
                                    if (selectedIds.size == callLogs.size) "Seçimi Kaldır" else "Tümünü Seç",
                                    color = MaterialTheme.colorScheme.primary,
                                    fontSize = 13.sp
                                )
                            }
                            // Seçilileri sil
                            IconButton(onClick = { showDeleteDialog = true }) {
                                Icon(
                                    Icons.Default.Delete,
                                    contentDescription = "Seçilileri Sil",
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent
                    ),
                    windowInsets = WindowInsets(0)
                )
            },
            containerColor = Color.Transparent,
            contentWindowInsets = WindowInsets(0)
        ) { padding ->
            if (callLogs.isEmpty()) {
                Box(modifier = Modifier.padding(padding)) {
                    com.securechat.app.ui.components.EmptyStateView(
                        icon = Icons.Default.Call,
                        title = "Arama geçmişi boş",
                        subtitle = "Yaptığınız ve kaçırdığınız aramalar burada görünecek."
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(horizontal = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    item { Spacer(Modifier.height(4.dp)) }
                    items(callLogs, key = { it.id }) { log ->
                        val isSelected = log.id in selectedIds
                        CallLogRow(
                            log = log,
                            dark = dark,
                            isSelectMode = isSelectMode,
                            isSelected = isSelected,
                            onClick = {
                                if (isSelectMode) {
                                    selectedIds = if (isSelected) selectedIds - log.id
                                    else selectedIds + log.id
                                } else {
                                    onCallClick(log.peerId, log.callType)
                                }
                            },
                            onLongClick = {
                                selectedIds = if (isSelected) selectedIds - log.id
                                else selectedIds + log.id
                            }
                        )
                    }
                    item { Spacer(Modifier.height(4.dp)) }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CallLogRow(
    log: CallLogItem,
    dark: Boolean,
    isSelectMode: Boolean,
    isSelected: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    val isMissed = log.status == "MISSED" || log.status == "REJECTED" || log.status == "FAILED" || log.status == "BUSY"
    val nameColor = if (isMissed) {
        MaterialTheme.colorScheme.error
    } else {
        MaterialTheme.colorScheme.onSurface
    }

    val selectionBorder = if (isSelected) Modifier.border(
        2.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(16.dp)
    ) else Modifier

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark = dark, shape = RoundedCornerShape(16.dp))
            .then(selectionBorder)
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            )
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Secim modu: checkbox veya avatar
        if (isSelectMode) {
            Box(
                modifier = Modifier.size(48.dp),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = if (isSelected) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                    modifier = Modifier.size(28.dp)
                )
            }
        } else {
            GeneratedAvatar(
                name = log.peerName,
                size = 48.dp
            )
        }

        Spacer(Modifier.width(12.dp))

        // Isim + detay
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = log.peerName,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = nameColor,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = getDirectionIcon(log.direction, log.status),
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = if (isMissed) MaterialTheme.colorScheme.error else Color(0xFF4CAF50)
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    text = getCallLabel(log),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Sag taraf: tarih + arama tipi ikonu
        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = formatTimestamp(log.timestamp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 12.sp
            )
            Spacer(Modifier.height(4.dp))
            Icon(
                imageVector = if (log.callType == "VIDEO") Icons.Default.Videocam else Icons.Default.Phone,
                contentDescription = if (log.callType == "VIDEO") "Görüntülü" else "Sesli",
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }
    }
}

private fun getDirectionIcon(direction: String, status: String): ImageVector {
    if (status == "MISSED" || status == "FAILED" || status == "BUSY") return Icons.AutoMirrored.Filled.CallMissed
    return when (direction) {
        "OUTGOING" -> Icons.AutoMirrored.Filled.CallMade
        "INCOMING" -> Icons.AutoMirrored.Filled.CallReceived
        else -> Icons.Default.Call
    }
}

private fun getCallLabel(log: CallLogItem): String {
    val typeText = if (log.callType == "VIDEO") "Görüntülü" else "Sesli"
    val statusText = when (log.status) {
        "ANSWERED" -> {
            val dirText = if (log.direction == "INCOMING") "Gelen" else "Giden"
            "$dirText $typeText"
        }
        "MISSED" -> "Cevapsız $typeText"
        "REJECTED" -> "Reddedilen $typeText"
        "BUSY" -> if (log.direction == "INCOMING") "Meşgulken gelen $typeText" else "Meşgul $typeText"
        "FAILED" -> "Başarısız $typeText"
        else -> typeText
    }
    val durationText = if (log.status == "ANSWERED" && log.duration > 0) {
        " · ${formatDuration(log.duration)}"
    } else ""
    return "$statusText$durationText"
}

private fun formatDuration(ms: Long): String {
    val seconds = TimeUnit.MILLISECONDS.toSeconds(ms) % 60
    val minutes = TimeUnit.MILLISECONDS.toMinutes(ms) % 60
    val hours = TimeUnit.MILLISECONDS.toHours(ms)
    return if (hours > 0) String.format("%d:%02d:%02d", hours, minutes, seconds)
    else String.format("%d:%02d", minutes, seconds)
}

private fun formatTimestamp(timestamp: Long): String {
    val now = System.currentTimeMillis()
    val diff = now - timestamp
    val dayMs = 24 * 60 * 60 * 1000L

    return when {
        diff < dayMs -> SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(timestamp))
        diff < 2 * dayMs -> "Dün"
        diff < 7 * dayMs -> SimpleDateFormat("EEEE", Locale("tr")).format(Date(timestamp))
        else -> SimpleDateFormat("dd.MM.yyyy", Locale.getDefault()).format(Date(timestamp))
    }
}
