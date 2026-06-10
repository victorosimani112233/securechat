package com.securechat.app.ui.screen

import android.app.Activity
import android.media.RingtoneManager
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
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Backup
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.SdStorage
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Wallpaper
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.res.stringResource
import com.securechat.app.R
import com.securechat.app.ui.components.GlassDialog
import kotlinx.coroutines.delay
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
    onBackClick: () -> Unit,
    onScheduledMessages: () -> Unit = {},
    onBackupClick: () -> Unit = {},
    onStorageUsageClick: () -> Unit = {},
    onAutoDownloadClick: () -> Unit = {},
    onAccountDeleted: () -> Unit = {},
    onNavigateToCallReadiness: () -> Unit = {}
) {
    val dark = LocalDarkTheme.current
    val profilePhotoUri by viewModel.profilePhotoUri.collectAsStateWithLifecycle()
    val followSystem by viewModel.followSystemTheme.collectAsStateWithLifecycle()
    val isDark by viewModel.isDarkTheme.collectAsStateWithLifecycle()
    val showNotificationContent by viewModel.showNotificationContent.collectAsStateWithLifecycle()
    val notificationSoundUri by viewModel.notificationSoundUri.collectAsStateWithLifecycle()
    val useDoodleBackground by viewModel.useDoodleBackground.collectAsStateWithLifecycle()
    val fullscreenMode by viewModel.fullscreenMode.collectAsStateWithLifecycle()
    val shareLastSeen by viewModel.shareLastSeen.collectAsStateWithLifecycle()
    val scheduledMessagesEnabled by viewModel.scheduledMessagesEnabled.collectAsStateWithLifecycle()
    val storageInfo by viewModel.storageInfo.collectAsStateWithLifecycle()

    // Ekran acildiginda depolama bilgisini hesapla
    LaunchedEffect(Unit) {
        viewModel.calculateStorageUsage()
    }

    var showNukeDialog by remember { mutableStateOf(false) }
    var showThemeDialog by remember { mutableStateOf(false) }
    var showLanguageDialog by remember { mutableStateOf(false) }
    var showDeleteAccountDialog by remember { mutableStateOf(false) }

    // Ayar arama — toolbar'da search ikonu toggle eder. Bos query'de orijinal layout korunur;
    // dolu query'de her ListItem `SearchableSetting` wrapper'i ile match'lendiginde gosterilir,
    // section header'lari ve eslesmeyen tum section'in glass card'i gizlenir.
    var isSettingsSearchVisible by remember { mutableStateOf(false) }
    var settingsSearchQuery by remember { mutableStateOf("") }

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

    // Bildirim sesi seçici
    val soundPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            @Suppress("DEPRECATION") // typed getParcelableExtra API 33+ — min SDK 26 destegi icin eski API
            val uri = result.data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            viewModel.setNotificationSoundUri(uri?.toString() ?: "")
        }
    }

    // Tüm verileri silme onay diyaloğu
    if (showNukeDialog) {
        AlertDialog(
            onDismissRequest = { showNukeDialog = false },
            title = { Text(stringResource(R.string.settings_nuke_dialog_title)) },
            text = { Text(stringResource(R.string.settings_nuke_dialog_body)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.nukeAllData()
                    showNukeDialog = false
                }) {
                    Text(stringResource(R.string.settings_nuke_confirm), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showNukeDialog = false }) { Text(stringResource(R.string.cancel)) }
            },
            icon = {
                Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            }
        )
    }

    // Hesap silme tamamlandiginda kayit ekranina yonlendir
    val accountDeleted by viewModel.accountDeleted.collectAsStateWithLifecycle()
    LaunchedEffect(accountDeleted) {
        if (accountDeleted) {
            onAccountDeleted()
        }
    }

    // Hesap silme onay diyalogu
    if (showDeleteAccountDialog) {
        var deleteConfirmText by remember { mutableStateOf("") }
        val isDeleteEnabled = deleteConfirmText == "SİL"
        var isDeleting by remember { mutableStateOf(false) }

        AlertDialog(
            onDismissRequest = { if (!isDeleting) showDeleteAccountDialog = false },
            title = {
                Text(
                    "Hesabı Sil",
                    color = MaterialTheme.colorScheme.error
                )
            },
            text = {
                Column {
                    // Yedekleme butonu
                    Button(
                        onClick = {
                            showDeleteAccountDialog = false
                            onBackupClick()
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = Color.White
                        ),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Icon(Icons.Default.Backup, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(stringResource(R.string.settings_nuke_backup_first), fontWeight = FontWeight.Bold)
                    }
                    Text(
                        "Silmeden önce verilerinizi yedeklemenizi öneriyoruz.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp)
                    )

                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        "Hesabınız kalıcı olarak silinecek.",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.error
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(stringResource(R.string.settings_nuke_all_data_warning))
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Bu işlem geri alınamaz.",
                        fontWeight = FontWeight.Bold
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(stringResource(R.string.settings_nuke_type_to_confirm))
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = deleteConfirmText,
                        onValueChange = { deleteConfirmText = it },
                        singleLine = true,
                        placeholder = { Text(stringResource(R.string.settings_nuke_type_placeholder)) },
                        enabled = !isDeleting,
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.colorScheme.error,
                            unfocusedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            cursorColor = MaterialTheme.colorScheme.error
                        ),
                        shape = RoundedCornerShape(8.dp)
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        isDeleting = true
                        viewModel.deleteAccount()
                    },
                    enabled = isDeleteEnabled && !isDeleting,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError
                    )
                ) {
                    if (isDeleting) {
                        androidx.compose.material3.CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            color = MaterialTheme.colorScheme.onError,
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text(if (isDeleting) "Siliniyor..." else "Hesabı Sil")
                }
            },
            dismissButton = {
                if (!isDeleting) {
                    TextButton(onClick = { showDeleteAccountDialog = false }) {
                        Text(stringResource(R.string.cancel))
                    }
                }
            },
            icon = {
                Icon(
                    Icons.Default.DeleteForever,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.error
                )
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

    // Dil seçim diyaloğu
    if (showLanguageDialog) {
        LanguageSelectionDialog(
            onLanguageSelected = { langTag ->
                val locales = if (langTag.isEmpty()) {
                    androidx.core.os.LocaleListCompat.getEmptyLocaleList()
                } else {
                    androidx.core.os.LocaleListCompat.forLanguageTags(langTag)
                }
                androidx.appcompat.app.AppCompatDelegate.setApplicationLocales(locales)
                showLanguageDialog = false
            },
            onDismiss = { showLanguageDialog = false }
        )
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.settings_title), color = MaterialTheme.colorScheme.onSurface) },
                    navigationIcon = {
                        IconButton(onClick = onBackClick) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.nav_back), tint = MaterialTheme.colorScheme.onSurface)
                        }
                    },
                    actions = {
                        IconButton(onClick = {
                            isSettingsSearchVisible = !isSettingsSearchVisible
                            if (!isSettingsSearchVisible) settingsSearchQuery = ""
                        }) {
                            Icon(
                                if (isSettingsSearchVisible) Icons.Default.Close else Icons.Default.Search,
                                contentDescription = "Ayarlarda ara",
                                tint = MaterialTheme.colorScheme.onSurface
                            )
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
                // Ayar arama bar'i — toolbar search ikonuna basinca acilir.
                AnimatedVisibility(
                    visible = isSettingsSearchVisible,
                    enter = expandVertically(),
                    exit = shrinkVertically()
                ) {
                    TextField(
                        value = settingsSearchQuery,
                        onValueChange = { settingsSearchQuery = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 4.dp)
                            .clip(RoundedCornerShape(24.dp))
                            .glass(dark = dark, shape = RoundedCornerShape(24.dp)),
                        placeholder = {
                            Text(
                                "Ayarlarda ara...",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                fontSize = 14.sp
                            )
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Search,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        },
                        trailingIcon = {
                            if (settingsSearchQuery.isNotEmpty()) {
                                IconButton(onClick = { settingsSearchQuery = "" }) {
                                    Icon(
                                        Icons.Default.Close,
                                        contentDescription = "Aramayı temizle"
                                    )
                                }
                            }
                        },
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            cursorColor = MaterialTheme.colorScheme.primary
                        ),
                        singleLine = true
                    )
                }

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
                        if (settingsSearchQuery.isBlank()) SectionHeader("Görünüm")

                        val themeLabel = when {
                            followSystem -> "Sistemi Takip Et"
                            isDark -> "Koyu Tema"
                            else -> "Açık Tema"
                        }
                        val themeTitle = stringResource(R.string.settings_chat_theme)
                        SearchableSetting(settingsSearchQuery, themeTitle, themeLabel, "Görünüm") {
                            ListItem(
                                headlineContent = { Text(themeTitle) },
                                supportingContent = { Text(themeLabel) },
                                leadingContent = {
                                    Icon(Icons.Default.Palette, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                modifier = Modifier.clickable { showThemeDialog = true }
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        // === Dil Secimi ===
                        val currentLocale = androidx.appcompat.app.AppCompatDelegate.getApplicationLocales()
                        val currentLangTag = if (currentLocale.isEmpty) "" else currentLocale.toLanguageTags()
                        val currentLangLabel = when {
                            currentLangTag.startsWith("en") -> "English"
                            currentLangTag.startsWith("de") -> "Deutsch"
                            currentLangTag.startsWith("ar") -> "العربية"
                            currentLangTag.startsWith("tr") -> "Türkçe"
                            else -> "Sistem Dili"
                        }
                        val langTitle = stringResource(R.string.settings_language)
                        SearchableSetting(settingsSearchQuery, langTitle, currentLangLabel, "dil", "language") {
                            ListItem(
                                headlineContent = { Text(langTitle) },
                                supportingContent = { Text(currentLangLabel) },
                                leadingContent = {
                                    Icon(Icons.Default.Language, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                modifier = Modifier.clickable { showLanguageDialog = true }
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        val backdropTitle = stringResource(R.string.settings_backdrop)
                        val backdropSubtitle = if (useDoodleBackground) "Doodle desenli arka plan" else "Düz renk arka plan"
                        SearchableSetting(settingsSearchQuery, backdropTitle, backdropSubtitle, "arka plan", "doodle") {
                            ListItem(
                                headlineContent = { Text(backdropTitle) },
                                supportingContent = { Text(backdropSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.Wallpaper, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                trailingContent = {
                                    Switch(
                                        checked = useDoodleBackground,
                                        onCheckedChange = { viewModel.setUseDoodleBackground(it) },
                                        colors = SwitchDefaults.colors(
                                            checkedTrackColor = MaterialTheme.colorScheme.primary,
                                            uncheckedTrackColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                                            uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            uncheckedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                        )
                                    )
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        val fullscreenTitle = stringResource(R.string.settings_fullscreen)
                        val fullscreenSubtitle = if (fullscreenMode) "Sistem navigasyon çubuğu gizli" else "Sistem navigasyon çubuğu görünür"
                        SearchableSetting(settingsSearchQuery, fullscreenTitle, fullscreenSubtitle, "tam ekran", "fullscreen") {
                            ListItem(
                                headlineContent = { Text(fullscreenTitle) },
                                supportingContent = { Text(fullscreenSubtitle) },
                                leadingContent = {
                                    Icon(
                                        if (fullscreenMode) Icons.Default.FullscreenExit else Icons.Default.Fullscreen,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                },
                                trailingContent = {
                                    Switch(
                                        checked = fullscreenMode,
                                        onCheckedChange = { viewModel.setFullscreenMode(it) },
                                        colors = SwitchDefaults.colors(
                                            checkedTrackColor = MaterialTheme.colorScheme.primary,
                                            uncheckedTrackColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                                            uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            uncheckedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                        )
                                    )
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
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
                        if (settingsSearchQuery.isBlank()) SectionHeader("Bildirimler")

                        val notifPreviewTitle = stringResource(R.string.settings_show_message_preview)
                        val notifPreviewSubtitle = if (showNotificationContent) "Gönderici adı ve mesaj içeriği gösterilir"
                            else "Sadece 'Yeni mesaj' gösterilir"
                        SearchableSetting(settingsSearchQuery, notifPreviewTitle, notifPreviewSubtitle, "bildirim", "onizleme", "preview") {
                            ListItem(
                                headlineContent = { Text(notifPreviewTitle) },
                                supportingContent = { Text(notifPreviewSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.Notifications, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                trailingContent = {
                                    Switch(
                                        checked = showNotificationContent,
                                        onCheckedChange = { viewModel.setShowNotificationContent(it) },
                                        colors = SwitchDefaults.colors(
                                            checkedTrackColor = MaterialTheme.colorScheme.primary,
                                            uncheckedTrackColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                                            uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            uncheckedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                        )
                                    )
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        // RingtoneManager.getRingtone() + getTitle() disk I/O yapar — ana
                        // thread'de composition icinde calistirilirsa SettingsScreen'e gecis
                        // animasyonunda donmaya yol acar. produceState ile IO dispatcher'a tasiyoruz;
                        // baslangic degeri "Varsayilan", sonra arka planda gercek isim resolve edilir.
                        val soundLabel by androidx.compose.runtime.produceState(
                            initialValue = "Varsayılan",
                            notificationSoundUri
                        ) {
                            if (notificationSoundUri.isEmpty()) {
                                value = "Varsayılan"
                                return@produceState
                            }
                            value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                                try {
                                    RingtoneManager.getRingtone(context, Uri.parse(notificationSoundUri))
                                        ?.getTitle(context) ?: "Varsayılan"
                                } catch (_: Exception) { "Varsayılan" }
                            }
                        }

                        // Ses onizleme icin MediaPlayer durumu
                        var isPlayingPreview by remember { mutableStateOf(false) }
                        val mediaPlayerRef = remember { mutableStateOf<android.media.MediaPlayer?>(null) }

                        // Composable'dan cikildiginda MediaPlayer'i serbest birak
                        DisposableEffect(Unit) {
                            onDispose {
                                mediaPlayerRef.value?.let { mp ->
                                    try {
                                        if (mp.isPlaying) mp.stop()
                                        mp.release()
                                    } catch (_: Exception) { }
                                }
                                mediaPlayerRef.value = null
                            }
                        }

                        val soundTitle = stringResource(R.string.settings_notification_sound)
                        SearchableSetting(settingsSearchQuery, soundTitle, soundLabel, "bildirim sesi", "ses", "sound", "ringtone") {
                        ListItem(
                            headlineContent = { Text(soundTitle) },
                            supportingContent = { Text(soundLabel) },
                            leadingContent = {
                                Icon(Icons.Default.MusicNote, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            },
                            trailingContent = {
                                // Ses onizleme butonu
                                IconButton(
                                    onClick = {
                                        if (isPlayingPreview) {
                                            // Onceki calan sesi durdur
                                            mediaPlayerRef.value?.let { mp ->
                                                try {
                                                    if (mp.isPlaying) mp.stop()
                                                    mp.release()
                                                } catch (_: Exception) { }
                                            }
                                            mediaPlayerRef.value = null
                                            isPlayingPreview = false
                                        } else {
                                            // Secili sesi cal
                                            try {
                                                val soundUri = if (notificationSoundUri.isNotEmpty()) {
                                                    Uri.parse(notificationSoundUri)
                                                } else {
                                                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                                                }
                                                val mp = android.media.MediaPlayer().apply {
                                                    setDataSource(context, soundUri)
                                                    setAudioAttributes(
                                                        android.media.AudioAttributes.Builder()
                                                            .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                                                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                                            .build()
                                                    )
                                                    setOnCompletionListener {
                                                        isPlayingPreview = false
                                                        it.release()
                                                        mediaPlayerRef.value = null
                                                    }
                                                    prepare()
                                                    start()
                                                }
                                                mediaPlayerRef.value = mp
                                                isPlayingPreview = true
                                            } catch (e: Exception) {
                                                android.util.Log.w("SettingsScreen", "Ses onizleme basarisiz: ${e.message}")
                                                isPlayingPreview = false
                                            }
                                        }
                                    }
                                ) {
                                    Icon(
                                        if (isPlayingPreview) Icons.Default.Stop else Icons.Default.PlayArrow,
                                        contentDescription = if (isPlayingPreview) "Durdur" else "Dinle",
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            modifier = Modifier.clickable {
                                // Ses onizleme caliyorsa durdur
                                mediaPlayerRef.value?.let { mp ->
                                    try {
                                        if (mp.isPlaying) mp.stop()
                                        mp.release()
                                    } catch (_: Exception) { }
                                }
                                mediaPlayerRef.value = null
                                isPlayingPreview = false

                                val intent = android.content.Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                                    putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_NOTIFICATION)
                                    putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Bildirim Sesi Seçin")
                                    putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                                    putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
                                    if (notificationSoundUri.isNotEmpty()) {
                                        putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(notificationSoundUri))
                                    }
                                }
                                soundPickerLauncher.launch(intent)
                            }
                        )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Arama ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        if (settingsSearchQuery.isBlank()) SectionHeader("Arama")

                        val canDrawOverlays = remember {
                            android.provider.Settings.canDrawOverlays(context)
                        }

                        val incomingCallTitle = stringResource(R.string.settings_incoming_call_screen)
                        val incomingCallSubtitle = if (canDrawOverlays) "Arama geldiğinde tam ekran açılır"
                            else "İzin ver — arama geldiğinde ekran açılsın"
                        SearchableSetting(settingsSearchQuery, incomingCallTitle, incomingCallSubtitle, "arama", "tam ekran") {
                            ListItem(
                                headlineContent = { Text(incomingCallTitle) },
                                supportingContent = { Text(incomingCallSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.PhoneAndroid, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                trailingContent = {
                                    if (!canDrawOverlays) {
                                        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                    }
                                },
                                modifier = Modifier.clickable {
                                    if (!canDrawOverlays) {
                                        val intent = android.content.Intent(
                                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                            android.net.Uri.parse("package:${context.packageName}")
                                        )
                                        context.startActivity(intent)
                                    }
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        // Aramaları kaçırma — kapsamlı izin yönetim ekranı.
                        // CallReadinessHelper.currentState() permission check + bircok sistem call yapar;
                        // ilk composition'da main-thread'i bloklayip transition jank'ina sebep oluyor.
                        // produceState ile IO'ya tasiyip baslangic state'i "tum izinler verildi varsayilan"
                        // ile composition'a hizli giriyoruz.
                        val missedCallTitle = stringResource(R.string.settings_missed_call)
                        val missedCallAllGranted by androidx.compose.runtime.produceState(
                            initialValue = true
                        ) {
                            value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                                com.securechat.app.util.CallReadinessHelper.currentState(context).allGranted
                            }
                        }
                        val missedCallSubtitle = if (missedCallAllGranted) "Tüm izinler verildi"
                            else "Aramaların gerçek zamanlı gelmesi için ayarları kontrol et"
                        SearchableSetting(settingsSearchQuery, missedCallTitle, missedCallSubtitle, "arama", "kacirma", "izin") {
                            ListItem(
                                headlineContent = { Text(missedCallTitle) },
                                supportingContent = { Text(missedCallSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.PhoneAndroid, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                trailingContent = {
                                    Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                modifier = Modifier.clickable {
                                    onNavigateToCallReadiness()
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        // Pil optimizasyonu — BatteryOptimizationHelper.isIgnoring PowerManager
                        // sorgu yapar; ilk composition'da main thread'i bloklamasin diye initial
                        // state "true" (en az alarm dolu) ve LaunchedEffect ile asenkron resolve.
                        var batteryOptimized by remember { mutableStateOf(true) }
                        androidx.compose.runtime.DisposableEffect(Unit) {
                            val lifecycleOwner = (context as? androidx.lifecycle.LifecycleOwner)
                            val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
                                if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                                    // ON_RESUME zaten arka planda calisir, dogrudan oku.
                                    batteryOptimized = com.securechat.app.util.BatteryOptimizationHelper.isIgnoring(context)
                                }
                            }
                            lifecycleOwner?.lifecycle?.addObserver(observer)
                            onDispose { lifecycleOwner?.lifecycle?.removeObserver(observer) }
                        }
                        // Ilk durumu IO'da resolve et — main thread'i bloklamadan
                        LaunchedEffect(Unit) {
                            batteryOptimized = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                                com.securechat.app.util.BatteryOptimizationHelper.isIgnoring(context)
                            }
                        }
                        val batteryTitle = stringResource(R.string.settings_battery_optimization)
                        val batterySubtitle = if (batteryOptimized) "Kapalı — aramalar gerçek zamanlı gelir"
                            else "Açık — kapat ki kapalı uygulamada aramalar geç gelmesin"
                        SearchableSetting(settingsSearchQuery, batteryTitle, batterySubtitle, "pil", "battery", "optimizasyon") {
                            ListItem(
                                headlineContent = { Text(batteryTitle) },
                                supportingContent = { Text(batterySubtitle) },
                                leadingContent = {
                                    Icon(
                                        Icons.Default.BatteryFull,
                                        contentDescription = null,
                                        tint = if (batteryOptimized) MaterialTheme.colorScheme.primary
                                               else MaterialTheme.colorScheme.error
                                    )
                                },
                                trailingContent = {
                                    if (!batteryOptimized) {
                                        Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                    } else {
                                        Icon(Icons.Default.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                    }
                                },
                                modifier = Modifier.clickable {
                                    if (!batteryOptimized) {
                                        com.securechat.app.util.BatteryOptimizationHelper.requestExemption(context)
                                    }
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Planlı Mesajlar ===
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        if (settingsSearchQuery.isBlank()) SectionHeader("Planlı Mesajlar")

                        val schedToggleTitle = stringResource(R.string.settings_scheduled_messages)
                        val schedToggleSubtitle = if (scheduledMessagesEnabled) "Planlı mesajlar aktif" else "Planlı mesajlar devre dışı"
                        SearchableSetting(settingsSearchQuery, schedToggleTitle, schedToggleSubtitle, "planli mesaj", "scheduled") {
                            ListItem(
                                headlineContent = { Text(schedToggleTitle) },
                                supportingContent = { Text(schedToggleSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.EditCalendar, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                trailingContent = {
                                    Switch(
                                        checked = scheduledMessagesEnabled,
                                        onCheckedChange = { viewModel.setScheduledMessagesEnabled(it) },
                                        colors = SwitchDefaults.colors(
                                            checkedTrackColor = MaterialTheme.colorScheme.primary,
                                            uncheckedTrackColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                                            uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            uncheckedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                        )
                                    )
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        val schedManageTitle = stringResource(R.string.settings_manage_scheduled)
                        val schedManageSubtitle = stringResource(R.string.settings_manage_scheduled_desc)
                        SearchableSetting(settingsSearchQuery, schedManageTitle, schedManageSubtitle, "planli mesaj") {
                            ListItem(
                                headlineContent = { Text(schedManageTitle) },
                                supportingContent = { Text(schedManageSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.EditCalendar, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                trailingContent = {
                                    Icon(
                                        Icons.AutoMirrored.Filled.ArrowForward,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                                        modifier = Modifier.size(20.dp)
                                    )
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                modifier = Modifier.clickable { onScheduledMessages() }
                            )
                        }
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
                        if (settingsSearchQuery.isBlank()) SectionHeader("Güvenlik")

                        val e2eeTitle = stringResource(R.string.settings_e2ee)
                        val e2eeSubtitle = stringResource(R.string.settings_e2ee_desc)
                        SearchableSetting(settingsSearchQuery, e2eeTitle, e2eeSubtitle, "uctan uca", "e2ee", "guvenlik", "sifreleme") {
                            ListItem(
                                headlineContent = { Text(e2eeTitle) },
                                supportingContent = { Text(e2eeSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
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
                        if (settingsSearchQuery.isBlank()) SectionHeader("Gizlilik")

                        val lastSeenTitle = stringResource(R.string.settings_last_seen)
                        val lastSeenSubtitle = if (shareLastSeen) "Diğer kullanıcılar son görülme zamanınızı görebilir"
                            else "Son görülme zamanınız gizli"
                        SearchableSetting(settingsSearchQuery, lastSeenTitle, lastSeenSubtitle, "son gorulme", "gizlilik", "last seen") {
                            ListItem(
                                headlineContent = { Text(lastSeenTitle) },
                                supportingContent = { Text(lastSeenSubtitle) },
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
                                        colors = SwitchDefaults.colors(
                                            checkedTrackColor = MaterialTheme.colorScheme.primary,
                                            uncheckedTrackColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                                            uncheckedThumbColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                                            uncheckedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                        )
                                    )
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent)
                            )
                        }
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
                        if (settingsSearchQuery.isBlank()) SectionHeader("Veri Yönetimi")

                        val msgStorageTitle = stringResource(R.string.settings_message_storage)
                        val msgStorageSubtitle = stringResource(R.string.settings_message_storage_desc)
                        SearchableSetting(settingsSearchQuery, msgStorageTitle, msgStorageSubtitle, "mesaj saklama", "depolama") {
                            ListItem(
                                headlineContent = { Text(msgStorageTitle) },
                                supportingContent = { Text(msgStorageSubtitle) },
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
                        }

                        val backupTitle = stringResource(R.string.settings_backup)
                        val backupSubtitle = stringResource(R.string.settings_backup_desc)
                        SearchableSetting(settingsSearchQuery, backupTitle, backupSubtitle, "yedek", "backup", "geri yukle") {
                            ListItem(
                                headlineContent = { Text(backupTitle) },
                                supportingContent = { Text(backupSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.Backup, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                modifier = Modifier.clickable { onBackupClick() }
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        // Depolama bilgisi — tiklaninca per-chat detay ekranina gider
                        storageInfo?.let { info ->
                            val storageUsageTitle = stringResource(R.string.settings_storage_usage)
                            val storageUsageSubtitle = "Toplam: ${formatStorageSize(info.totalSize)}"
                            SearchableSetting(settingsSearchQuery, storageUsageTitle, storageUsageSubtitle, "depolama", "kullanim") {
                                ListItem(
                                    headlineContent = { Text(storageUsageTitle) },
                                    supportingContent = {
                                        Column {
                                            Text("Toplam: ${formatStorageSize(info.totalSize)}")
                                            Text(
                                                "Veritabani: ${formatStorageSize(info.dbSize)} | " +
                                                "Onbellek: ${formatStorageSize(info.cacheSize)} | " +
                                                "Dosyalar: ${formatStorageSize(info.filesSize)}",
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant
                                            )
                                        }
                                    },
                                    leadingContent = {
                                        Icon(Icons.Default.SdStorage, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                    },
                                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                    modifier = Modifier.clickable { onStorageUsageClick() }
                                )
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                    thickness = 0.5.dp,
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
                            }

                            // Onbellek temizleme butonu
                            val cacheTitle = "Onbellegi Temizle"
                            val cacheSubtitle = "Onbellek: ${formatStorageSize(info.cacheSize)}"
                            SearchableSetting(settingsSearchQuery, cacheTitle, cacheSubtitle, "onbellek", "cache", "temizle") {
                                ListItem(
                                    headlineContent = { Text(cacheTitle) },
                                    supportingContent = { Text(cacheSubtitle) },
                                    leadingContent = {
                                        Icon(Icons.Default.CleaningServices, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                    },
                                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                    modifier = Modifier.clickable { viewModel.clearCache() }
                                )
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                    thickness = 0.5.dp,
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
                            }

                            // Otomatik indirme ayarlari
                            val autoDlTitle = "Otomatik İndirme"
                            val autoDlSubtitle = "Wi-Fi ve hücresel veride medya indirme kuralları"
                            SearchableSetting(settingsSearchQuery, autoDlTitle, autoDlSubtitle, "indirme", "download", "medya") {
                                ListItem(
                                    headlineContent = { Text(autoDlTitle) },
                                    supportingContent = {
                                        Text(
                                            autoDlSubtitle,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    },
                                    leadingContent = {
                                        Icon(
                                            Icons.Default.Download,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary
                                        )
                                    },
                                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                    modifier = Modifier.clickable { onAutoDownloadClick() }
                                )
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                    thickness = 0.5.dp,
                                    modifier = Modifier.padding(horizontal = 16.dp)
                                )
                            }
                        }

                        val nukeTitle = stringResource(R.string.settings_nuke_dialog_title)
                        val nukeSubtitle = "Tüm mesajlar ve sohbetler kalıcı olarak silinir"
                        SearchableSetting(settingsSearchQuery, nukeTitle, nukeSubtitle, "sil", "temizle", "nuke") {
                            ListItem(
                                headlineContent = { Text(nukeTitle, color = MaterialTheme.colorScheme.error) },
                                supportingContent = { Text(nukeSubtitle, color = MaterialTheme.colorScheme.error.copy(alpha = 0.7f)) },
                                leadingContent = {
                                    Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                modifier = Modifier.clickable { showNukeDialog = true }
                            )
                            HorizontalDivider(
                                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                thickness = 0.5.dp,
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        val deleteAccTitle = "Hesabı Sil"
                        val deleteAccSubtitle = "Hesabınız ve tüm verileriniz kalıcı olarak silinir"
                        SearchableSetting(settingsSearchQuery, deleteAccTitle, deleteAccSubtitle, "hesap sil", "delete account") {
                            ListItem(
                                headlineContent = { Text(deleteAccTitle, color = MaterialTheme.colorScheme.error) },
                                supportingContent = { Text(deleteAccSubtitle, color = MaterialTheme.colorScheme.error.copy(alpha = 0.7f)) },
                                leadingContent = {
                                    Icon(Icons.Default.DeleteForever, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                modifier = Modifier.clickable { showDeleteAccountDialog = true }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))

                // === Hakkında ===
                var versionTapCount by remember { mutableIntStateOf(0) }
                var showEasterEgg by remember { mutableStateOf(false) }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                        .glass(dark = dark, shape = RoundedCornerShape(16.dp))
                ) {
                    Column {
                        if (settingsSearchQuery.isBlank()) SectionHeader("Hakkında")

                        val versionTitle = "Uygulama Versiyonu"
                        val versionSubtitle = com.securechat.app.BuildConfig.VERSION_NAME
                        SearchableSetting(settingsSearchQuery, versionTitle, versionSubtitle, "versiyon", "version", "hakkinda") {
                            ListItem(
                                headlineContent = { Text(versionTitle) },
                                supportingContent = { Text(versionSubtitle) },
                                leadingContent = {
                                    Icon(Icons.Default.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                },
                                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                                modifier = Modifier.clickable {
                                    if (!showEasterEgg) {
                                        versionTapCount++
                                        if (versionTapCount >= 5) {
                                            showEasterEgg = true
                                            versionTapCount = 0
                                        }
                                    }
                                }
                            )
                        }
                    }
                }

                // Easter egg popup
                if (showEasterEgg) {
                    var dismissTriggered by remember { mutableStateOf(false) }
                    LaunchedEffect(Unit) {
                        delay(3000)
                        dismissTriggered = true
                    }
                    if (dismissTriggered) {
                        showEasterEgg = false
                    } else {
                        GlassDialog(onDismissRequest = { showEasterEgg = false }) {
                            val infiniteTransition = rememberInfiniteTransition(label = "blink")
                            val alpha by infiniteTransition.animateFloat(
                                initialValue = 1f,
                                targetValue = 0.1f,
                                animationSpec = infiniteRepeatable(
                                    animation = tween(400),
                                    repeatMode = RepeatMode.Reverse
                                ),
                                label = "blinkAlpha"
                            )
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 32.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    text = "güçcük whatsapp",
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary.copy(alpha = alpha),
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    }
                }

                // Alt navigasyon barinin arkasinda kalmamasi icin ekstra bosluk
                Spacer(modifier = Modifier.height(100.dp))
            }
        }
    }
}

/**
 * Ayar arama wrapper'i — query bossa veya title/subtitle/sectionTitle bunu iceriyorsa
 * icerigi render eder; aksi takdirde gizlenir. Section header'lari bu helper ile yerine
 * `if (query.isBlank())` ile koklenir.
 *
 * vararg matchTexts: title, subtitle, ek anahtar kelimeler — hepsi case-insensitive.
 */
@Composable
private fun SearchableSetting(
    query: String,
    vararg matchTexts: String?,
    content: @Composable () -> Unit
) {
    val q = query.trim()
    val visible = q.isBlank() || matchTexts.any {
        it != null && it.contains(q, ignoreCase = true)
    }
    if (visible) content()
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
        title = { Text(stringResource(R.string.settings_chat_theme)) },
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

/**
 * Dil seçim diyaloğu — AppCompatDelegate.setApplicationLocales kullanır.
 * Android 13+ native per-app locale, oncesinde compat fallback.
 */
@Composable
private fun LanguageSelectionDialog(
    onLanguageSelected: (langTag: String) -> Unit,
    onDismiss: () -> Unit
) {
    val current = androidx.appcompat.app.AppCompatDelegate.getApplicationLocales()
    val currentTag = if (current.isEmpty) "" else current.toLanguageTags().substringBefore("-")

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Dil Seçimi") },
        text = {
            Column {
                LanguageOption(
                    label = "Sistem Dili",
                    selected = currentTag.isEmpty(),
                    onClick = { onLanguageSelected("") }
                )
                LanguageOption(
                    label = "Türkçe",
                    selected = currentTag == "tr",
                    onClick = { onLanguageSelected("tr") }
                )
                LanguageOption(
                    label = "English",
                    selected = currentTag == "en",
                    onClick = { onLanguageSelected("en") }
                )
                LanguageOption(
                    label = "Deutsch",
                    selected = currentTag == "de",
                    onClick = { onLanguageSelected("de") }
                )
                LanguageOption(
                    label = "العربية",
                    selected = currentTag == "ar",
                    onClick = { onLanguageSelected("ar") }
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("Kapat") }
        }
    )
}

@Composable
private fun LanguageOption(
    label: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp, horizontal = 8.dp),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
    ) {
        androidx.compose.material3.RadioButton(
            selected = selected,
            onClick = onClick
        )
        Spacer(Modifier.width(8.dp))
        Text(text = label, style = MaterialTheme.typography.bodyLarge)
    }
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
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
    )
}

/** Dosya boyutunu okunabilir formata cevirir (B/KB/MB/GB). */
private fun formatStorageSize(bytes: Long): String {
    return when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> "${bytes / 1024} KB"
        bytes < 1024 * 1024 * 1024 -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
        else -> String.format("%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
    }
}
