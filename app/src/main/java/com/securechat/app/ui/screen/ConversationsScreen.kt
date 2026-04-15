package com.securechat.app.ui.screen

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SyncProblem
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.viewmodel.ConversationsViewModel
import com.securechat.app.util.TimeFormatter
import com.securechat.network.model.ConnectionState
import com.securechat.storage.domain.Conversation
import kotlin.math.abs

/**
 * Konusma listesi ana ekrani.
 * Tum aktif konusmalari gosterir, yeni sohbet baslama FAB'i ve ayarlar erisimi saglar.
 * Arama cubugu, gradient avatar'lar, divider'lar, gelismis bos durum tasarimi,
 * swipe-to-delete ve uzun basma ile silme menuleri icerir.
 *
 * Midnight Teal tasarim: koyu arka plan, cyan vurgular, ince alt border'li top bar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationsScreen(
    viewModel: ConversationsViewModel = hiltViewModel(),
    onConversationClick: (String) -> Unit,
    onConversationInfoClick: (Conversation) -> Unit = {},
    onNewChat: () -> Unit,
    onNewGroup: () -> Unit = {},
    onSettingsClick: () -> Unit,
    onCallHistoryClick: () -> Unit = {}
) {
    val conversations by viewModel.conversations.collectAsStateWithLifecycle()
    val archivedConversations by viewModel.archivedConversations.collectAsStateWithLifecycle()
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    val typingStates by com.securechat.app.data.IncomingMessageHandler.typingStates.collectAsStateWithLifecycle()
    var searchQuery by remember { mutableStateOf("") }
    var isSearchVisible by remember { mutableStateOf(false) }
    var showArchived by remember { mutableStateOf(false) }

    // Silme onay diyalogu durumu
    var conversationToDelete by remember { mutableStateOf<Conversation?>(null) }

    // Contact names'leri güncelle
    LaunchedEffect(Unit) {
        viewModel.updateContactNames()
    }

    // Silme onay diyalogu
    conversationToDelete?.let { conversation ->
        DeleteConversationDialog(
            conversationName = conversation.peerName,
            onConfirm = {
                viewModel.deleteConversation(conversation.id)
                conversationToDelete = null
            },
            onDismiss = { conversationToDelete = null }
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "ELÇİM",
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                },
                actions = {
                    IconButton(onClick = onCallHistoryClick) {
                        Icon(
                            Icons.Default.Call,
                            contentDescription = "Arama Geçmişi",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    IconButton(onClick = onNewGroup) {
                        Icon(
                            Icons.Default.GroupAdd,
                            contentDescription = "Yeni Grup",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    IconButton(onClick = { isSearchVisible = !isSearchVisible }) {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = "Ara",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    IconButton(onClick = onSettingsClick) {
                        Icon(
                            Icons.Default.Settings,
                            contentDescription = "Ayarlar",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.onSurface
                ),
                modifier = Modifier.drawBehind {
                    // Ince alt border — outline rengiyle
                    drawLine(
                        color = Color(0xFF30363D),
                        start = Offset(0f, size.height),
                        end = Offset(size.width, size.height),
                        strokeWidth = 1f
                    )
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = onNewChat,
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = Color(0xFF0D1117)
            ) {
                Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = "Yeni Sohbet")
            }
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(modifier = Modifier.padding(padding)) {
            // Baglanti durumu banner'i
            if (connectionState != ConnectionState.Connected) {
                ConnectionStatusBanner(state = connectionState)
            }

            // Arama cubugu
            if (isSearchVisible) {
                SearchBar(
                    query = searchQuery,
                    onQueryChange = { searchQuery = it }
                )
            }

            if (showArchived) {
                // Arşiv ekranı
                ArchivedConversationsContent(
                    archivedConversations = archivedConversations,
                    onConversationClick = onConversationClick,
                    onUnarchive = { viewModel.unarchiveConversation(it.id) },
                    onDeleteRequest = { conversationToDelete = it },
                    onBackClick = { showArchived = false }
                )
            } else {
                val filteredConversations = if (searchQuery.isBlank()) {
                    conversations
                } else {
                    conversations.filter {
                        it.peerName.contains(searchQuery, ignoreCase = true) ||
                            (it.lastMessage?.contains(searchQuery, ignoreCase = true) ?: false)
                    }
                }

                if (filteredConversations.isEmpty() && archivedConversations.isEmpty()) {
                    EmptyConversationsState(
                        isSearching = searchQuery.isNotBlank()
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize()
                    ) {
                        // Arşiv banner'ı (arşivlenmiş sohbet varsa göster)
                        if (archivedConversations.isNotEmpty() && searchQuery.isBlank()) {
                            item(key = "archive_banner") {
                                ArchiveBanner(
                                    count = archivedConversations.size,
                                    onClick = { showArchived = true }
                                )
                                HorizontalDivider(
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                                    thickness = 0.5.dp
                                )
                            }
                        }

                        if (filteredConversations.isEmpty() && searchQuery.isNotBlank()) {
                            item {
                                EmptyConversationsState(isSearching = true)
                            }
                        } else {
                            items(filteredConversations, key = { it.id }) { conversation ->
                                SwipeableConversationItem(
                                    conversation = conversation,
                                    isTyping = typingStates[conversation.peerId] == true,
                                    onClick = { onConversationClick(conversation.id) },
                                    onInfoClick = { onConversationInfoClick(conversation) },
                                    onDeleteRequest = { conversationToDelete = conversation },
                                    onArchiveRequest = { viewModel.archiveConversation(conversation.id) }
                                )
                                HorizontalDivider(
                                    modifier = Modifier.padding(start = 80.dp),
                                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                                    thickness = 0.5.dp
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Konusma silme onay diyalogu.
 * Kullaniciyi geri donulemez silme islemi hakkinda uyarir.
 */
@Composable
private fun DeleteConversationDialog(
    conversationName: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text("Sohbeti Sil")
        },
        text = {
            Text("\"$conversationName\" ile olan sohbeti silmek istediğinize emin misiniz? Bu işlem geri alınamaz.")
        },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(
                    "Sil",
                    color = MaterialTheme.colorScheme.error
                )
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
 * Swipe-to-delete ve uzun basma menusu olan konusma satiri.
 * Sola kaydirildiginda kirmizi "Sil" arka plani gosterir.
 * Uzun basildiginda "Sil" secenegi iceren dropdown menu acar.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SwipeableConversationItem(
    conversation: Conversation,
    isTyping: Boolean = false,
    onClick: () -> Unit,
    onInfoClick: (() -> Unit)? = null,
    onDeleteRequest: () -> Unit,
    onArchiveRequest: (() -> Unit)? = null
) {
    var showContextMenu by remember { mutableStateOf(false) }

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { dismissValue ->
            if (dismissValue == SwipeToDismissBoxValue.EndToStart) {
                onDeleteRequest()
                false
            } else if (dismissValue == SwipeToDismissBoxValue.StartToEnd) {
                onArchiveRequest?.invoke()
                false
            } else {
                false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            if (direction == SwipeToDismissBoxValue.StartToEnd) {
                // Saga kaydirma — arsivleme
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFF00897B)),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(
                        modifier = Modifier.padding(start = 24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Archive,
                            contentDescription = "Arşivle",
                            tint = Color.White
                        )
                        Text(
                            text = "Arşivle",
                            color = Color.White,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            } else {
                // Sola kaydirma — silme
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.error),
                    contentAlignment = Alignment.CenterEnd
                ) {
                    Row(
                        modifier = Modifier.padding(end = 24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "Sil",
                            tint = MaterialTheme.colorScheme.onError
                        )
                        Text(
                            text = "Sil",
                            color = MaterialTheme.colorScheme.onError,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        },
        enableDismissFromStartToEnd = onArchiveRequest != null,
        enableDismissFromEndToStart = true
    ) {
        Surface(
            color = MaterialTheme.colorScheme.background
        ) {
            Box {
                ConversationItem(
                    conversation = conversation,
                    isTyping = isTyping,
                    onClick = onClick,
                    onLongClick = { showContextMenu = true }
                )

                DropdownMenu(
                    expanded = showContextMenu,
                    onDismissRequest = { showContextMenu = false }
                ) {
                    if (onInfoClick != null) {
                        DropdownMenuItem(
                            text = { Text("Bilgi") },
                            onClick = {
                                showContextMenu = false
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
                    if (onArchiveRequest != null) {
                        DropdownMenuItem(
                            text = { Text("Arşivle") },
                            onClick = {
                                showContextMenu = false
                                onArchiveRequest()
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Archive,
                                    contentDescription = null,
                                    tint = Color(0xFF00897B)
                                )
                            }
                        )
                    }
                    DropdownMenuItem(
                        text = {
                            Text(
                                "Sohbeti Sil",
                                color = MaterialTheme.colorScheme.error
                            )
                        },
                        onClick = {
                            showContextMenu = false
                            onDeleteRequest()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error
                            )
                        }
                    )
                }
            }
        }
    }
}

/**
 * Arama cubugu composable'i.
 * Koyu surfaceVariant arka planli, cyan odak halkali arama cubugu.
 */
@Composable
private fun SearchBar(
    query: String,
    onQueryChange: (String) -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.background
    ) {
        TextField(
            value = query,
            onValueChange = onQueryChange,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            placeholder = {
                Text(
                    "Sohbetlerde ara...",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            leadingIcon = {
                Icon(
                    Icons.Default.Search,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            },
            shape = RoundedCornerShape(24.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent,
                cursorColor = MaterialTheme.colorScheme.primary
            ),
            singleLine = true
        )
    }
}

/**
 * Bos konusma durumu.
 * Arama yapiliyorsa farkli mesaj gosterir, yoksa genel bos durum mesaji gosterir.
 */
@Composable
private fun EmptyConversationsState(isSearching: Boolean) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.padding(48.dp)
        ) {
            // Bos durum ikonu — cyan tonlu
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Forum,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            Text(
                text = if (isSearching) "Sonuç bulunamadı" else "Henüz bir sohbet yok",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = if (isSearching) {
                    "Farklı bir arama terimi deneyin."
                } else {
                    "Yeni sohbet başlatmak için\nsağ alttaki butona dokunun."
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

/**
 * Avatar icin isim bazli gradient renk paleti olusturur.
 * Midnight Teal ile uyumlu, daha koyu ve canli gradient ciftleri.
 */
private fun avatarGradientForName(name: String): Brush {
    val avatarColorPairs = listOf(
        Color(0xFF00897B) to Color(0xFF004D40),
        Color(0xFF00ACC1) to Color(0xFF006064),
        Color(0xFF5C6BC0) to Color(0xFF283593),
        Color(0xFF7E57C2) to Color(0xFF4527A0),
        Color(0xFFEF5350) to Color(0xFFB71C1C),
        Color(0xFFFF7043) to Color(0xFFBF360C),
        Color(0xFF26A69A) to Color(0xFF00695C),
        Color(0xFF42A5F5) to Color(0xFF1565C0),
        Color(0xFFEC407A) to Color(0xFF880E4F),
        Color(0xFF66BB6A) to Color(0xFF2E7D32)
    )
    val index = abs(name.hashCode()) % avatarColorPairs.size
    val (startColor, endColor) = avatarColorPairs[index]
    return Brush.linearGradient(colors = listOf(startColor, endColor))
}

/**
 * Konusma listesindeki tek bir konusma satiri.
 * Gradient avatar, isim, son mesaj, goreli zaman ve okunmamis mesaj sayisi gosterir.
 * Uzun basma destegi icerir.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ConversationItem(
    conversation: Conversation,
    isTyping: Boolean = false,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick
            )
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Gradient avatar — grup ise grup ikonu, birebir ise bas harf
        Box(
            modifier = Modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(avatarGradientForName(conversation.peerName)),
            contentAlignment = Alignment.Center
        ) {
            if (conversation.isGroup) {
                Icon(
                    imageVector = Icons.Default.Group,
                    contentDescription = "Grup",
                    tint = Color.White,
                    modifier = Modifier.size(28.dp)
                )
            } else {
                Text(
                    text = conversation.peerName.firstOrNull()?.uppercase() ?: "?",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 20.sp
                )
            }
        }

        Spacer(modifier = Modifier.width(16.dp))

        // Isim ve son mesaj
        Column(
            modifier = Modifier.weight(1f)
        ) {
            Text(
                text = conversation.peerName,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = if (conversation.unreadCount > 0) FontWeight.Bold else FontWeight.Normal,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )

            Spacer(modifier = Modifier.height(2.dp))

            if (isTyping) {
                Text(
                    text = "yazıyor...",
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    color = MaterialTheme.colorScheme.primary
                )
            } else {
                Text(
                    text = conversation.lastMessage ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = if (conversation.unreadCount > 0)
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f)
                    else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        // Zaman ve okunmamis sayisi
        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = formatTimestamp(conversation.lastMessageTimestamp),
                style = MaterialTheme.typography.labelSmall,
                color = if (conversation.unreadCount > 0)
                    MaterialTheme.colorScheme.secondary
                else MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 12.sp
            )
            if (conversation.unreadCount > 0) {
                Spacer(modifier = Modifier.height(4.dp))
                Badge(
                    containerColor = MaterialTheme.colorScheme.secondary,
                    contentColor = Color.White
                ) {
                    Text(
                        "${conversation.unreadCount}",
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

/**
 * Baglanti durumu banner'i.
 * Koyu arka plan, renkli sol border ile uyari gosterir (Midnight Teal stili).
 */
@Composable
fun ConnectionStatusBanner(state: ConnectionState) {
    val (text, icon, baseColor) = when (state) {
        is ConnectionState.Connecting -> Triple(
            "Bağlanılıyor...",
            Icons.Default.SyncProblem,
            Color(0xFFFFA726)
        )
        is ConnectionState.Error -> Triple(
            "Bağlantı hatası",
            Icons.Default.WifiOff,
            MaterialTheme.colorScheme.error
        )
        is ConnectionState.Disconnected -> Triple(
            "Bağlantı kesildi",
            Icons.Default.CloudOff,
            MaterialTheme.colorScheme.error
        )
        is ConnectionState.Connected -> return
    }

    val animatedColor by animateColorAsState(
        targetValue = baseColor,
        animationSpec = tween(500),
        label = "bannerColor"
    )

    // Koyu arka plan, sol kenarda renkli border
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .drawBehind {
                    // Sol kenarda renkli border ciz
                    drawRect(
                        color = animatedColor,
                        topLeft = Offset(0f, 0f),
                        size = androidx.compose.ui.geometry.Size(4.dp.toPx(), size.height)
                    )
                }
                .padding(start = 12.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = animatedColor
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = text,
                style = MaterialTheme.typography.labelMedium,
                color = animatedColor,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

/**
 * Arşiv banner'ı — arşivlenmiş sohbet sayısını gösterir.
 */
@Composable
private fun ArchiveBanner(
    count: Int,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.Archive,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp)
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = "Arşivlenmiş",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

/**
 * Arşivlenmiş sohbetler ekranı.
 */
@Composable
private fun ArchivedConversationsContent(
    archivedConversations: List<Conversation>,
    onConversationClick: (String) -> Unit,
    onUnarchive: (Conversation) -> Unit,
    onDeleteRequest: (Conversation) -> Unit,
    onBackClick: () -> Unit
) {
    androidx.activity.compose.BackHandler(onBack = onBackClick)

    Column(modifier = Modifier.fillMaxSize()) {
        // Üst bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBackClick) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Geri",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            }
            Text(
                text = "Arşivlenmiş Sohbetler",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
        HorizontalDivider(
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
            thickness = 0.5.dp
        )

        if (archivedConversations.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        Icons.Default.Archive,
                        contentDescription = null,
                        modifier = Modifier.size(48.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = "Arşivlenmiş sohbet yok",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                    )
                }
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(archivedConversations, key = { it.id }) { conversation ->
                    ArchivedConversationItem(
                        conversation = conversation,
                        onClick = { onConversationClick(conversation.id) },
                        onUnarchive = { onUnarchive(conversation) },
                        onDeleteRequest = { onDeleteRequest(conversation) }
                    )
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 80.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        thickness = 0.5.dp
                    )
                }
            }
        }
    }
}

/**
 * Arşivlenmiş sohbet satırı — uzun basma ile arşivden çıkarma ve silme menüsü.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ArchivedConversationItem(
    conversation: Conversation,
    onClick: () -> Unit,
    onUnarchive: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    var showContextMenu by remember { mutableStateOf(false) }

    Box {
        ConversationItem(
            conversation = conversation,
            onClick = onClick,
            onLongClick = { showContextMenu = true }
        )

        DropdownMenu(
            expanded = showContextMenu,
            onDismissRequest = { showContextMenu = false }
        ) {
            DropdownMenuItem(
                text = { Text("Arşivden Çıkar") },
                onClick = {
                    showContextMenu = false
                    onUnarchive()
                },
                leadingIcon = {
                    Icon(
                        Icons.Default.Unarchive,
                        contentDescription = null,
                        tint = Color(0xFF00897B)
                    )
                }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        "Sil",
                        color = MaterialTheme.colorScheme.error
                    )
                },
                onClick = {
                    showContextMenu = false
                    onDeleteRequest()
                },
                leadingIcon = {
                    Icon(
                        Icons.Default.Delete,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            )
        }
    }
}

/**
 * Konusma listesinde gosterilecek sekilde zaman damgasini formatlar.
 */
private fun formatTimestamp(timestamp: Long?): String {
    return TimeFormatter.formatTimestamp(timestamp)
}
