package com.securechat.app.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.data.ChatStorageAnalyzer
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.viewmodel.StorageUsageViewModel

/**
 * Sohbet basina depolama kullanim ekrani.
 *
 * - Her satir bir konusmanin toplam boyutu + dosya sayisi ozeti
 * - "Temizle" butonu ile o konusmadaki tum medya/dosya silinir (mesaj metni kalir)
 * - Buyukten kucuge sirali (kullaniciya neyi temizleyecegini gosteren UX)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StorageUsageScreen(
    onBack: () -> Unit,
    viewModel: StorageUsageViewModel = hiltViewModel()
) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val cleaningId by viewModel.cleaningId.collectAsStateWithLifecycle()
    var confirmCleanId by remember { mutableStateOf<String?>(null) }
    var confirmCleanName by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Depolama Kullanımı") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Geri"
                        )
                    }
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            if (isLoading && items.isEmpty()) {
                CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                return@Box
            }
            if (items.isEmpty()) {
                Text(
                    "Henüz sohbet yok",
                    modifier = Modifier.align(Alignment.Center),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                return@Box
            }
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(items, key = { it.conversationId }) { item ->
                    ChatStorageRow(
                        item = item,
                        isCleaning = cleaningId == item.conversationId,
                        onClean = {
                            confirmCleanId = item.conversationId
                            confirmCleanName = item.displayName
                        }
                    )
                }
            }
        }
    }

    if (confirmCleanId != null) {
        AlertDialog(
            onDismissRequest = { confirmCleanId = null },
            title = { Text("Medyayı temizle") },
            text = {
                Text(
                    "\"$confirmCleanName\" sohbetindeki tüm medya ve dosya mesajları silinecek. " +
                        "Mesaj metinleri korunur. Bu işlem geri alınamaz."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val id = confirmCleanId
                    confirmCleanId = null
                    if (id != null) viewModel.cleanFiles(id)
                }) { Text("Temizle", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmCleanId = null }) { Text("Vazgeç") }
            }
        )
    }
}

@Composable
private fun ChatStorageRow(
    item: ChatStorageAnalyzer.ChatStorageBreakdown,
    isCleaning: Boolean,
    onClean: () -> Unit
) {
    val dark = LocalDarkTheme.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark = dark, shape = RoundedCornerShape(16.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (item.isGroup) Icons.Default.Group else Icons.Default.Person,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp)
            )
        }
        Column(modifier = Modifier.weight(1f).padding(start = 12.dp)) {
            Text(
                item.displayName,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1
            )
            Text(
                "${item.messageCount} mesaj · ${item.fileCount} dosya · ${formatBytes(item.totalBytes)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (isCleaning) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
        } else if (item.fileCount > 0) {
            IconButton(onClick = onClean) {
                Icon(
                    Icons.Default.CleaningServices,
                    contentDescription = "Medyayı temizle",
                    tint = Color(0xFFEF6C00)
                )
            }
        }
    }
}

private fun formatBytes(bytes: Long): String {
    val kb = 1024.0
    val mb = kb * 1024
    val gb = mb * 1024
    return when {
        bytes < kb -> "$bytes B"
        bytes < mb -> "%.1f KB".format(bytes / kb)
        bytes < gb -> "%.1f MB".format(bytes / mb)
        else -> "%.2f GB".format(bytes / gb)
    }
}
