package com.securechat.app.ui.screen

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.TextButton
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
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.MonoFamily
import com.securechat.app.ui.theme.glass
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
 * Azure glassmorphism tasarım: koyu arka plan, teal giden balonlar, koyu gri gelen balonlar.
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
    var messageText by remember { mutableStateOf(viewModel.getDraft()) }
    var replyingToMessage by remember { mutableStateOf<LocalMessage?>(null) }
    // Mesaj iletme (forward) multi-select modu
    var isForwardSelectMode by remember { mutableStateOf(false) }
    var selectedMessageIds by remember { mutableStateOf(setOf<String>()) }
    // Iletme hedef secimi dialog'u
    var showForwardPicker by remember { mutableStateOf(false) }
    var forwardContent by remember { mutableStateOf("") }
    // Mesaj bilgi popup'ı (grup sohbetlerinde iletildi/okundu durumu)
    var messageInfoTarget by remember { mutableStateOf<LocalMessage?>(null) }
    val listState = rememberLazyListState()
    var initialScrollDone by remember { mutableStateOf(false) }

    // Sohbet açıldığında en alta scroll (animasyonsuz, anlık)
    LaunchedEffect(messages) {
        if (!initialScrollDone && messages.isNotEmpty()) {
            val totalItems = buildFlatItemList(messages).size
            listState.scrollToItem(maxOf(0, totalItems - 1))
            initialScrollDone = true
        }
    }

    // Sohbetten çıkınca taslağı kaydet
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose {
            viewModel.saveDraft(messageText)
        }
    }
    val snackbarHostState = remember { SnackbarHostState() }

    // Yazma göstergesi
    val peerIsTyping by viewModel.peerIsTyping.collectAsStateWithLifecycle()

    // Çevrimiçi durumu
    val peerPresence by viewModel.peerPresence.collectAsStateWithLifecycle()

    // Süreli mesaj state'leri
    val disappearingDuration by viewModel.disappearingDuration.collectAsStateWithLifecycle()
    var showDisappearingDialog by remember { mutableStateOf(false) }

    // Arama state'leri
    var isSearchMode by remember { mutableStateOf(false) }
    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val searchResultIds by viewModel.searchResultIds.collectAsStateWithLifecycle()
    val currentSearchIndex by viewModel.currentSearchIndex.collectAsStateWithLifecycle()
    val highlightedMessageId by viewModel.highlightedMessageId.collectAsStateWithLifecycle()

    // Mesaj duzenleme state'leri
    var editingMessageId by remember { mutableStateOf<String?>(null) }
    var editingMessageContent by remember { mutableStateOf("") }

    // Dosya seçici launcher
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri?.let { viewModel.sendFile(it) }
    }

    // Galeri seçici launcher
    val galleryPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { viewModel.sendFile(it) }
    }

    // Kamera launcher
    var cameraPhotoUri by remember { mutableStateOf<Uri?>(null) }
    val cameraLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success ->
        if (success) {
            cameraPhotoUri?.let { viewModel.sendFile(it) }
        }
    }

    // Ataşman menü state
    var showAttachMenu by remember { mutableStateOf(false) }

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

    // Klavye açıldığında en alta scroll
    val density = LocalDensity.current
    val imeBottom = WindowInsets.ime.getBottom(density)
    LaunchedEffect(imeBottom) {
        if (imeBottom > 0 && messages.isNotEmpty() && !isSearchMode) {
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

    // Mesaj duzenleme dialog'u
    if (editingMessageId != null) {
        EditMessageDialog(
            currentContent = editingMessageContent,
            onConfirm = { newContent ->
                viewModel.editMessage(editingMessageId!!, newContent)
                editingMessageId = null
                editingMessageContent = ""
            },
            onDismiss = {
                editingMessageId = null
                editingMessageContent = ""
            }
        )
    }

    // İletme hedef seçim dialog'u
    if (showForwardPicker) {
        val forwardConversations by viewModel.getConversationsFlow()
            .collectAsStateWithLifecycle(initialValue = emptyList())
        ForwardPickerDialog(
            conversations = forwardConversations,
            onConversationSelected = { targetId ->
                viewModel.forwardMessage(targetId, forwardContent)
                showForwardPicker = false
                isForwardSelectMode = false
                selectedMessageIds = emptySet()
            },
            onDismiss = { showForwardPicker = false }
        )
    }

    // Mesaj bilgi popup'ı (grup sohbetlerinde iletildi/okundu durumu)
    messageInfoTarget?.let { msg ->
        val convInfo = conversationInfo
        if (convInfo != null) {
            MessageInfoPopup(
                message = msg,
                memberNames = convInfo.memberNames,
                groupMembers = convInfo.members,
                onDismiss = { messageInfoTarget = null }
            )
        }
    }

    val dark = LocalDarkTheme.current
    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        topBar = {
            Column {
                ChatTopBar(
                    peerName = displayName,
                    isGroup = isGroup,
                    memberCount = conversationInfo?.memberCount ?: 0,
                    peerIsTyping = peerIsTyping,
                    peerIsOnline = peerPresence?.isOnline ?: false,
                    peerLastSeen = peerPresence?.lastSeen,
                    disappearingDuration = disappearingDuration,
                    isMuted = conversationInfo?.isMuted ?: false,
                    onBackClick = onBackClick,
                    onVoiceCallClick = {
                        onVoiceCallClick(conversationId)
                    },
                    onVideoCallClick = {
                        onVideoCallClick(conversationId)
                    },
                    onSearchClick = { isSearchMode = true },
                    onDisappearingClick = { showDisappearingDialog = true },
                    onMuteToggle = { viewModel.toggleMuted() },
                    onChatInfoClick = {
                        if (conversationInfo?.isGroup == true) {
                            onGroupInfoClick(conversationId)
                        } else {
                            onChatInfoClick(conversationId)
                        }
                    }
                )
                AnimatedVisibility(
                    visible = isSearchMode,
                    enter = slideInVertically(tween(200)) { -it } + fadeIn(tween(200)),
                    exit = slideOutVertically(tween(200)) { -it } + fadeOut(tween(200))
                ) {
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
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = Color.Transparent
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .consumeWindowInsets(padding)
                .fillMaxSize()
                .imePadding()
        ) {
            // Mesaj listesi
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
            ) {
                if (messages.isEmpty()) {
                    EncryptionInfoBanner(
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(32.dp)
                    )
                }

                // Mesajları tarih gruplarına ve reply map'e memoize et — gereksiz yeniden hesaplamayı önler
                val groupedMessages = remember(messages) { groupMessagesByDate(messages) }
                val replyToMap = remember(messages) { messages.associateBy { it.id } }

                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    state = listState,
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    if (messages.isNotEmpty()) {
                        item(key = "encryption_info") {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 32.dp, vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                EncryptionInfoBanner()
                            }
                        }
                    }

                    groupedMessages.forEach { (dateLabel, dayMessages) ->
                        item(key = "date_$dateLabel") {
                            DateSeparator(dateLabel = dateLabel)
                        }
                        items(dayMessages, key = { it.id }) { message ->
                            // Yanıtlanan mesajı O(1) ile bul
                            val replyToMsg = if (message.replyToId != null) {
                                replyToMap[message.replyToId]
                            } else null

                            if (isForwardSelectMode) {
                                // İletme seçim modu — checkbox ile
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    androidx.compose.material3.Checkbox(
                                        checked = message.id in selectedMessageIds,
                                        onCheckedChange = { checked ->
                                            selectedMessageIds = if (checked) {
                                                selectedMessageIds + message.id
                                            } else {
                                                selectedMessageIds - message.id
                                            }
                                        },
                                        modifier = Modifier.size(36.dp)
                                    )
                                    Box(modifier = Modifier.weight(1f)) {
                                        MessageBubble(
                                            message = message,
                                            isGroupChat = isGroup,
                                            memberNames = conversationInfo?.memberNames ?: emptyMap(),
                                            replyToMessage = replyToMsg,
                                            onReplyClick = { replyId ->
                                                viewModel.navigateToMessage(replyId)
                                            }
                                        )
                                    }
                                }
                            } else {
                                SwipeableMessageBubble(
                                    onSwipeReply = { replyingToMessage = message }
                                ) {
                                    MessageBubble(
                                        message = message,
                                        isGroupChat = isGroup,
                                        memberNames = conversationInfo?.memberNames ?: emptyMap(),
                                        isHighlighted = message.id == highlightedMessageId,
                                        searchQuery = if (isSearchMode) searchQuery else "",
                                        replyToMessage = replyToMsg,
                                        onDeleteMessage = { viewModel.deleteMessage(message.id) },
                                        onDeleteForEveryone = if (message.isOutgoing) {
                                            { viewModel.deleteMessageForEveryone(message.id) }
                                        } else null,
                                        onEditMessage = if (message.isOutgoing && !message.isFileMessage && !message.isDeleted) {
                                            { currentContent ->
                                                editingMessageId = message.id
                                                editingMessageContent = currentContent
                                            }
                                        } else null,
                                        onToggleStarMessage = { messageId, isStarred ->
                                            viewModel.toggleMessageStarred(messageId, isStarred)
                                        },
                                        onForwardMessage = {
                                            isForwardSelectMode = true
                                            selectedMessageIds = setOf(message.id)
                                        },
                                        onReplyClick = { replyId ->
                                            viewModel.navigateToMessage(replyId)
                                        },
                                        onInfoClick = if (conversationInfo?.isGroup == true && message.isOutgoing) {
                                            { messageInfoTarget = message }
                                        } else null,
                                        onReplyToMessage = { replyingToMessage = message }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if (isForwardSelectMode) {
                // İletme modu aksiyon çubuğu
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier
                            .padding(horizontal = 16.dp, vertical = 12.dp)
                            .fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        IconButton(onClick = {
                            isForwardSelectMode = false
                            selectedMessageIds = emptySet()
                        }) {
                            Icon(Icons.Default.Close, contentDescription = "İptal")
                        }
                        Text(
                            text = "${selectedMessageIds.size} mesaj seçildi",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium
                        )
                        IconButton(
                            onClick = {
                                val selectedMsgs = messages.filter { it.id in selectedMessageIds }
                                forwardContent = selectedMsgs.joinToString("\n") { msg ->
                                    if (msg.isFileMessage) "[Dosya: ${msg.content.split("|").firstOrNull() ?: "dosya"}]"
                                    else msg.content
                                }
                                showForwardPicker = true
                            },
                            enabled = selectedMessageIds.isNotEmpty()
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.Send,
                                contentDescription = "İlet",
                                tint = if (selectedMessageIds.isNotEmpty())
                                    MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                            )
                        }
                    }
                }
            } else {
                // Yanıtlama önizlemesi
                replyingToMessage?.let { replyMsg ->
                    ReplyPreview(
                        message = replyMsg,
                        senderName = if (replyMsg.isOutgoing) null
                            else conversationInfo?.memberNames?.get(replyMsg.senderId)
                                ?: conversationInfo?.name,
                        onDismiss = { replyingToMessage = null }
                    )
                }

                // Ataşman seçenekleri popup
                AnimatedVisibility(
                    visible = showAttachMenu,
                    enter = slideInVertically(tween(200)) { it } + fadeIn(tween(200)),
                    exit = slideOutVertically(tween(200)) { it } + fadeOut(tween(200))
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        val chatContext = LocalContext.current
                        AttachOption(
                            icon = Icons.Default.CameraAlt,
                            label = "Kamera",
                            color = Color(0xFF3E7BFA),
                            dark = dark,
                            onClick = {
                                showAttachMenu = false
                                val photoFile = java.io.File(
                                    chatContext.cacheDir,
                                    "camera_${System.currentTimeMillis()}.jpg"
                                )
                                val uri = androidx.core.content.FileProvider.getUriForFile(
                                    chatContext,
                                    "${chatContext.packageName}.fileprovider",
                                    photoFile
                                )
                                cameraPhotoUri = uri
                                cameraLauncher.launch(uri)
                            }
                        )
                        AttachOption(
                            icon = Icons.Default.Image,
                            label = "Galeri",
                            color = Color(0xFF22C55E),
                            dark = dark,
                            onClick = {
                                showAttachMenu = false
                                galleryPickerLauncher.launch("image/*")
                            }
                        )
                        AttachOption(
                            icon = Icons.AutoMirrored.Filled.InsertDriveFile,
                            label = "Dosyalar",
                            color = Color(0xFFFFB800),
                            dark = dark,
                            onClick = {
                                showAttachMenu = false
                                filePickerLauncher.launch(arrayOf("*/*"))
                            }
                        )
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
                        viewModel.sendMessage(messageText.trim(), replyingToMessage?.id)
                        messageText = ""
                        replyingToMessage = null
                        viewModel.updateTypingState(false)
                    }
                },
                onAttachClick = {
                    showAttachMenu = !showAttachMenu
                }
            )
            }
        }
    }
    } // Box wrapper
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
    val dark = LocalDarkTheme.current
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }

    Surface(
        color = if (dark) Color(0xFF0D1014).copy(alpha = 0.85f)
                else Color.White.copy(alpha = 0.92f)
    ) {
        Column {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 4.dp, end = 4.dp, top = 2.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Geri / kapat butonu
                IconButton(onClick = onClose, modifier = Modifier.size(36.dp)) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Aramadan çık",
                        tint = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.size(20.dp)
                    )
                }

                // Arama alanı
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(40.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                            RoundedCornerShape(20.dp)
                        )
                        .padding(start = 14.dp, end = 6.dp),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(modifier = Modifier.weight(1f)) {
                            if (query.isEmpty()) {
                                Text(
                                    "Mesajlarda ara...",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                )
                            }
                            androidx.compose.foundation.text.BasicTextField(
                                value = query,
                                onValueChange = onQueryChange,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .focusRequester(focusRequester),
                                singleLine = true,
                                textStyle = MaterialTheme.typography.bodyMedium.copy(
                                    color = MaterialTheme.colorScheme.onSurface
                                ),
                                cursorBrush = androidx.compose.ui.graphics.SolidColor(MaterialTheme.colorScheme.primary)
                            )
                        }
                        if (query.isNotBlank()) {
                            IconButton(
                                onClick = { onQueryChange("") },
                                modifier = Modifier.size(32.dp)
                            ) {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = "Temizle",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(16.dp)
                                )
                            }
                        }
                    }
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
                        // Yukarı ok — daha eski mesaja git
                        IconButton(
                            onClick = onNext,
                            enabled = resultCount > 0 && currentIndex < resultCount - 1,
                            modifier = Modifier.size(40.dp)
                        ) {
                            Icon(
                                Icons.Default.KeyboardArrowUp,
                                contentDescription = "Daha eski sonuç",
                                tint = if (resultCount > 0 && currentIndex < resultCount - 1)
                                    MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f),
                                modifier = Modifier.size(28.dp)
                            )
                        }

                        // Aşağı ok — daha yeni mesaja git
                        IconButton(
                            onClick = onPrev,
                            enabled = resultCount > 0 && currentIndex > 0,
                            modifier = Modifier.size(40.dp)
                        ) {
                            Icon(
                                Icons.Default.KeyboardArrowDown,
                                contentDescription = "Daha yeni sonuç",
                                tint = if (resultCount > 0 && currentIndex > 0)
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
    val dark = LocalDarkTheme.current
    Box(
        modifier = modifier
            .glass(dark = dark, shape = RoundedCornerShape(100.dp))
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
                color = if (dark) Color(0xFFECEEF2).copy(alpha = 0.7f)
                        else Color(0xFF13161B).copy(alpha = 0.7f),
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
    val dark = LocalDarkTheme.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .glass(dark = dark, shape = RoundedCornerShape(100.dp))
        ) {
            Text(
                text = dateLabel,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                style = MaterialTheme.typography.labelSmall,
                color = if (dark) Color(0xFFECEEF2) else Color(0xFF13161B),
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
 * Son görülme zamanını kullanıcı dostu formata çevirir.
 * "az önce", "bugün HH:mm", "dün HH:mm" veya "d MMM HH:mm" formatında döner.
 */
private fun formatLastSeen(timestamp: Long): String {
    val now = System.currentTimeMillis()
    val diff = now - timestamp
    val cal = Calendar.getInstance().apply { timeInMillis = timestamp }
    val nowCal = Calendar.getInstance()
    val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())

    return when {
        diff < 60_000 -> "Son görülme: az önce"
        cal.get(Calendar.DAY_OF_YEAR) == nowCal.get(Calendar.DAY_OF_YEAR)
            && cal.get(Calendar.YEAR) == nowCal.get(Calendar.YEAR) ->
            "Son görülme: bugün ${sdf.format(Date(timestamp))}"
        diff < 86_400_000 * 2 -> "Son görülme: dün ${sdf.format(Date(timestamp))}"
        else -> {
            val dateSdf = SimpleDateFormat("d MMM HH:mm", Locale("tr"))
            "Son görülme: ${dateSdf.format(Date(timestamp))}"
        }
    }
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
    peerIsOnline: Boolean = false,
    peerLastSeen: Long? = null,
    disappearingDuration: Long = 0,
    isMuted: Boolean = false,
    onBackClick: () -> Unit,
    onVoiceCallClick: () -> Unit,
    onVideoCallClick: () -> Unit,
    onSearchClick: (() -> Unit)? = null,
    onDisappearingClick: (() -> Unit)? = null,
    onMuteToggle: (() -> Unit)? = null,
    onChatInfoClick: (() -> Unit)? = null
) {
    val dark = LocalDarkTheme.current
    var showMenu by remember { mutableStateOf(false) }
    Surface(
        color = if (dark) Color(0xFF0D1014).copy(alpha = 0.85f)
                else Color.White.copy(alpha = 0.92f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
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
                GeneratedAvatar(
                    name = peerName,
                    isGroup = isGroup,
                    size = 40.dp
                )
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
                            fontFamily = MonoFamily,
                            color = MaterialTheme.colorScheme.primary,
                            fontSize = 11.sp
                        )
                    } else if (isGroup && memberCount > 0) {
                        Text(
                            text = "$memberCount üye",
                            style = MaterialTheme.typography.labelSmall,
                            fontFamily = MonoFamily,
                            color = if (dark) Color(0xFF9BA3AE) else Color(0xFF5D6570),
                            fontSize = 11.sp
                        )
                    } else if (peerIsOnline) {
                        Text(
                            text = "çevrimiçi",
                            style = MaterialTheme.typography.labelSmall,
                            fontFamily = MonoFamily,
                            color = Color(0xFF22C55E),
                            fontSize = 11.sp
                        )
                    } else if (peerLastSeen != null && peerLastSeen > 0) {
                        Text(
                            text = formatLastSeen(peerLastSeen),
                            style = MaterialTheme.typography.labelSmall,
                            fontFamily = MonoFamily,
                            color = if (dark) Color(0xFF9BA3AE) else Color(0xFF5D6570),
                            fontSize = 11.sp
                        )
                    }
                }
            }

            // Aksiyon ikonları — küçültülmüş boyut
            IconButton(
                onClick = onVoiceCallClick,
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    Icons.Default.Call,
                    contentDescription = "Sesli Arama",
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(
                onClick = onVideoCallClick,
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    Icons.Default.Videocam,
                    contentDescription = "Görüntülü Arama",
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Daha fazla menü (arama, süreli mesaj vb.)
            Box {
                IconButton(
                    onClick = { showMenu = true },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        Icons.Default.MoreVert,
                        contentDescription = "Daha Fazla",
                        modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                DropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false }
                ) {
                    if (onSearchClick != null) {
                        DropdownMenuItem(
                            text = { Text("Sohbette Ara") },
                            onClick = {
                                showMenu = false
                                onSearchClick()
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Search,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = {
                            Text(
                                if (disappearingDuration > 0) "Süreli Mesajlar (Açık)" else "Süreli Mesajlar"
                            )
                        },
                        onClick = {
                            showMenu = false
                            onDisappearingClick?.invoke()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Schedule,
                                contentDescription = null,
                                tint = if (disappearingDuration > 0) MaterialTheme.colorScheme.primary
                                       else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    )
                    if (onMuteToggle != null) {
                        DropdownMenuItem(
                            text = { Text(if (isMuted) "Sesi Aç" else "Sessize Al") },
                            onClick = {
                                showMenu = false
                                onMuteToggle()
                            },
                            leadingIcon = {
                                Icon(
                                    if (isMuted) Icons.Default.Notifications else Icons.Default.NotificationsOff,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        )
                    }
                }
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
private fun chatAvatarColor(name: String): Color {
    val colors = listOf(
        Color(0xFF3E7BFA), // azure
        Color(0xFF6B737D), // slate
        Color(0xFF8A929C), // silver
        Color(0xFF5D6570), // graphite
        Color(0xFF4A535E), // charcoal
        Color(0xFF9BA3AE), // mist
        Color(0xFF7B8491), // pebble
        Color(0xFF556070), // steel
    )
    var h = 0
    for (c in name) h = (h * 31 + c.code) and 0x7FFFFFFF
    return colors[h % colors.size]
}

/**
 * Gönderen isim rengi — her isim için tutarlı renk üretir.
 * Azure tema ile uyumlu nötr + mavi tonlar.
 */
private fun senderNameColor(senderId: String): Color {
    val senderColors = listOf(
        Color(0xFF3E7BFA),
        Color(0xFF5EA3FF),
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
 * Azure glassmorphism stili.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MessageBubble(
    message: LocalMessage,
    isGroupChat: Boolean = false,
    memberNames: Map<String, String> = emptyMap(),
    isHighlighted: Boolean = false,
    searchQuery: String = "",
    replyToMessage: LocalMessage? = null,
    onDeleteMessage: (() -> Unit)? = null,
    onDeleteForEveryone: (() -> Unit)? = null,
    onEditMessage: ((String) -> Unit)? = null,
    onToggleStarMessage: ((String, Boolean) -> Unit)? = null,
    onForwardMessage: (() -> Unit)? = null,
    onReplyClick: ((String) -> Unit)? = null,
    onInfoClick: (() -> Unit)? = null,
    onReplyToMessage: (() -> Unit)? = null
) {
    val isOutgoing = message.isOutgoing
    val dark = LocalDarkTheme.current
    var showPopupMenu by remember { mutableStateOf(false) }

    // Azure tema balon renkleri
    val bubbleBg = if (isOutgoing) {
        if (dark) Color(0xFF3E7BFA).copy(alpha = 0.28f)
        else Color(0xFF3E7BFA).copy(alpha = 0.18f)
    } else {
        if (dark) Color(0xFF0F141C).copy(alpha = 0.55f)
        else Color(0xFF13161B).copy(alpha = 0.06f)
    }
    val bubbleBorder = if (isOutgoing) {
        if (dark) Color(0xFF5EA3FF).copy(alpha = 0.35f)
        else Color(0xFF3E7BFA).copy(alpha = 0.35f)
    } else {
        if (dark) Color.White.copy(alpha = 0.08f)
        else Color(0xFF13161B).copy(alpha = 0.09f)
    }
    val bubbleShape = if (isOutgoing)
        RoundedCornerShape(20.dp, 20.dp, 4.dp, 20.dp)
    else
        RoundedCornerShape(20.dp, 20.dp, 20.dp, 4.dp)

    // Highlight animasyonu
    val highlightColor by animateColorAsState(
        targetValue = if (isHighlighted) Color(0xFF3E7BFA).copy(alpha = 0.25f)
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
            Box(
                modifier = Modifier
                    .widthIn(max = 300.dp)
                    .background(bubbleBg, bubbleShape)
                    .border(1.dp, bubbleBorder, bubbleShape)
                    .clip(bubbleShape)
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
                    // Yanıtlanan mesaj önizlemesi — tıklayınca orijinal mesaja git
                    if (replyToMessage != null) {
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            color = if (isOutgoing)
                                MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                            else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                            modifier = Modifier
                                .padding(bottom = 4.dp)
                                .clickable {
                                    onReplyClick?.invoke(replyToMessage.id)
                                }
                        ) {
                            Row(modifier = Modifier.padding(6.dp)) {
                                Box(
                                    modifier = Modifier
                                        .width(3.dp)
                                        .height(32.dp)
                                        .background(
                                            MaterialTheme.colorScheme.primary,
                                            RoundedCornerShape(2.dp)
                                        )
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Column {
                                    Text(
                                        text = if (replyToMessage.isOutgoing) "Sen" else (memberNames[replyToMessage.senderId] ?: replyToMessage.senderId),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.primary,
                                        fontWeight = FontWeight.Bold,
                                        maxLines = 1
                                    )
                                    Text(
                                        text = if (replyToMessage.isDeleted) "Bu mesaj silindi" else replyToMessage.content,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }

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
                        modifier = Modifier.align(Alignment.End)
                    ) {
                        if (message.isEdited) {
                            Text(
                                text = "düzenlendi",
                                style = MaterialTheme.typography.labelSmall,
                                color = if (isOutgoing) {
                                    if (dark) Color.White.copy(alpha = 0.45f) else Color(0xFF1E52D9).copy(alpha = 0.45f)
                                } else {
                                    if (dark) Color(0xFF9BA3AE).copy(alpha = 0.5f) else Color(0xFF5D6570).copy(alpha = 0.5f)
                                },
                                fontSize = 10.sp
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                        }
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
                            color = if (isOutgoing) {
                                if (dark) Color.White.copy(alpha = 0.55f) else Color(0xFF1E52D9).copy(alpha = 0.55f)
                            } else {
                                if (dark) Color(0xFF9BA3AE).copy(alpha = 0.6f) else Color(0xFF5D6570).copy(alpha = 0.6f)
                            },
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
            com.securechat.app.ui.components.GlassDropdownMenu(
                expanded = showPopupMenu,
                onDismissRequest = { showPopupMenu = false }
            ) {
                // Yanitla
                if (onReplyToMessage != null) {
                    DropdownMenuItem(
                        text = { Text("Yanıtla") },
                        onClick = {
                            showPopupMenu = false
                            onReplyToMessage()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.AutoMirrored.Filled.Send,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.graphicsLayer(rotationZ = 180f)
                            )
                        }
                    )
                }

                // Kopyala (dosya mesaji degilse)
                if (!message.isFileMessage && !message.isDeleted) {
                    val clipboardManager = LocalClipboardManager.current
                    val clipContext = LocalContext.current
                    val coroutineScope = rememberCoroutineScope()
                    DropdownMenuItem(
                        text = { Text("Kopyala") },
                        onClick = {
                            showPopupMenu = false
                            clipboardManager.setText(androidx.compose.ui.text.AnnotatedString(message.content))
                            // Guvenlik: 60 sn sonra panoyu temizle
                            coroutineScope.launch {
                                kotlinx.coroutines.delay(60_000)
                                val cm = clipContext.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                                if (android.os.Build.VERSION.SDK_INT >= 28) {
                                    cm.clearPrimaryClip()
                                } else {
                                    cm.setPrimaryClip(android.content.ClipData.newPlainText("", ""))
                                }
                            }
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.ContentCopy,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurface
                            )
                        }
                    )
                }

                // Duzenle (sadece kendi TEXT mesajlari, 15 dakika icinde)
                if (onEditMessage != null && message.isOutgoing && !message.isFileMessage && !message.isDeleted) {
                    val canEdit = (System.currentTimeMillis() - message.timestamp) < 15 * 60 * 1000L
                    if (canEdit) {
                        DropdownMenuItem(
                            text = { Text("Düzenle") },
                            onClick = {
                                showPopupMenu = false
                                onEditMessage(message.content)
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Edit,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary
                                )
                            }
                        )
                    }
                }

                // Bilgi seçeneği (sadece grup giden mesajlarında)
                if (onInfoClick != null) {
                    DropdownMenuItem(
                        text = { Text("Bilgi") },
                        onClick = {
                            showPopupMenu = false
                            onInfoClick()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Info,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    )
                }

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

                // İlet
                if (onForwardMessage != null) {
                    DropdownMenuItem(
                        text = { Text("İlet") },
                        onClick = {
                            showPopupMenu = false
                            onForwardMessage()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.AutoMirrored.Filled.Send,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
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
    val dark = LocalDarkTheme.current
    val textColor = if (isOutgoing) {
        if (dark) Color.White else Color(0xFF1E52D9)
    } else {
        if (dark) Color(0xFFECEEF2) else Color(0xFF13161B)
    }

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
                color = Color(0xFF13161B),
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
    val dark = LocalDarkTheme.current
    val textColor = if (isOutgoing) {
        if (dark) Color.White else Color(0xFF1E52D9)
    } else {
        if (dark) Color(0xFFECEEF2) else Color(0xFF13161B)
    }

    val subtextColor = if (isOutgoing) {
        if (dark) Color.White.copy(alpha = 0.7f) else Color(0xFF1E52D9).copy(alpha = 0.7f)
    } else {
        if (dark) Color(0xFF9BA3AE) else Color(0xFF5D6570)
    }

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
            Color(0xFF3E7BFA)
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
        MessageStatus.READ -> Icons.Default.DoneAll to Color(0xFF3E7BFA)
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
    val dark = LocalDarkTheme.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .glass(dark = dark, shape = RoundedCornerShape(28.dp))
            .padding(start = 4.dp, end = 6.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        // Atasman butonu
        IconButton(
            onClick = onAttachClick,
            modifier = Modifier.size(40.dp)
        ) {
            Icon(
                Icons.Default.AttachFile,
                contentDescription = "Dosya ekle",
                tint = if (dark) Color(0xFF9BA3AE) else Color(0xFF5D6570),
                modifier = Modifier.size(22.dp)
            )
        }

        // Metin alani — BasicTextField ile minimal padding
        androidx.compose.foundation.text.BasicTextField(
            value = text,
            onValueChange = onTextChange,
            modifier = Modifier
                .weight(1f)
                .padding(vertical = 10.dp),
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = if (dark) Color(0xFFECEEF2) else Color(0xFF13161B)
            ),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(Color(0xFF3E7BFA)),
            maxLines = 4,
            decorationBox = { innerTextField ->
                if (text.isEmpty()) {
                    Text(
                        "Mesaj yazın...",
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (dark) Color(0xFF6B737D) else Color(0xFF8A929C)
                    )
                }
                innerTextField()
            }
        )

        Spacer(modifier = Modifier.width(6.dp))

        // Gonder butonu — azure daire
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(if (text.isNotBlank()) Color(0xFF3E7BFA) else Color(0xFF3E7BFA).copy(alpha = 0.5f))
                .clickable { if (text.isNotBlank()) onSend() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.AutoMirrored.Filled.Send,
                contentDescription = "Gönder",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}

/**
 * Ataşman menü seçenek butonu.
 */
@Composable
private fun AttachOption(
    icon: ImageVector,
    label: String,
    color: Color,
    dark: Boolean,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 4.dp)
    ) {
        Box(
            modifier = Modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(color.copy(alpha = if (dark) 0.2f else 0.12f))
                .border(1.dp, color.copy(alpha = 0.3f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                icon,
                contentDescription = label,
                tint = color,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = if (dark) Color(0xFFECEEF2) else Color(0xFF13161B)
        )
    }
}

/**
 * Mesaj duzenleme dialog'u. Mevcut mesaj icerigini gosterir ve kullanicinin duzenlemesine izin verir.
 */
@Composable
private fun EditMessageDialog(
    currentContent: String,
    onConfirm: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var editedText by remember { mutableStateOf(currentContent) }
    val dark = LocalDarkTheme.current

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Mesajı Düzenle") },
        text = {
            OutlinedTextField(
                value = editedText,
                onValueChange = { editedText = it },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 6,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Color(0xFF3E7BFA),
                    cursorColor = Color(0xFF3E7BFA)
                )
            )
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val trimmed = editedText.trim()
                    if (trimmed.isNotBlank() && trimmed != currentContent) {
                        onConfirm(trimmed)
                    } else {
                        onDismiss()
                    }
                }
            ) {
                Text("Kaydet", color = Color(0xFF3E7BFA))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("İptal")
            }
        }
    )
}

/**
 * Sağa sürükle ile yanıtlama jesti.
 * Mesaj sağa sürüklenince onSwipeReply tetiklenir.
 */
@Composable
private fun SwipeableMessageBubble(
    onSwipeReply: () -> Unit,
    content: @Composable () -> Unit
) {
    var offsetX by remember { mutableStateOf(0f) }
    val animatedOffset by animateFloatAsState(
        targetValue = offsetX,
        animationSpec = tween(durationMillis = if (offsetX == 0f) 200 else 0),
        label = "swipeOffset"
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .offset(x = (animatedOffset / 3f).dp)
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (offsetX > 150f) {
                            onSwipeReply()
                        }
                        offsetX = 0f
                    },
                    onDragCancel = { offsetX = 0f },
                    onHorizontalDrag = { _, dragAmount ->
                        if (dragAmount > 0) { // Sadece sağa sürükleme
                            offsetX = (offsetX + dragAmount).coerceIn(0f, 250f)
                        }
                    }
                )
            }
    ) {
        // Yanıtla ikonu (sürükleme sırasında göster)
        if (animatedOffset > 30f) {
            Icon(
                Icons.AutoMirrored.Filled.Send,
                contentDescription = "Yanıtla",
                tint = MaterialTheme.colorScheme.primary.copy(
                    alpha = (animatedOffset / 200f).coerceIn(0f, 1f)
                ),
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = 8.dp)
                    .size(20.dp)
            )
        }
        content()
    }
}

/**
 * Yanıtlama önizlemesi — metin alanının üstünde gösterilir.
 */
@Composable
private fun ReplyPreview(
    message: LocalMessage,
    senderName: String? = null,
    onDismiss: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.8f),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .padding(horizontal = 12.dp, vertical = 8.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(36.dp)
                    .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp))
            )
            Spacer(modifier = Modifier.width(8.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (message.isOutgoing) "Kendine yanıt" else (senderName ?: message.senderId),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = message.content,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            IconButton(onClick = onDismiss, modifier = Modifier.size(32.dp)) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "İptal",
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Mesaj iletme hedef secimi dialog'u.
 * Mevcut konusmalari ve arama ozelligini icerir.
 */
@Composable
fun ForwardPickerDialog(
    conversations: List<com.securechat.storage.domain.Conversation>,
    onConversationSelected: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var searchQuery by remember { mutableStateOf("") }
    val filtered = remember(conversations, searchQuery) {
        if (searchQuery.isBlank()) conversations
        else conversations.filter {
            it.peerName.contains(searchQuery, ignoreCase = true) ||
                it.peerId.contains(searchQuery, ignoreCase = true)
        }
    }

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text("Mesajı İlet", fontWeight = FontWeight.Bold)
        },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Arama
                androidx.compose.material3.OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    placeholder = { Text("Kişi veya grup ara...") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    leadingIcon = {
                        Icon(Icons.Default.Search, contentDescription = null)
                    }
                )
                Spacer(modifier = Modifier.height(8.dp))
                // Konusma listesi
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(300.dp)
                ) {
                    items(filtered, key = { it.id }) { conv ->
                        val displayName = conv.peerName.ifBlank { conv.peerId }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onConversationSelected(conv.peerId) }
                                .padding(vertical = 10.dp, horizontal = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            // Avatar
                            GeneratedAvatar(
                                name = displayName,
                                isGroup = conv.isGroup,
                                size = 40.dp
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text(
                                    text = displayName,
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                if (conv.lastMessage != null) {
                                    Text(
                                        text = conv.lastMessage!!,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                            thickness = 0.5.dp
                        )
                    }
                    if (filtered.isEmpty()) {
                        item {
                            Text(
                                text = "Konuşma bulunamadı",
                                modifier = Modifier.padding(16.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) {
                Text("İptal")
            }
        }
    )
}

/**
 * Mesaj zaman damgasını saat:dakika formatına çevirir.
 */
private fun formatTime(timestamp: Long): String {
    return TimeFormatter.formatTime(timestamp)
}

/**
 * Mesaj bilgi popup'ı -- grup mesajlarinin iletildi/okundu durumunu gosterir.
 */
@Composable
private fun MessageInfoPopup(
    message: LocalMessage,
    memberNames: Map<String, String>,
    groupMembers: List<String>,
    onDismiss: () -> Unit
) {
    com.securechat.app.ui.components.GlassDialog(
        onDismissRequest = onDismiss
    ) {
        Text(
            text = "Mesaj Bilgisi",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Okundu bolumu
        Text(
            text = "Okundu",
            style = MaterialTheme.typography.labelMedium,
            color = Color(0xFF3E7BFA),
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))

        if (message.status == com.securechat.storage.model.MessageStatus.READ) {
            groupMembers.filter { it != message.senderId }.forEach { memberId ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    GeneratedAvatar(
                        name = memberNames[memberId] ?: memberId,
                        size = 32.dp
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = memberNames[memberId] ?: memberId,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        } else {
            Text(
                text = "\u2014",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Iletildi bolumu
        Text(
            text = "\u0130letildi",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))

        if (message.status == com.securechat.storage.model.MessageStatus.DELIVERED) {
            groupMembers.filter { it != message.senderId }.forEach { memberId ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    GeneratedAvatar(
                        name = memberNames[memberId] ?: memberId,
                        size = 32.dp
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = memberNames[memberId] ?: memberId,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        } else if (message.status == com.securechat.storage.model.MessageStatus.SENT) {
            groupMembers.filter { it != message.senderId }.forEach { memberId ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    GeneratedAvatar(
                        name = memberNames[memberId] ?: memberId,
                        size = 32.dp
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = memberNames[memberId] ?: memberId,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            Text(
                text = "\u2014",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Kapat butonu
        androidx.compose.material3.TextButton(
            onClick = onDismiss,
            modifier = Modifier.align(Alignment.End)
        ) {
            Text("Kapat", color = MaterialTheme.colorScheme.primary)
        }
    }
}
