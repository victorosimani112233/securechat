package com.securechat.app.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CallMade
import androidx.compose.material.icons.filled.CallMissed
import androidx.compose.material.icons.filled.CallReceived
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import com.securechat.app.ui.theme.DisplayFamily
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.viewmodel.CallHistoryViewModel
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.viewmodel.CallLogItem
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallHistoryScreen(
    onBackClick: () -> Unit,
    onCallClick: (peerId: String, callType: String) -> Unit,
    viewModel: CallHistoryViewModel = hiltViewModel()
) {
    val dark = LocalDarkTheme.current
    val callLogs by viewModel.callLogs.collectAsStateWithLifecycle()

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Arama Geçmişi") },
                    navigationIcon = {
                        IconButton(onClick = onBackClick) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri")
                        }
                    },
                    actions = {
                        if (callLogs.isNotEmpty()) {
                            IconButton(onClick = { viewModel.clearAllHistory() }) {
                                Icon(
                                    Icons.Default.Delete,
                                    contentDescription = "Tümünü Sil",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
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
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.Call,
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                        )
                        Spacer(Modifier.height(16.dp))
                        Text(
                            "Arama geçmişi boş",
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                        )
                    }
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
                        CallLogRow(
                            log = log,
                            dark = dark,
                            onCallClick = { onCallClick(log.peerId, log.callType) }
                        )
                    }
                    item { Spacer(Modifier.height(4.dp)) }
                }
            }
        }
    }
}

@Composable
private fun CallLogRow(
    log: CallLogItem,
    dark: Boolean,
    onCallClick: () -> Unit
) {
    val isMissed = log.status == "MISSED" || log.status == "REJECTED" || log.status == "FAILED"
    val nameColor = if (isMissed) {
        MaterialTheme.colorScheme.error
    } else {
        MaterialTheme.colorScheme.onSurface
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark = dark, shape = RoundedCornerShape(16.dp))
            .clickable(onClick = onCallClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Avatar
        GeneratedAvatar(
            name = log.peerName,
            size = 48.dp
        )

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
    if (status == "MISSED" || status == "FAILED") return Icons.Default.CallMissed
    return when (direction) {
        "OUTGOING" -> Icons.Default.CallMade
        "INCOMING" -> Icons.Default.CallReceived
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
