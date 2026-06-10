package com.securechat.app.ui.screen

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.data.AutoDownloadPolicy
import com.securechat.app.ui.viewmodel.AutoDownloadViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AutoDownloadSettingsScreen(
    onBack: () -> Unit,
    viewModel: AutoDownloadViewModel = hiltViewModel()
) {
    val policy by viewModel.policy.collectAsStateWithLifecycle()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Otomatik İndirme") },
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
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                item {
                    SectionHeader("Wi-Fi üzerinden")
                    PolicyRow(
                        "Fotoğraflar",
                        policy.photosOnWifi
                    ) { viewModel.togglePhotos(onWifi = true, value = it) }
                    PolicyRow(
                        "Videolar",
                        policy.videosOnWifi
                    ) { viewModel.toggleVideos(onWifi = true, value = it) }
                    PolicyRow(
                        "Belgeler",
                        policy.documentsOnWifi
                    ) { viewModel.toggleDocuments(onWifi = true, value = it) }
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                        thickness = 0.5.dp
                    )
                    SectionHeader("Hücresel veri üzerinden")
                    PolicyRow(
                        "Fotoğraflar",
                        policy.photosOnCellular
                    ) { viewModel.togglePhotos(onWifi = false, value = it) }
                    PolicyRow(
                        "Videolar",
                        policy.videosOnCellular
                    ) { viewModel.toggleVideos(onWifi = false, value = it) }
                    PolicyRow(
                        "Belgeler",
                        policy.documentsOnCellular
                    ) { viewModel.toggleDocuments(onWifi = false, value = it) }
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                        thickness = 0.5.dp
                    )
                    ListItem(
                        headlineContent = {
                            Text(
                                "Hücresel üst sınırı: ${formatMb(policy.maxAutoDownloadBytes)}",
                                style = MaterialTheme.typography.bodyMedium
                            )
                        },
                        supportingContent = {
                            Text(
                                "Daha büyük dosyalar hücresel veride otomatik indirilmez",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
    )
}

@Composable
private fun PolicyRow(
    label: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f)
        )
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

private fun formatMb(bytes: Long): String {
    val mb = bytes / (1024.0 * 1024.0)
    return "%.0f MB".format(mb)
}
