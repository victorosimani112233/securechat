package com.securechat.app.ui.screen

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.platform.LocalContext
import com.securechat.app.ui.viewmodel.ChatViewModel
import com.securechat.app.ui.viewmodel.ConversationInfo
import com.securechat.app.util.FileOpenHelper
import com.securechat.app.util.TimeFormatter
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.abs

/**
 * Sohbet ekranı.
 * Mesaj baloncukları, chat top bar, tarih ayırıcılar, şifreleme bilgisi ve mesaj giriş çubuğu içerir.
 * Dosya/resim gönderme desteği: ataşman butonu ile dosya seçimi ve gönderimi.
 * Arka plan temiz koyu (#0D1117), gelişmiş mesaj baloncukları, yazma göstergesi placeholder'ı
 * ve uzun basma ile mesaj silme desteği içerir.
 *
 * Midnight Teal tasarım: koyu arka plan, teal giden balonlar, koyu gri gelen balonlar.
 */
@Composable
fun ChatScreen(
    conversationId: String,
    viewModel: ChatViewModel = hiltViewModel(),
    onBackClick: () -> Unit,
    onVoiceCallClick: (String) -> Unit,
    onVideoCallClick: (String) -> Unit,
    onChatInfoClick: (String) -> Unit = {},
    onGroupInfoClick: (String) -> Unit = {},
    onMessageJump: (String) -> Unit = {}
) {
    val messages by viewModel.messages.collectAsStateWithLifecycle()
    val conversationInfo by viewModel.conversationInfo.collectAsStateWithLifecycle()
    var messageText by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val snackbarHostState = remember { SnackbarHostState() }

    // Yazma göstergesi
    val peerIsTyping by viewModel.peerIsTyping.collectAsStateWithLifecycle()

    // Süreli mesaj state'leri
    val disappearingDuration by viewModel.disappearingDuration.collectAsStateWithLifecycle()
    var showDisappearingDialog by remember { mutableStateOf(false) }

    // Arama state'leri
    var isSearchMode by remember { mutableStateOf(false) }
    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val searchResultIds by viewModel.searchResultIds.collectAsStateWithLifecycle()
    val currentSearchIndex by viewModel.currentSearchIndex.collectAsStateWithLifecycle()
    val highlightedMessageId by viewModel.highlightedMessageId.collectAsStateWithLifecycle()

    // Dosya seçici launcher
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let { viewModel.sendFile(it) }
    }

    // Dosya transfer hata mesajlarını göster
    LaunchedEffect(Unit) {
        viewModel.fileTransferEvent.collect { message ->
            snackbarHostState.showSnackbar(message)
        }
    }

    // Yeni mesaj gelince en alta scroll (arama modunda değil)
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty() && !isSearchMode) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }

    // Arama sonucu mesaja scroll
    LaunchedEffect(Unit) {
        viewModel.scrollToMessageId.collect { targetId ->
            // Flat mesaj listesinde hedef mesajın index'ini bul
            // encryption_info (1 item) + her tarih grubu için 1 date separator + mesajlar
            val flatItems = buildFlatItemList(messages)
            val targetIndex = flatItems.indexOfFirst { it == targetId }
            if (targetIndex >= 0) {
                listState.animateScrollToItem(targetIndex)
            }
        }
    }

    // Konuşma bilgisinden isim al
    val displayName = conversationInfo?.name ?: conversationId
    val isGroup = conversationInfo?.isGroup ?: false

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

    Scaffold(
        topBar = {
            if (isSearchMode) {
                ChatSearchBar(
                    query = searchQuery,
                    resultCount = searchResultIds.size,
                    currentIndex = currentSearchIndex,
                    onQueryChange = { viewModel.searchInChat(it) },
                    onNext = { viewModel.nextSearchResult() },
                    onPrev = { viewModel.prevSearchResult() },
                    onClose = {
                        isSearchMode = false
                        viewModel.clearChatSearch()
                    }
                )
            } else {
                ChatTopBar(
                    peerName = displayName,
                    isGroup = isGroup,
                    memberCount = conversationInfo?.memberCount ?: 0,
                    peerIsTyping = peerIsTyping,
                    onBackClick = onBackClick,
                    onVoiceCallClick = { onVoiceCallClick(conversationId) },
                    onVideoCallClick = { onVideoCallClick(conversationId) },
                    onSearchClick = { isSearchMode = true },
                    onChatInfoClick = {
                        if (conversationInfo?.isGroup == true) {
                            onGroupInfoClick(conversationId)
                        } else {
                            onChatInfoClick(conversationId)
                        }
                    }
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.ime)
        ) {
            // Mesaj listesi
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.background)
            ) {
                if (messages.isEmpty()) {
                    EncryptionInfoBanner(
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(32.dp)
                    )
                }

                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    state = listState,
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    if (messages.isNotEmpty()) {
                        item(key = "encryption_info") {
                            EncryptionInfoBanner(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 32.dp, vertical = 8.dp)
                            )
                        }
                    }

                    val groupedMessages = groupMessagesByDate(messages)
                    groupedMessages.forEach { (dateLabel, dayMessages) ->
                        item(key = "date_$dateLabel") {
                            DateSeparator(dateLabel = dateLabel)
                        }
                        items(dayMessages, key = { it.id }) { message ->
                            MessageBubble(
                                message = message,
                                isGroupChat = isGroup,
                                memberNames = conversationInfo?.memberNames ?: emptyMap(),
                                isHighlighted = message.id == highlightedMessageId,
                                searchQuery = if (isSearchMode) searchQuery else "",
                                onDeleteMessage = { viewModel.deleteMessage(message.id) },
                                onDeleteForEveryone = if (message.isOutgoing) {
                                    { viewModel.deleteMessageForEveryone(message.id) }
                                } else null,
                                onToggleStarMessage = { messageId, isStarred ->
                                    viewModel.toggleMessageStarred(messageId, isStarred)
                                }
                            )
                        }
                    }
                }
            }

            // Mesaj giriş çubuğu
            MessageInputBar(
                text = messageText,
                onTextChange = {
                    messageText = it
                    viewModel.updateTypingState(it.isNotBlank())
                },
                onSend = {
                    if (messageText.isNotBlank()) {
                        viewModel.sendMessage(messageText.trim())
                        messageText = ""
                        viewModel.updateTypingState(false)
                    }
                },
                onAttachClick = {
                    filePickerLauncher.launch(arrayOf("*/*"))
                }
            )
        }
    }
}

/**
 * Flat item listesi oluşturur — scroll index hesabı için.
 * encryption_info + (tarih_ayırıcı + mesajlar) sırasında.
 */
private fun buildFlatItemList(messages: List<LocalMessage>): List<String> {
    if (messages.isEmpty()) return emptyList()
    val result = mutableListOf<String>()
    result.add("encryption_info")
    val grouped = groupMessagesByDate(messages)
    for ((dateLabel, dayMessages) in grouped) {
        result.add("date_$dateLabel")
        for (msg in dayMessages) {
            result.add(msg.id)
        }
    }
    return result
}

/**
 * WhatsApp benzeri sohbet içi arama çubuğu.
 * Arama text field'ı, belirgin sonuç sayacı ve yukarı/aşağı navigasyon okları içerir.
 * Aşağı ok: daha eski mesaja gider. Yukarı ok: daha yeni mesaja gider.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatSearchBar(
    query: String,
    resultCount: Int,
    currentIndex: Int,
    onQueryChange: (String) -> Unit,
    onNext: () -> Unit,
    onPrev: () -> Unit,
    onClose: () -> Unit
) {
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    Surface(
        color = MaterialTheme.colorScheme.background,
        modifier = Modifier
            .windowInsetsPadding(WindowInsets.statusBars)
            .drawBehind {
                drawLine(
                    color = Color(0xFF30363D),
                    start = Offset(0f, size.height),
                    end = Offset(size.width, size.height),
                    strokeWidth = 1f
                )
            }
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 4.dp, end = 4.dp, top = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Geri / kapat butonu
                IconButton(onClick = onClose) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Aramadan çık",
                        tint = MaterialTheme.colorScheme.onSurface
                    )
                }

                // Arama alanı
                Surface(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(24.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                ) {
                    TextField(
                        value = query,
                        onValueChange = onQueryChange,
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(focusRequester),
                        placeholder = {
                            Text(
                                "Mesajlarda ara...",
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                            )
                        },
                        singleLine = true,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            cursorColor = MaterialTheme.colorScheme.primary
                        ),
                        trailingIcon = {
                            if (query.isNotBlank()) {
                                IconButton(onClick = {
                                    onQueryChange("")
                                }) {
                                    Icon(
                                        Icons.Default.Close,
                                        contentDescription = "Temizle",
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(18.dp)
                                    )
                                }
                            }
                        }
                    )
                }
            }

            // Sonuç sayacı ve navigasyon okları — ayrı satırda, belirgin
            if (query.isNotBlank()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 16.dp, end = 4.dp, bottom = 6.dp, top = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    // Sonuç sayacı — belirgin
                    Text(
                        text = if (resultCount > 0)
                            "${currentIndex + 1} / $resultCount sonuç"
                        else
                            "Sonuç bulunamadı",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (resultCount > 0)
                            MaterialTheme.colorScheme.primary
                        else
                            MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
                        fontWeight = FontWeight.Medium,
                        fontSize = 13.sp
                    )

                    // Navigasyon okları
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        // Yukarı ok — daha yeni mesaja git
                        IconButton(
                            onClick = onPrev,
                            enabled = resultCount > 0 && currentIndex > 0,
                            modifier = Modifier.size(40.dp)
                        ) {
                            Icon(
                                Icons.Default.KeyboardArrowUp,
                                contentDescription = "Daha yeni sonuç",
                                tint = if (resultCount > 0 && currentIndex > 0)
                                    MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f),
                                modifier = Modifier.size(28.dp)
                            )
                        }

                        // Aşağı ok — daha eski mesaja git
                        IconButton(
                            onClick = onNext,
                            enabled = resultCount > 0 && currentIndex < resultCount - 1,
                            modifier = Modifier.size(40.dp)
                        ) {
                            Icon(
                                Icons.Default.KeyboardArrowDown,
                                contentDescription = "Daha eski sonuç",
                                tint = if (resultCount > 0 && currentIndex < resultCount - 1)
                                    MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f),
                                modifier = Modifier.size(28.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

/**
 * Şifreleme bilgisi banner'ı.
 * Uçtan uca şifreleme durumunu gösterir — cyan tonlu.
 */
@Composable
private fun EncryptionInfoBanner(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = Icons.Default.Lock,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f)
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = "Mesajlar uçtan uca şifrelenmiştir.",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
                fontSize = 11.sp
            )
        }
    }
}

/**
 * Tarih ayırıcı.
 * Farklı günlere ait mesajlar arasında tarih etiketi gösterir.
 */
@Composable
private fun DateSeparator(dateLabel: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.85f),
            shadowElevation = 1.dp
        ) {
            Text(
                text = dateLabel,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                fontWeight = FontWeight.Medium,
                fontSize = 12.sp
            )
        }
    }
}

/**
 * Mesajları tarih bazında gruplar.
 * Bugün, Dün, bu haftanın günleri veya tarih olarak etiketler.
 */
private fun groupMessagesByDate(messages: List<LocalMessage>): List<Pair<String, List<LocalMessage>>> {
    if (messages.isEmpty()) return emptyList()

    val dateFormat = SimpleDateFormat("dd MMMM yyyy", Locale("tr"))
    val dayOfWeekFormat = SimpleDateFormat("EEEE", Locale("tr"))
    val now = Calendar.getInstance()
    val yesterday = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }

    return messages.groupBy { message ->
        val msgCal = Calendar.getInstance().apply { timeInMillis = message.timestamp }
        when {
            isSameDay(now, msgCal) -> "Bugün"
            isSameDay(yesterday, msgCal) -> "Dün"
            isSameWeek(now, msgCal) -> dayOfWeekFormat.format(Date(message.timestamp))
                .replaceFirstChar { it.uppercase() }
            else -> dateFormat.format(Date(message.timestamp))
        }
    }.toList()
}

private fun isSameDay(cal1: Calendar, cal2: Calendar): Boolean {
    return cal1.get(Calendar.YEAR) == cal2.get(Calendar.YEAR) &&
        cal1.get(Calendar.DAY_OF_YEAR) == cal2.get(Calendar.DAY_OF_YEAR)
}

private fun isSameWeek(cal1: Calendar, cal2: Calendar): Boolean {
    return cal1.get(Calendar.YEAR) == cal2.get(Calendar.YEAR) &&
        cal1.get(Calendar.WEEK_OF_YEAR) == cal2.get(Calendar.WEEK_OF_YEAR)
}

/**
 * Sohbet ekranı üst bar'ı — WhatsApp stili.
 * Geri butonu + [avatar + isim] butonu (info'ya gider) + arama/arama ikonları.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ChatTopBar(
    peerName: String,
    isGroup: Boolean = false,
    memberCount: Int = 0,
    peerIsTyping: Boolean = false,
    onBackClick: () -> Unit,
    onVoiceCallClick: () -> Unit,
    onVideoCallClick: () -> Unit,
    onSearchClick: (() -> Unit)? = null,
    onChatInfoClick: (() -> Unit)? = null
) {
    Surface(
        color = MaterialTheme.colorScheme.background,
        modifier = Modifier.drawBehind {
            drawLine(
                color = Color(0xFF30363D),
                start = Offset(0f, size.height),
                end = Offset(size.width, size.height),
                strokeWidth = 1f
            )
        }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsPadding(WindowInsets.statusBars)
                .padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Geri butonu
            IconButton(onClick = onBackClick) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Geri",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }

            // Avatar + isim alanı — tek tıklanabilir blok, info ekranına gider
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(8.dp))
                    .then(
                        if (onChatInfoClick != null) Modifier.combinedClickable(
                            onClick = { onChatInfoClick() }
                        ) else Modifier
                    )
                    .padding(vertical = 8.dp, horizontal = 4.dp)
            ) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(chatAvatarGradient(peerName)),
                    contentAlignment = Alignment.Center
                ) {
                    if (isGroup) {
                        Icon(
                            imageVector = Icons.Default.Group,
                            contentDescription = "Grup",
                            tint = Color.White,
                            modifier = Modifier.size(20.dp)
                        )
                    } else {
                        Text(
                            text = peerName.firstOrNull()?.uppercase() ?: "?",
                            style = MaterialTheme.typography.titleSmall,
                            color = Color.White,
                            fontWeight = FontWeight.Bold,
                            fontSize = 15.sp
                        )
                    }
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = peerName,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    if (peerIsTyping) {
                        Text(
                            text = "yazıyor...",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            fontSize = 11.sp
                        )
                    } else if (isGroup && memberCount > 0) {
                        Text(
                            text = "$memberCount üye",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = 11.sp
                        )
                    }
                }
            }

            // Aksiyon ikonları
            if (onSearchClick != null) {
                IconButton(onClick = onSearchClick) {
                    Icon(
                        Icons.Default.Search,
                        contentDescription = "Sohbette Ara",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            IconButton(onClick = onVoiceCallClick) {
                Icon(
                    Icons.Default.Call,
                    contentDescription = "Sesli Arama",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = onVideoCallClick) {
                Icon(
                    Icons.Default.Videocam,
                    contentDescription = "Görüntülü Arama",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Süreli mesaj zamanlayıcı seçim dialog'u.
 * WhatsApp benzeri seçenekler sunar.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun DisappearingTimerDialog(
    currentDuration: Long,
    onDurationSelected: (Long) -> Unit,
    onDismiss: () -> Unit
) {
    val options = listOf(
        0L to "Kapalı",
        30_000L to "30 saniye",
        60_000L to "1 dakika",
        300_000L to "5 dakika",
        3_600_000L to "1 saat",
        86_400_000L to "24 saat"
    )

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                "Süreli Mesajlar",
                style = MaterialTheme.typography.titleLarge
            )
        },
        text = {
            Column {
                Text(
                    "Mesajlar seçilen süre sonunda otomatik silinir.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 16.dp)
                )
                options.forEach { (duration, label) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .combinedClickable(onClick = { onDurationSelected(duration) })
                            .padding(vertical = 12.dp, horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            if (duration == 0L) Icons.Default.Close else Icons.Default.Schedule,
                            contentDescription = null,
                            tint = if (duration == currentDuration)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp)
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = label,
                            style = MaterialTheme.typography.bodyLarge,
                            color = if (duration == currentDuration)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.onSurface,
                            fontWeight = if (duration == currentDuration)
                                FontWeight.Bold
                            else
                                FontWeight.Normal
                        )
                        if (duration == currentDuration) {
                            Spacer(modifier = Modifier.weight(1f))
                            Icon(
                                Icons.Default.Check,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) {
                Text("Kapat")
            }
        }
    )
}

/**
 * Chat top bar avatar için gradient — daha koyu, canlı tonlar.
 */
private fun chatAvatarGradient(name: String): Brush {
    val colors = listOf(
        Color(0xFF00897B) to Color(0xFF004D40),
        Color(0xFF00ACC1) to Color(0xFF006064),
        Color(0xFF5C6BC0) to Color(0xFF283593),
        Color(0xFF7E57C2) to Color(0xFF4527A0),
        Color(0xFFEF5350) to Color(0xFFB71C1C),
        Color(0xFFFF7043) to Color(0xFFBF360C),
        Color(0xFF42A5F5) to Color(0xFF1565C0)
    )
    val index = abs(name.hashCode()) % colors.size
    val (start, end) = colors[index]
    return Brush.linearGradient(listOf(start, end))
}

/**
 * Gönderen isim rengi — her isim için tutarlı renk üretir.
 * Midnight Teal ile uyumlu parlak tonlar.
 */
private fun senderNameColor(senderId: String): Color {
    val senderColors = listOf(
        Color(0xFF4ECDC4),
        Color(0xFF2979FF),
        Color(0xFF7C4DFF),
        Color(0xFFFF7043),
        Color(0xFFEC407A),
        Color(0xFF66BB6A),
        Color(0xFF42A5F5)
    )
    val index = abs(senderId.hashCode()) % senderColors.size
    return senderColors[index]
}

/**
 * Mesaj baloncuğu.
 * TEXT mesajları metin olarak, IMAGE mesajları küçük resim simgesi ile,
 * FILE mesajları dosya adı ve boyutuyla gösterilir.
 * Giden mesajlar teal (#003D47), gelen mesajlar koyu gri (#21262D) ile gösterilir.
 * Midnight Teal stili.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MessageBubble(
    message: LocalMessage,
    isGroupChat: Boolean = false,
    memberNames: Map<String, String> = emptyMap(),
    isHighlighted: Boolean = false,
    searchQuery: String = "",
    onDeleteMessage: (() -> Unit)? = null,
    onDeleteForEveryone: (() -> Unit)? = null,
    onToggleStarMessage: ((String, Boolean) -> Unit)? = null
) {
    val isOutgoing = message.isOutgoing
    var showPopupMenu by remember { mutableStateOf(false) }

    // Highlight animasyonu
    val highlightColor by animateColorAsState(
        targetValue = if (isHighlighted) Color(0xFF4ECDC4).copy(alpha = 0.25f)
        else Color.Transparent,
        animationSpec = tween(durationMillis = 400),
        label = "highlight"
    )

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(highlightColor)
            .padding(
                start = if (isOutgoing) 48.dp else 4.dp,
                end = if (isOutgoing) 4.dp else 48.dp,
                top = 1.dp,
                bottom = 1.dp
            ),
        horizontalArrangement = if (isOutgoing) Arrangement.End else Arrangement.Start
    ) {
        Box {
            Surface(
                shape = RoundedCornerShape(
                    topStart = if (isOutgoing) 12.dp else 4.dp,
                    topEnd = if (isOutgoing) 4.dp else 12.dp,
                    bottomStart = 12.dp,
                    bottomEnd = 12.dp
                ),
                color = if (isOutgoing)
                    MaterialTheme.colorScheme.primaryContainer
                else MaterialTheme.colorScheme.surfaceVariant,
                shadowElevation = 1.dp,
                modifier = Modifier
                    .widthIn(min = 80.dp, max = 300.dp)
                    .combinedClickable(
                        onClick = { },
                        onLongClick = { if (!message.isDeleted) showPopupMenu = true }
                    )
            ) {
                Column(
                    modifier = Modifier.padding(
                        start = 10.dp,
                        end = 10.dp,
                        top = 6.dp,
                        bottom = 4.dp
                    )
                ) {
                    // Grup konuşmalarında gelen mesajlarda gönderici ismini göster
                    if (isGroupChat && !isOutgoing) {
                        val displayName = memberNames[message.senderId] ?: message.senderId
                        Text(
                            text = displayName,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = senderNameColor(message.senderId),
                            fontSize = 12.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Spacer(modifier = Modifier.height(2.dp))
                    }

                    // Mesaj içeriğini tipine göre göster
                    when {
                        message.isDeleted -> {
                            Row(
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    Icons.Default.Block,
                                    contentDescription = null,
                                    modifier = Modifier.size(14.dp),
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                )
                                Spacer(modifier = Modifier.width(4.dp))
                                Text(
                                    text = "Bu mesaj silindi",
                                    style = MaterialTheme.typography.bodyMedium.copy(
                                        fontStyle = androidx.compose.ui.text.font.FontStyle.Italic
                                    ),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                )
                            }
                        }
                        message.isFileMessage -> {
                            val context = LocalContext.current
                            FileMessageContent(
                                message = message,
                                isOutgoing = isOutgoing,
                                onFileClick = {
                                    message.filePath?.let { filePath ->
                                        FileOpenHelper.openFile(
                                            context = context,
                                            filePath = filePath,
                                            mimeType = message.fileMimeType ?: "application/octet-stream"
                                        )
                                    }
                                },
                                onShareClick = {
                                    message.filePath?.let { filePath ->
                                        FileOpenHelper.shareFile(
                                            context = context,
                                            filePath = filePath,
                                            mimeType = message.fileMimeType ?: "application/octet-stream",
                                            fileName = message.fileName ?: "Dosya"
                                        )
                                    }
                                }
                            )
                        }
                        else -> TextMessageContent(
                            message = message,
                            isOutgoing = isOutgoing,
                            searchQuery = searchQuery
                        )
                    }

                    Spacer(modifier = Modifier.height(2.dp))
                    Row(
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (message.isStarred) {
                            Icon(
                                Icons.Default.Star,
                                contentDescription = null,
                                tint = Color(0xFFFFD700),
                                modifier = Modifier.size(12.dp)
                            )
                            Spacer(modifier = Modifier.width(3.dp))
                        }
                        Text(
                            text = formatTime(message.timestamp),
                            style = MaterialTheme.typography.labelSmall,
                            color = if (isOutgoing)
                                MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.55f)
                            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                            fontSize = 11.sp
                        )
                        if (isOutgoing) {
                            Spacer(modifier = Modifier.width(3.dp))
                            MessageStatusIcon(status = message.status)
                        }
                    }
                }
            }

            // Uzun basma popup menüsü — mesaj silme ve yıldızlama seçenekleri
            DropdownMenu(
                expanded = showPopupMenu,
                onDismissRequest = { showPopupMenu = false }
            ) {
                // Yıldızlama seçeneği
                onToggleStarMessage?.let { toggleStar ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                if (message.isStarred) "Yıldızdan Çıkar" else "Yıldızla",
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        },
                        onClick = {
                            showPopupMenu = false
                            toggleStar(message.id, !message.isStarred)
                        },
                        leadingIcon = {
                            Icon(
                                if (message.isStarred) Icons.Default.Star else Icons.Default.StarBorder,
                                contentDescription = null,
                                tint = if (message.isStarred) Color(0xFFFFD700) else MaterialTheme.colorScheme.onSurface
                            )
                        }
                    )
                }

                // Benden sil
                DropdownMenuItem(
                    text = { Text("Benden Sil") },
                    onClick = {
                        showPopupMenu = false
                        onDeleteMessage?.invoke()
                    },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                )

                // Herkesten sil (sadece kendi mesajları için)
                if (onDeleteForEveryone != null) {
                    DropdownMenuItem(
                        text = {
                            Text(
                                "Herkesten Sil",
                                color = MaterialTheme.colorScheme.error
                            )
                        },
                        onClick = {
                            showPopupMenu = false
                            onDeleteForEveryone()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.DeleteForever,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error
                            )
                        }
                    )
                }

                // Dosya mesajı ise birlikte aç seçeneği de ekle
                if (message.isFileMessage) {
                    val context = LocalContext.current
                    DropdownMenuItem(
                        text = {
                            Text(
                                "Birlikte Aç",
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        },
                        onClick = {
                            showPopupMenu = false
                            message.filePath?.let { filePath ->
                                FileOpenHelper.openWithChooser(
                                    context = context,
                                    filePath = filePath,
                                    mimeType = message.fileMimeType ?: "application/octet-stream"
                                )
                            }
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Share,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    )
                }
            }
        }
    }
}

/**
 * Metin mesajı içeriği.
 * Arama sorgusu verilmişse eşleşen metni highlight eder.
 */
@Composable
private fun TextMessageContent(
    message: LocalMessage,
    isOutgoing: Boolean,
    searchQuery: String = ""
) {
    val textColor = if (isOutgoing)
        MaterialTheme.colorScheme.onPrimaryContainer
    else MaterialTheme.colorScheme.onSurface

    if (searchQuery.isNotBlank() && message.content.contains(searchQuery, ignoreCase = true)) {
        val annotated = buildHighlightedText(message.content, searchQuery, textColor)
        Text(
            text = annotated,
            style = MaterialTheme.typography.bodyMedium,
            lineHeight = 20.sp
        )
    } else {
        Text(
            text = message.content,
            style = MaterialTheme.typography.bodyMedium,
            color = textColor,
            lineHeight = 20.sp
        )
    }
}

/**
 * Arama sorgusuna eşleşen metin parçalarını highlight eden AnnotatedString oluşturur.
 */
private fun buildHighlightedText(
    text: String,
    query: String,
    defaultColor: Color
) = buildAnnotatedString {
    val lowerText = text.lowercase()
    val lowerQuery = query.lowercase()
    var currentIndex = 0

    while (currentIndex < text.length) {
        val matchIndex = lowerText.indexOf(lowerQuery, currentIndex)
        if (matchIndex == -1) {
            // Kalan metin — normal renk
            withStyle(SpanStyle(color = defaultColor)) {
                append(text.substring(currentIndex))
            }
            break
        }

        // Match'ten önceki metin
        if (matchIndex > currentIndex) {
            withStyle(SpanStyle(color = defaultColor)) {
                append(text.substring(currentIndex, matchIndex))
            }
        }

        // Eşleşen metin — sarı highlight
        withStyle(
            SpanStyle(
                color = Color(0xFF0D1117),
                background = Color(0xFFFFEB3B)
            )
        ) {
            append(text.substring(matchIndex, matchIndex + query.length))
        }

        currentIndex = matchIndex + query.length
    }
}

/**
 * Dosya mesajı içeriği.
 * Resim dosyaları resim ikonu ile, diğer dosyalar dosya ikonu ile gösterilir.
 * Dosya adı ve okunabilir boyut bilgisi yer alır.
 * Dosyaya tıklandığında external app ile açılır.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FileMessageContent(
    message: LocalMessage,
    isOutgoing: Boolean,
    onFileClick: () -> Unit = {},
    onShareClick: () -> Unit = {}
) {
    val textColor = if (isOutgoing)
        MaterialTheme.colorScheme.onPrimaryContainer
    else MaterialTheme.colorScheme.onSurface

    val subtextColor = if (isOutgoing)
        MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.7f)
    else MaterialTheme.colorScheme.onSurfaceVariant

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .padding(vertical = 4.dp)
            .combinedClickable(
                onClick = onFileClick
            )
    ) {
        // Dosya tipi ikonu
        val icon = if (message.isImageFile) {
            Icons.Default.Image
        } else {
            Icons.AutoMirrored.Filled.InsertDriveFile
        }

        // Dynamic color based on MIME type
        val iconTint = message.fileMimeType?.let { mimeType ->
            FileOpenHelper.getMimeTypeColor(mimeType)
        } ?: if (message.isImageFile) {
            Color(0xFF4ECDC4)
        } else {
            Color(0xFF42A5F5)
        }

        Surface(
            shape = RoundedCornerShape(8.dp),
            color = iconTint.copy(alpha = 0.15f),
            modifier = Modifier.size(40.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconTint,
                    modifier = Modifier.size(24.dp)
                )
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = message.fileName ?: "Dosya",
                style = MaterialTheme.typography.bodyMedium,
                color = textColor,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                fontWeight = FontWeight.Medium
            )
            val sizeText = message.fileSize?.let { formatFileSize(it) } ?: ""
            val typeText = message.fileMimeType?.let { mimeType ->
                FileOpenHelper.getFileTypeDisplayName(mimeType, message.fileName ?: "")
            } ?: "Dosya"
            Text(
                text = if (sizeText.isNotBlank()) "$typeText - $sizeText" else typeText,
                style = MaterialTheme.typography.labelSmall,
                color = subtextColor,
                fontSize = 11.sp
            )
        }
    }
}

/**
 * Dosya boyutunu okunabilir formata çevirir.
 * Örneğin: 1024 -> "1 KB", 1048576 -> "1 MB"
 */
private fun formatFileSize(bytes: Long): String {
    return when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> "${bytes / 1024} KB"
        else -> String.format("%.1f MB", bytes / (1024.0 * 1024.0))
    }
}

/**
 * Mesaj durum ikonu.
 * SENDING: saat, SENT: tek tik, DELIVERED: çift tik, READ: cyan çift tik, FAILED: hata.
 */
@Composable
fun MessageStatusIcon(status: MessageStatus) {
    val (icon, tint) = when (status) {
        MessageStatus.SENDING -> Icons.Default.Schedule to MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.4f)
        MessageStatus.SENT -> Icons.Default.Check to MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.55f)
        MessageStatus.DELIVERED -> Icons.Default.DoneAll to MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.55f)
        MessageStatus.READ -> Icons.Default.DoneAll to Color(0xFF4ECDC4)
        MessageStatus.FAILED -> Icons.Default.Error to MaterialTheme.colorScheme.error
    }
    Icon(
        imageVector = icon,
        contentDescription = status.name,
        modifier = Modifier
            .padding(start = 2.dp)
            .size(16.dp),
        tint = tint
    )
}

/**
 * Mesaj giriş çubuğu.
 * Koyu surface arka plan, ince border, yuvarlatılmış alan.
 * Ataşman (dosya ekleme) butonu solda, gönder butonu sağda.
 * Metin boşsa ataşman butonu vurgulanır.
 */
@Composable
fun MessageInputBar(
    text: String,
    onTextChange: (String) -> Unit,
    onSend: () -> Unit,
    onAttachClick: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier.drawBehind {
            // Üst kenarda ince border
            drawLine(
                color = Color(0xFF30363D),
                start = Offset(0f, 0f),
                end = Offset(size.width, 0f),
                strokeWidth = 1f
            )
        }
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 6.dp, vertical = 6.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.Bottom
        ) {
            // Ataşman (dosya ekleme) butonu
            IconButton(
                onClick = onAttachClick,
                modifier = Modifier.size(48.dp)
            ) {
                Icon(
                    Icons.Default.AttachFile,
                    contentDescription = "Dosya ekle",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(24.dp)
                )
            }

            // Metin alanı — koyu surfaceVariant arka plan, ince border
            Surface(
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(24.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                border = androidx.compose.foundation.BorderStroke(
                    0.5.dp,
                    MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)
                )
            ) {
                TextField(
                    value = text,
                    onValueChange = onTextChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = {
                        Text(
                            "Mesaj yazın...",
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                        )
                    },
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.Transparent,
                        unfocusedContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        disabledIndicatorColor = Color.Transparent,
                        cursorColor = MaterialTheme.colorScheme.primary
                    ),
                    maxLines = 4
                )
            }

            Spacer(modifier = Modifier.width(6.dp))

            // Gönder butonu — canlı cyan, metin varsa gönderir
            IconButton(
                onClick = {
                    if (text.isNotBlank()) onSend()
                },
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary),
                colors = IconButtonDefaults.iconButtonColors(
                    contentColor = Color(0xFF0D1117)
                )
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.Send,
                    contentDescription = "Gönder",
                    modifier = Modifier.size(22.dp)
                )
            }
        }
    }
}

/**
 * Mesaj zaman damgasını saat:dakika formatına çevirir.
 */
private fun formatTime(timestamp: Long): String {
    return TimeFormatter.formatTime(timestamp)
}
