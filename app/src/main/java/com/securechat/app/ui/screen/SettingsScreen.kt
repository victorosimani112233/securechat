package com.securechat.app.ui.screen

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.DisplayFamily
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.viewmodel.SettingsViewModel

/**
 * Ayarlar ekranı.
 * Profil fotoğrafı, tema seçimi, güvenlik, veri yönetimi ve hakkında bölümleri.
 * Azure glassmorphism tasarım ile.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onBackClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    val profilePhotoUri by viewModel.profilePhotoUri.collectAsStateWithLifecycle()
    val followSystem by viewModel.followSystemTheme.collectAsStateWithLifecycle()
    val isDark by viewModel.isDarkTheme.collectAsStateWithLifecycle()
    val showNotificationContent by viewModel.showNotificationContent.collectAsStateWithLifecycle()
    val shareLastSeen by viewModel.shareLastSeen.collectAsStateWithLifecycle()

    var showNukeDialog by remember { mutableStateOf(false) }
    var showThemeDialog by remember { mutableStateOf(false) }

    val context = LocalContext.current

    // Fotoğraf seçici
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let {
            // Kalıcı URI izni al
            try {
                context.contentResolver.takePersistableUriPermission(
                    it, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) { }
            viewModel.updateProfilePhoto(it.toString())
        }
    }

    // Tüm verileri silme onay diyaloğu
    if (showNukeDialog) {
        AlertDialog(
            onDismissRequest = { showNukeDialog = false },
            title = { Text("Tüm Sohbetleri Sil") },
            text = { Text("Tüm sohbetler ve mesajlar kalıcı olarak silinecektir. Bu işlem geri alınamaz.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.nukeAllData()
                    showNukeDialog = false
                }) {
                    Text("Sil", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showNukeDialog = false }) { Text("İptal") }
            },
            icon = {
                Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            }
        )
    }

    // Tema seçim diyaloğu
    if (showThemeDialog) {
        ThemeSelectionDialog(
            followSystem = followSystem,
            isDark = isDark,
            onFollowSystem = {
                viewModel.setFollowSystemTheme(true)
                showThemeDialog = false
            },
            onLight = {
                viewModel.setDarkTheme(false)
                showThemeDialog = false
            },
            onDark = {
                viewModel.setDarkTheme(true)
                showThemeDialog = false
            },
            onDismiss = { showThemeDialog = false }
        )
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Ayarlar", color = MaterialTheme.colorScheme.onSurface) },
                    navigationIcon = {
                        IconButton(onClick = onBackClick) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri", tint = MaterialTheme.colorScheme.onSurface)
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
            Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
            ) {
                // === Profil Bölümü ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp)
                        .glass(dark = dark, strong = true, shape = RoundedCornerShape(16.dp))
                ) {
                    ProfileSection(
                        displayName = viewModel.userSession.displayName ?: "",
                        phoneNumber = viewModel.userSession.phoneNumber ?: "",
                        profilePhotoUri = profilePhotoUri,
                        onPhotoClick = { photoPickerLauncher.launch("image/*") },
                        onRemovePhoto = { viewModel.updateProfilePhoto(null) }
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Tema Bölümü ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        SectionHeader("Görünüm")

                        val themeLabel = when {
                            followSystem -> "Sistemi Takip Et"
                            isDark -> "Koyu Tema"
                            else -> "Açık Tema"
                        }
                        ListItem(
                            headlineContent = { Text("Sohbet Teması") },
                            supportingContent = { Text(themeLabel) },
                            leadingContent = {
                                Icon(Icons.Default.Palette, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            modifier = Modifier.clickable { showThemeDialog = true }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Bildirimler ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        SectionHeader("Bildirimler")

                        ListItem(
                            headlineContent = { Text("Mesaj içeriğini göster") },
                            supportingContent = {
                                Text(
                                    if (showNotificationContent) "Gönderici adı ve mesaj içeriği gösterilir"
                                    else "Sadece 'Yeni mesaj' gösterilir"
                                )
                            },
                            leadingContent = {
                                Icon(Icons.Default.Notifications, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            trailingContent = {
                                Switch(
                                    checked = showNotificationContent,
                                    onCheckedChange = { viewModel.setShowNotificationContent(it) },
                                    colors = SwitchDefaults.colors(checkedTrackColor = MaterialTheme.colorScheme.primary)
                                )
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Güvenlik ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        SectionHeader("Güvenlik")

                        ListItem(
                            headlineContent = { Text("Uçtan uca şifreleme") },
                            supportingContent = { Text("Mesajlarınız Signal Protocol ile şifrelenir") },
                            leadingContent = {
                                Icon(Icons.Default.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Gizlilik ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        SectionHeader("Gizlilik")

                        ListItem(
                            headlineContent = { Text("Son görülme zamanı") },
                            supportingContent = {
                                Text(
                                    if (shareLastSeen) "Diğer kullanıcılar son görülme zamanınızı görebilir"
                                    else "Son görülme zamanınız gizli"
                                )
                            },
                            leadingContent = {
                                Icon(
                                    if (shareLastSeen) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            },
                            trailingContent = {
                                Switch(
                                    checked = shareLastSeen,
                                    onCheckedChange = { viewModel.setShareLastSeen(it) },
                                    colors = SwitchDefaults.colors(checkedTrackColor = MaterialTheme.colorScheme.primary)
                                )
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Veri Yönetimi ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        SectionHeader("Veri Yönetimi")

                        ListItem(
                            headlineContent = { Text("Mesaj saklama süresi") },
                            supportingContent = { Text("Mesajlar yalnızca bu cihazda saklanır") },
                            leadingContent = {
                                Icon(Icons.Default.DeleteSweep, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                        )

                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                            thickness = 0.5.dp,
                            modifier = Modifier.padding(horizontal = 16.dp)
                        )

                        ListItem(
                            headlineContent = { Text("Tüm Sohbetleri Sil", color = MaterialTheme.colorScheme.error) },
                            supportingContent = { Text("Tüm mesajlar ve sohbetler kalıcı olarak silinir", color = MaterialTheme.colorScheme.error.copy(alpha = 0.7f)) },
                            leadingContent = {
                                Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            modifier = Modifier.clickable { showNukeDialog = true }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Hakkında ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        SectionHeader("Hakkında")

                        ListItem(
                            headlineContent = { Text("Uygulama Versiyonu") },
                            supportingContent = { Text("1.0.0") },
                            leadingContent = {
                                Icon(Icons.Default.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

// === Profil Bölümü ===

@Composable
private fun ProfileSection(
    displayName: String,
    phoneNumber: String,
    profilePhotoUri: String?,
    onPhotoClick: () -> Unit,
    onRemovePhoto: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Avatar / profil fotoğrafı
        Box(
            modifier = Modifier.size(72.dp),
            contentAlignment = Alignment.Center
        ) {
            if (profilePhotoUri != null) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current)
                        .data(profilePhotoUri)
                        .crossfade(true)
                        .build(),
                    contentDescription = "Profil Fotoğrafı",
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .clickable { onPhotoClick() }
                )
            } else {
                GeneratedAvatar(
                    name = displayName,
                    size = 72.dp,
                    modifier = Modifier.clickable { onPhotoClick() }
                )
            }

            // Kamera ikonu
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size(26.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary)
                    .clickable { onPhotoClick() },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.CameraAlt,
                    contentDescription = "Fotoğraf Seç",
                    tint = Color.White,
                    modifier = Modifier.size(14.dp)
                )
            }
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = displayName,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onSurface,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = phoneNumber,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (profilePhotoUri != null) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Fotoğrafı Kaldır",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.clickable { onRemovePhoto() }
                )
            }
        }
    }
}

// === Tema Seçim Diyaloğu ===

@Composable
private fun ThemeSelectionDialog(
    followSystem: Boolean,
    isDark: Boolean,
    onFollowSystem: () -> Unit,
    onLight: () -> Unit,
    onDark: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Sohbet Teması") },
        text = {
            Column {
                ThemeOption(
                    icon = Icons.Default.PhoneAndroid,
                    label = "Sistemi Takip Et",
                    selected = followSystem,
                    onClick = onFollowSystem
                )
                ThemeOption(
                    icon = Icons.Default.LightMode,
                    label = "Açık Tema",
                    selected = !followSystem && !isDark,
                    onClick = onLight
                )
                ThemeOption(
                    icon = Icons.Default.DarkMode,
                    label = "Koyu Tema",
                    selected = !followSystem && isDark,
                    onClick = onDark
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Kapat") }
        }
    )
}

@Composable
private fun ThemeOption(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(vertical = 12.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(24.dp)
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
            modifier = Modifier.weight(1f)
        )
        RadioButton(
            selected = selected,
            onClick = onClick,
            colors = RadioButtonDefaults.colors(
                selectedColor = MaterialTheme.colorScheme.primary
            )
        )
    }
}

// === Yardımcı ===

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
    )
}
