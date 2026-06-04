package com.securechat.app.ui.screen

import android.content.Intent
import android.media.RingtoneManager
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.StickyNote2
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.viewmodel.ChatInfoViewModel
import com.securechat.storage.entity.MessageEntity
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.theme.MonoFamily
import com.securechat.app.ui.theme.DisplayFamily
import kotlin.math.abs

private val AZ_AVATAR_COLORS = listOf(
    Color(0xFF3E7BFA), Color(0xFF6B737D), Color(0xFF8A929C),
    Color(0xFF5D6570), Color(0xFF4A535E), Color(0xFF9BA3AE),
)

/**
 * WhatsApp benzeri sohbet bilgileri ekranı.
 * Kişi bilgileri, telefon numarası, medyalar, dokümanlar, yıldızlı mesajlar,
 * arama, kişiye not ve kişiye özel bildirim sesi seçimi.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatInfoScreen(
    conversationId: String,
    viewModel: ChatInfoViewModel = hiltViewModel(),
    onBackClick: () -> Unit,
    onMessageClick: (String) -> Unit,
    onMediaClick: (MessageEntity) -> Unit,
    onSendMessageClick: (String) -> Unit = {}
) {
    val conversationName by viewModel.conversationName.collectAsStateWithLifecycle()
    val phoneNumber by viewModel.phoneNumber.collectAsStateWithLifecycle()
    val contactNote by viewModel.contactNote.collectAsStateWithLifecycle()
    val customNotificationUri by viewModel.customNotificationUri.collectAsStateWithLifecycle()
    val isGroup by viewModel.isGroup.collectAsStateWithLifecycle()
    val canStartConversation by viewModel.canStartConversation.collectAsStateWithLifecycle()
    val mediaMessages by viewModel.mediaMessages.collectAsStateWithLifecycle()
    val documentMessages by viewModel.documentMessages.collectAsStateWithLifecycle()
    val starredMessages by viewModel.starredMessages.collectAsStateWithLifecycle()
    val searchResults by viewModel.searchResults.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val disappearingDuration by viewModel.disappearingDuration.collectAsStateWithLifecycle()
    val isMuted by viewModel.isMuted.collectAsStateWithLifecycle()
    val isLocked by viewModel.isLocked.collectAsStateWithLifecycle()

    val context = LocalContext.current
    var currentTab by remember { mutableStateOf(ChatInfoTab.MAIN) }
    var searchQuery by remember { mutableStateOf("") }
    var showNoteDialog by remember { mutableStateOf(false) }
    var showDisappearingDialog by remember { mutableStateOf(false) }

    // Ringtone picker launcher
    val ringtoneLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        @Suppress("DEPRECATION")
        val uri = result.data?.getParcelableExtra<android.net.Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        viewModel.updateCustomNotification(uri?.toString())
    }

    // ViewModel'i initialize et
    viewModel.initialize(conversationId)

    val dark = LocalDarkTheme.current

    // Not ekleme dialogu
    if (showNoteDialog) {
        NoteDialog(
            currentNote = contactNote ?: "",
            onDismiss = { showNoteDialog = false },
            onSave = { note ->
                viewModel.updateContactNote(note)
                showNoteDialog = false
            }
        )
    }

    // Süreli mesaj dialog
    if (showDisappearingDialog) {
        DisappearingTimerDialog(
            currentDuration = disappearingDuration,
            onDurationSelected = { duration ->
                viewModel.setDisappearingDuration(duration)
                showDisappearingDialog = false
            },
            onDismiss = { showDisappearingDialog = false }
        )
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when (currentTab) {
                            ChatInfoTab.MAIN -> "Kişi Bilgileri"
                            ChatInfoTab.SEARCH -> "Sohbette Ara"
                            ChatInfoTab.STARRED -> "Yıldızlı Mesajlar"
                            ChatInfoTab.MEDIA -> "Medya"
                            ChatInfoTab.DOCUMENTS -> "Dokümanlar"
                        },
                        color = MaterialTheme.colorScheme.onSurface
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (currentTab == ChatInfoTab.MAIN) {
                            onBackClick()
                        } else {
                            currentTab = ChatInfoTab.MAIN
                            searchQuery = ""
                            viewModel.clearSearch()
                        }
                    }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Geri",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onSurface
                ),
                windowInsets = WindowInsets(0)
            )
        },
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0)
    ) { padding ->
        when (currentTab) {
            ChatInfoTab.MAIN -> {
                MainInfoContent(
                    modifier = Modifier.padding(padding),
                    peerName = conversationName,
                    phoneNumber = phoneNumber,
                    isGroup = isGroup,
                    canStartConversation = canStartConversation,
                    onStartConversationClick = {
                        // ViewModel conversation entity'i (yoksa) olusturur, sonra navigate.
                        viewModel.openConversation { peerId -> onSendMessageClick(peerId) }
                    },
                    contactNote = contactNote,
                    customNotificationUri = customNotificationUri,
                    disappearingDuration = disappearingDuration,
                    mediaCount = mediaMessages.size,
                    documentCount = documentMessages.size,
                    starredCount = starredMessages.size,
                    onSearchClick = { currentTab = ChatInfoTab.SEARCH },
                    onStarredClick = { currentTab = ChatInfoTab.STARRED },
                    onMediaClick = { currentTab = ChatInfoTab.MEDIA },
                    onDocumentsClick = { currentTab = ChatInfoTab.DOCUMENTS },
                    onNoteClick = { showNoteDialog = true },
                    onDisappearingClick = { showDisappearingDialog = true },
                    onNotificationClick = {
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_NOTIFICATION)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Bildirim Sesi Seç")
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            if (customNotificationUri != null) {
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                                    android.net.Uri.parse(customNotificationUri)
                                )
                            }
                        }
                        ringtoneLauncher.launch(intent)
                    },
                    isMuted = isMuted,
                    onMuteToggle = { viewModel.toggleMuted() },
                    isLocked = isLocked,
                    onLockToggle = { viewModel.toggleLocked() },
                    onAddContactClick = {
                        val addContactIntent = Intent(ContactsContract.Intents.Insert.ACTION).apply {
                            type = ContactsContract.RawContacts.CONTENT_TYPE
                            putExtra(ContactsContract.Intents.Insert.NAME, conversationName)
                            putExtra(ContactsContract.Intents.Insert.PHONE, phoneNumber)
                        }
                        context.startActivity(addContactIntent)
                    }
                )
            }
            ChatInfoTab.SEARCH -> {
                SearchContent(
                    modifier = Modifier.padding(padding),
                    searchQuery = searchQuery,
                    onSearchQueryChange = {
                        searchQuery = it
                        viewModel.searchMessages(it)
                    },
                    searchResults = searchResults,
                    isLoading = isLoading,
                    onMessageClick = onMessageClick
                )
            }
            ChatInfoTab.STARRED -> {
                StarredMessagesContent(
                    modifier = Modifier.padding(padding),
                    starredMessages = starredMessages,
                    isLoading = isLoading,
                    onMessageClick = onMessageClick
                )
            }
            ChatInfoTab.MEDIA -> {
                MediaContent(
                    modifier = Modifier.padding(padding),
                    mediaMessages = mediaMessages,
                    isLoading = isLoading,
                    onMediaClick = onMediaClick
                )
            }
            ChatInfoTab.DOCUMENTS -> {
                DocumentsContent(
                    modifier = Modifier.padding(padding),
                    documentMessages = documentMessages,
                    isLoading = isLoading,
                    onDocumentClick = onMediaClick
                )
            }
        }
    }
    } // Box
}

enum class ChatInfoTab {
    MAIN, SEARCH, STARRED, MEDIA, DOCUMENTS
}

// --- Not Ekleme Dialogu ---

@Composable
private fun NoteDialog(
    currentNote: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    var noteText by remember { mutableStateOf(currentNote) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                "Kişiye Not Ekle",
                color = MaterialTheme.colorScheme.onSurface
            )
        },
        text = {
            OutlinedTextField(
                value = noteText,
                onValueChange = { noteText = it },
                label = { Text("Not") },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 5,
                shape = RoundedCornerShape(12.dp)
            )
        },
        confirmButton = {
            TextButton(onClick = { onSave(noteText) }) {
                Text("Kaydet", color = MaterialTheme.colorScheme.primary)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("İptal", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        containerColor = MaterialTheme.colorScheme.surface,
        titleContentColor = MaterialTheme.colorScheme.onSurface,
        textContentColor = MaterialTheme.colorScheme.onSurface
    )
}

// --- Ana Info Ekranı ---

@Composable
private fun MainInfoContent(
    modifier: Modifier = Modifier,
    peerName: String,
    phoneNumber: String,
    isGroup: Boolean,
    canStartConversation: Boolean = false,
    onStartConversationClick: () -> Unit = {},
    contactNote: String?,
    customNotificationUri: String?,
    disappearingDuration: Long,
    mediaCount: Int,
    documentCount: Int,
    starredCount: Int,
    onSearchClick: () -> Unit,
    onStarredClick: () -> Unit,
    onMediaClick: () -> Unit,
    onDocumentsClick: () -> Unit,
    onNoteClick: () -> Unit,
    onDisappearingClick: () -> Unit,
    onNotificationClick: () -> Unit,
    isMuted: Boolean = false,
    onMuteToggle: () -> Unit = {},
    isLocked: Boolean = false,
    onLockToggle: () -> Unit = {},
    onAddContactClick: () -> Unit = {}
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        // Profil bilgileri — avatar, isim, numara
        item {
            ProfileHeader(
                peerName = peerName,
                phoneNumber = phoneNumber,
                isGroup = isGroup
            )
        }

        item { SectionDivider() }

        // Mesaj gonder — sadece kisi (grup degil) ve kendi UUID'imiz degilse.
        // Grup info'dan rehberde olmayan uyenin profiline gecince burada gorunur:
        // tiklayinca ChatInfoViewModel lokal conversation entity'i (yoksa) olusturur
        // ve route /chat/$peerId'a yonlendirme yapar.
        if (canStartConversation) {
            item {
                InfoMenuItem(
                    icon = Icons.AutoMirrored.Filled.Chat,
                    iconTint = Color(0xFF128C7E),
                    title = "Mesaj Gönder",
                    subtitle = "Bu kişiyle sohbet başlat",
                    onClick = onStartConversationClick
                )
            }
        }

        // Menü öğeleri
        item {
            InfoMenuItem(
                icon = Icons.Default.Search,
                title = "Sohbette Ara",
                subtitle = "Mesajlarda arama yap",
                onClick = onSearchClick
            )
        }

        item {
            InfoMenuItem(
                icon = Icons.Default.Image,
                title = "Medya",
                subtitle = if (mediaCount > 0) "$mediaCount medya" else "Medya yok",
                onClick = onMediaClick
            )
        }

        item {
            InfoMenuItem(
                icon = Icons.Default.Description,
                title = "Dokümanlar",
                subtitle = if (documentCount > 0) "$documentCount doküman" else "Doküman yok",
                onClick = onDocumentsClick
            )
        }

        item {
            InfoMenuItem(
                icon = Icons.Default.Star,
                iconTint = Color(0xFFFFD700),
                title = "Yıldızlı Mesajlar",
                subtitle = if (starredCount > 0) "$starredCount mesaj" else "Yıldızlı mesaj yok",
                onClick = onStarredClick
            )
        }

        item { SectionDivider() }

        // Süreli mesajlar
        item {
            InfoMenuItem(
                icon = Icons.Default.Schedule,
                iconTint = Color(0xFF00897B),
                title = "Süreli Mesajlar",
                subtitle = formatDisappearingLabel(disappearingDuration),
                onClick = onDisappearingClick
            )
        }

        // Kişiye not
        item {
            InfoMenuItem(
                icon = Icons.AutoMirrored.Filled.StickyNote2,
                iconTint = Color(0xFF66BB6A),
                title = "Kişiye Not",
                subtitle = contactNote ?: "Not eklemek için dokun",
                onClick = onNoteClick
            )
        }

        // Sessize al
        item {
            InfoMenuItem(
                icon = if (isMuted) Icons.Default.NotificationsOff else Icons.Default.Notifications,
                iconTint = if (isMuted) MaterialTheme.colorScheme.error else Color(0xFF66BB6A),
                title = if (isMuted) "Sessizde" else "Sesli",
                subtitle = if (isMuted) "Bildirimler kapalı" else "Bildirimler açık",
                onClick = onMuteToggle
            )
        }

        // Biyometrik kilit
        item {
            InfoMenuItem(
                icon = if (isLocked) Icons.Default.Lock else Icons.Default.LockOpen,
                iconTint = if (isLocked) MaterialTheme.colorScheme.primary else Color(0xFF78909C),
                title = if (isLocked) "Sohbet Kilitli" else "Sohbet Kilidi",
                subtitle = if (isLocked) "Biyometrik doğrulama açık" else "Biyometrik kilit ekle",
                onClick = onLockToggle
            )
        }

        // Kişiye özel bildirim
        item {
            val context = LocalContext.current
            val notifLabel = if (customNotificationUri != null) {
                try {
                    val ringtone = RingtoneManager.getRingtone(
                        context,
                        android.net.Uri.parse(customNotificationUri)
                    )
                    ringtone?.getTitle(context) ?: "Özel bildirim sesi"
                } catch (_: Exception) {
                    "Özel bildirim sesi"
                }
            } else {
                "Varsayılan"
            }

            InfoMenuItem(
                icon = Icons.Default.Notifications,
                iconTint = Color(0xFF42A5F5),
                title = "Özel Bildirim Sesi",
                subtitle = notifLabel,
                onClick = onNotificationClick
            )
        }

        // Rehbere ekle — sadece kişi sohbetlerinde gösterilir
        if (!isGroup && phoneNumber.isNotBlank()) {
            item { SectionDivider() }
            item {
                InfoMenuItem(
                    icon = Icons.Default.PersonAdd,
                    iconTint = Color(0xFF26A69A),
                    title = "Rehbere Ekle",
                    subtitle = "Bu kişiyi telefon rehberine ekle",
                    onClick = onAddContactClick
                )
            }
        }

        item { Spacer(modifier = Modifier.height(32.dp)) }
    }
}

// --- Profil Başlığı ---

@Composable
private fun ProfileHeader(
    peerName: String,
    phoneNumber: String,
    isGroup: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp, horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // 104dp avatar — insan silueti (WhatsApp tarzi)
        GeneratedAvatar(
            name = peerName,
            isGroup = isGroup,
            size = 104.dp
        )

        Spacer(modifier = Modifier.height(16.dp))

        // İsim — headlineMedium
        Text(
            text = peerName,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center
        )

        // Telefon numarası — uzun basarak kopyalanabilir
        if (!isGroup && phoneNumber.isNotBlank()) {
            Spacer(modifier = Modifier.height(4.dp))
            val clipboardManager = LocalClipboardManager.current
            val context = LocalContext.current
            @OptIn(ExperimentalFoundationApi::class)
            Text(
                text = formatPhoneDisplay(phoneNumber),
                fontFamily = MonoFamily,
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.combinedClickable(
                    onClick = { },
                    onLongClick = {
                        clipboardManager.setText(AnnotatedString(phoneNumber))
                        android.widget.Toast.makeText(context, "Numara kopyalandı", android.widget.Toast.LENGTH_SHORT).show()
                    }
                )
            )
            Text(
                text = "Kopyalamak için uzun basın",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                textAlign = TextAlign.Center,
                fontSize = 10.sp
            )
        }
    }
}

// --- Menü Öğesi ---

@Composable
private fun InfoMenuItem(
    icon: ImageVector,
    title: String,
    subtitle: String? = null,
    iconTint: Color = MaterialTheme.colorScheme.primary,
    onClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp)
            .glass(dark)
            .clickable { onClick() }
            .padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = iconTint,
            modifier = Modifier.size(24.dp)
        )

        Spacer(modifier = Modifier.width(20.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
            subtitle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            modifier = Modifier.size(20.dp)
        )
    }
}

@Composable
private fun SectionDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(vertical = 8.dp),
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f)
    )
}

// --- Arama Ekranı ---

@Composable
private fun SearchContent(
    modifier: Modifier = Modifier,
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    searchResults: List<MessageEntity>,
    isLoading: Boolean,
    onMessageClick: (String) -> Unit
) {
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        OutlinedTextField(
            value = searchQuery,
            onValueChange = onSearchQueryChange,
            label = { Text("Mesajlarda ara...") },
            leadingIcon = {
                Icon(Icons.Default.Search, contentDescription = null)
            },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(12.dp)
        )

        Spacer(modifier = Modifier.height(16.dp))

        if (isLoading) {
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator()
            }
        } else if (searchQuery.isNotBlank() && searchResults.isEmpty()) {
            EmptyStateMessage("Sonuç bulunamadı")
        } else {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(searchResults) { message ->
                    MessageResultItem(
                        message = message,
                        onClick = { onMessageClick(message.id) }
                    )
                }
            }
        }
    }
}

// --- Yıldızlı Mesajlar ---

@Composable
private fun StarredMessagesContent(
    modifier: Modifier = Modifier,
    starredMessages: List<MessageEntity>,
    isLoading: Boolean,
    onMessageClick: (String) -> Unit
) {
    if (isLoading) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
    } else if (starredMessages.isEmpty()) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            EmptyStateMessage("Yıldızlı mesaj yok")
        }
    } else {
        LazyColumn(
            modifier = modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(starredMessages) { message ->
                MessageResultItem(
                    message = message,
                    showStar = true,
                    onClick = { onMessageClick(message.id) }
                )
            }
        }
    }
}

// --- Medya Ekranı ---

@Composable
private fun MediaContent(
    modifier: Modifier = Modifier,
    mediaMessages: List<MessageEntity>,
    isLoading: Boolean,
    onMediaClick: (MessageEntity) -> Unit
) {
    if (isLoading) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
    } else if (mediaMessages.isEmpty()) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            EmptyStateMessage("Medya yok")
        }
    } else {
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(mediaMessages) { message ->
                MediaThumbnail(
                    message = message,
                    onClick = { onMediaClick(message) }
                )
            }
        }
    }
}

@Composable
private fun MediaThumbnail(
    message: MessageEntity,
    onClick: () -> Unit
) {
    val parts = message.content.split("|")
    val mimeType = parts.getOrNull(1) ?: ""
    val filePath = parts.getOrNull(3) ?: ""
    val isImage = mimeType.startsWith("image/")
    val isVideo = mimeType.startsWith("video/")
    val ctx = androidx.compose.ui.platform.LocalContext.current

    Card(
        modifier = Modifier
            .size(110.dp)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                shape = RoundedCornerShape(8.dp)
            )
            .clickable { onClick() },
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.15f)
        )
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            if ((isImage || isVideo) && filePath.isNotBlank()) {
                coil.compose.AsyncImage(
                    model = coil.request.ImageRequest.Builder(ctx)
                        .data(java.io.File(filePath))
                        .crossfade(true)
                        .build(),
                    contentDescription = parts.getOrNull(0),
                    modifier = Modifier.fillMaxSize(),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop
                )
                if (isVideo) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(Color.Black.copy(alpha = 0.55f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(22.dp)
                        )
                    }
                }
            } else {
                Icon(
                    Icons.Default.Image,
                    contentDescription = null,
                    modifier = Modifier.size(32.dp),
                    tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f)
                )
            }
        }
    }
}

// --- Dokümanlar Ekranı ---

@Composable
private fun DocumentsContent(
    modifier: Modifier = Modifier,
    documentMessages: List<MessageEntity>,
    isLoading: Boolean,
    onDocumentClick: (MessageEntity) -> Unit
) {
    if (isLoading) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
    } else if (documentMessages.isEmpty()) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            EmptyStateMessage("Doküman yok")
        }
    } else {
        LazyColumn(
            modifier = modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(documentMessages) { message ->
                DocumentItem(
                    message = message,
                    onClick = { onDocumentClick(message) }
                )
            }
        }
    }
}

@Composable
private fun DocumentItem(
    message: MessageEntity,
    onClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                shape = RoundedCornerShape(12.dp)
            )
            .glass(dark, shape = RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.Description,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(22.dp)
            )
        }

        Spacer(modifier = Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = message.content.substringAfterLast("/").substringBefore("|"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = java.text.SimpleDateFormat("dd/MM/yyyy", java.util.Locale.getDefault()).format(message.timestamp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

// --- Ortak Bileşenler ---

@Composable
private fun MessageResultItem(
    message: MessageEntity,
    showStar: Boolean = false,
    onClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark)
            .clickable { onClick() }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = message.content,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = java.text.SimpleDateFormat("dd/MM/yyyy HH:mm", java.util.Locale.getDefault()).format(message.timestamp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (showStar) {
                Spacer(modifier = Modifier.width(8.dp))
                Icon(
                    Icons.Default.Star,
                    contentDescription = null,
                    tint = Color(0xFFFFD700),
                    modifier = Modifier.size(16.dp)
                )
            }
        }
    }
}

@Composable
private fun EmptyStateMessage(text: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            textAlign = TextAlign.Center
        )
    }
}

// --- Yardımcı fonksiyonlar ---

/**
 * Süreli mesaj süresini okunabilir etikete çevirir.
 * Sabit preset'ler icin hizli yol; ozel sureler icin gun/saat/dakika/saniye birlesik metin.
 */
internal fun formatDisappearingLabel(duration: Long): String {
    if (duration <= 0) return "Kapalı"
    return when (duration) {
        30_000L -> "30 saniye"
        60_000L -> "1 dakika"
        600_000L -> "10 dakika"
        1_800_000L -> "30 dakika"
        3_600_000L -> "1 saat"
        86_400_000L -> "24 saat"
        else -> {
            val days = duration / 86_400_000L
            val hours = (duration % 86_400_000L) / 3_600_000L
            val minutes = (duration % 3_600_000L) / 60_000L
            val seconds = (duration % 60_000L) / 1_000L
            buildList {
                if (days > 0) add("$days gün")
                if (hours > 0) add("$hours saat")
                if (minutes > 0) add("$minutes dakika")
                if (seconds > 0 && days == 0L && hours == 0L) add("$seconds saniye")
            }.joinToString(" ").ifBlank { "Açık" }
        }
    }
}

private fun formatPhoneDisplay(phone: String): String {
    if (phone.startsWith("+90") && phone.length == 13) {
        return "+90 ${phone.substring(3, 6)} ${phone.substring(6, 9)} ${phone.substring(9, 11)} ${phone.substring(11)}"
    }
    return phone
}
