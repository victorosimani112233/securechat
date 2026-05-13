package com.securechat.app.ui.screen

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SyncProblem
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Badge
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.components.GlassDialog
import com.securechat.app.ui.components.GlassDropdownMenu
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.DisplayFamily
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.viewmodel.ConversationsViewModel
import com.securechat.network.model.ConnectionState
import com.securechat.storage.domain.Conversation

/** Sohbet filtre tipleri. */
private enum class ConversationFilter { NONE, UNREAD, GROUPS, FAVORITES }

/**
 * Konusma listesi ana ekrani.
 * Alt navigasyon bar, filtre chip'leri, favori/arsiv destegi, swipe aksiyonlari.
 * Azure glassmorphism tasarim.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun ConversationsScreen(
    viewModel: ConversationsViewModel = hiltViewModel(),
    onConversationClick: (String) -> Unit,
    onConversationInfoClick: (Conversation) -> Unit = {},
    onNewChat: () -> Unit,
    onNewGroup: () -> Unit = {},
    onScheduledMessages: () -> Unit = {},
    onBulkMessage: () -> Unit = {},
    onSettingsClick: () -> Unit,
    @Suppress("UNUSED_PARAMETER") onCallHistoryClick: () -> Unit = {},
    @Suppress("UNUSED_PARAMETER") onContactsClick: () -> Unit = onNewChat,
    onCallReadinessClick: () -> Unit = onSettingsClick
) {
    val conversations by viewModel.conversations.collectAsStateWithLifecycle()
    val archivedConversations by viewModel.archivedConversations.collectAsStateWithLifecycle()
    val connectionState by viewModel.connectionState.collectAsStateWithLifecycle()
    val typingStates by com.securechat.app.data.IncomingMessageHandler.typingStates.collectAsStateWithLifecycle()
    val globalSearchResults by viewModel.globalSearchResults.collectAsStateWithLifecycle()

    var searchQuery by remember { mutableStateOf("") }
    var isSearchVisible by remember { mutableStateOf(false) }
    var showConnectionInfo by remember { mutableStateOf(false) }
    var showArchived by remember { mutableStateOf(false) }
    var activeFilter by remember { mutableStateOf(ConversationFilter.NONE) }
    var conversationToDelete by remember { mutableStateOf<Conversation?>(null) }

    // Biyometrik kilit — kilitli sohbet tiklandiginda dogrulama iste
    val context = androidx.compose.ui.platform.LocalContext.current
    // Context ContextThemeWrapper olabilir — FragmentActivity'yi unwrap et
    val activity = remember(context) {
        var ctx: android.content.Context = context
        while (ctx is android.content.ContextWrapper) {
            if (ctx is androidx.fragment.app.FragmentActivity) return@remember ctx
            ctx = ctx.baseContext
        }
        null
    }

    // Kilitli sohbet kontrolu ile navigate
    val handleConversationClick: (Conversation) -> Unit = { conversation ->
        if (conversation.isLocked && activity != null) {
            val convId = conversation.id
            val biometricManager = androidx.biometric.BiometricManager.from(context)
            val canBiometric = biometricManager.canAuthenticate(
                androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
            ) == androidx.biometric.BiometricManager.BIOMETRIC_SUCCESS
            val canDeviceCredential = biometricManager.canAuthenticate(
                androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
            ) == androidx.biometric.BiometricManager.BIOMETRIC_SUCCESS

            if (!canBiometric && !canDeviceCredential) {
                // Telefonda hicbir kilit yontemi yok — direkt gir
                onConversationClick(convId)
            } else {
                val authenticators = when {
                    canBiometric && canDeviceCredential ->
                        androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    canDeviceCredential ->
                        androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    else ->
                        androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
                }

                val builder = androidx.biometric.BiometricPrompt.PromptInfo.Builder()
                    .setTitle("Kilitli Sohbet")
                    .setSubtitle("Bu sohbete erişmek için kimliğinizi doğrulayın")
                    .setAllowedAuthenticators(authenticators)
                // DEVICE_CREDENTIAL varsa negativeButtonText kullanilamaz
                if (!canDeviceCredential) {
                    builder.setNegativeButtonText("İptal")
                }
                val promptInfo = builder.build()

                val biometricPrompt = androidx.biometric.BiometricPrompt(
                    activity,
                    androidx.core.content.ContextCompat.getMainExecutor(context),
                    object : androidx.biometric.BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(result: androidx.biometric.BiometricPrompt.AuthenticationResult) {
                            onConversationClick(convId)
                        }
                        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                            // Kullanici iptal etti
                        }
                        override fun onAuthenticationFailed() {
                            // Tekrar deneme — prompt kapanmaz
                        }
                    }
                )
                biometricPrompt.authenticate(promptInfo)
            }
        } else {
            onConversationClick(conversation.id)
        }
    }

    LaunchedEffect(Unit) { viewModel.updateContactNames() }

    // Arama sorgusunu global arama icin tetikle
    LaunchedEffect(searchQuery) {
        if (searchQuery.length >= 2) {
            viewModel.searchGlobal(searchQuery)
        } else {
            viewModel.clearGlobalSearch()
        }
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

    val dark = LocalDarkTheme.current

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.combinedClickable(
                                onClick = {},
                                onLongClick = { viewModel.createTestConversation() }
                            )
                        ) {
                            Text(
                                "elçim",
                                fontFamily = DisplayFamily,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 22.sp,
                                letterSpacing = (-0.5).sp,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Text(
                                ".",
                                fontFamily = DisplayFamily,
                                fontWeight = FontWeight.Bold,
                                fontSize = 22.sp,
                                color = MaterialTheme.colorScheme.primary
                            )
                            if (connectionState != ConnectionState.Connected) {
                                Spacer(modifier = Modifier.width(6.dp))
                                val (icon, color) = when (connectionState) {
                                    is ConnectionState.Connecting -> Icons.Default.SyncProblem to Color(0xFFFFA726)
                                    is ConnectionState.Error -> Icons.Default.WifiOff to MaterialTheme.colorScheme.error
                                    is ConnectionState.Disconnected -> Icons.Default.CloudOff to MaterialTheme.colorScheme.error
                                    else -> Icons.Default.CloudOff to MaterialTheme.colorScheme.error
                                }
                                Box {
                                    IconButton(
                                        onClick = { showConnectionInfo = true },
                                        modifier = Modifier.size(28.dp)
                                    ) {
                                        Icon(
                                            icon,
                                            contentDescription = "Bağlantı durumu",
                                            tint = color,
                                            modifier = Modifier.size(18.dp)
                                        )
                                    }
                                    GlassDropdownMenu(
                                        expanded = showConnectionInfo,
                                        onDismissRequest = { showConnectionInfo = false }
                                    ) {
                                        val statusText = when (connectionState) {
                                            is ConnectionState.Connecting -> "Sunucuya bağlanılıyor..."
                                            is ConnectionState.Error -> "Bağlantı hatası oluştu"
                                            is ConnectionState.Disconnected -> "Sunucu bağlantısı kesildi"
                                            else -> ""
                                        }
                                        Row(
                                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                                        ) {
                                            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
                                            Text(
                                                statusText,
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.onSurface
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    },
                    actions = {
                        IconButton(onClick = {
                            isSearchVisible = !isSearchVisible
                            if (!isSearchVisible) searchQuery = ""
                        }) {
                            Icon(
                                if (isSearchVisible) Icons.Default.Close else Icons.Default.Search,
                                contentDescription = "Ara",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        // Uc nokta menu
                        var showMoreMenu by remember { mutableStateOf(false) }
                        Box {
                            IconButton(onClick = { showMoreMenu = true }) {
                                Icon(
                                    Icons.Default.MoreVert,
                                    contentDescription = "Daha Fazla",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            GlassDropdownMenu(
                                expanded = showMoreMenu,
                                onDismissRequest = { showMoreMenu = false }
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Yeni Sohbet") },
                                    onClick = { showMoreMenu = false; onNewChat() },
                                    leadingIcon = {
                                        Icon(Icons.Default.PersonAdd, null, modifier = Modifier.size(20.dp))
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Yeni Grup") },
                                    onClick = { showMoreMenu = false; onNewGroup() },
                                    leadingIcon = {
                                        Icon(Icons.Default.GroupAdd, null, modifier = Modifier.size(20.dp))
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Toplu Mesaj") },
                                    onClick = { showMoreMenu = false; onBulkMessage() },
                                    leadingIcon = {
                                        Icon(Icons.AutoMirrored.Filled.Chat, null, modifier = Modifier.size(20.dp))
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Planlı Mesajlar") },
                                    onClick = { showMoreMenu = false; onScheduledMessages() },
                                    leadingIcon = {
                                        Icon(Icons.Default.EditCalendar, null, modifier = Modifier.size(20.dp))
                                    }
                                )
                            }
                        }
                    },
                    windowInsets = WindowInsets(0),
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = Color.Transparent,
                        titleContentColor = MaterialTheme.colorScheme.onSurface
                    )
                )
            },
            containerColor = Color.Transparent,
            contentWindowInsets = WindowInsets(0)
        ) { padding ->
            Column(modifier = Modifier.padding(padding)) {
                // Arama cubugu — toggle ile acilir
                AnimatedVisibility(
                    visible = isSearchVisible,
                    enter = expandVertically(),
                    exit = shrinkVertically()
                ) {
                    GlassSearchBar(
                        query = searchQuery,
                        onQueryChange = { searchQuery = it },
                        dark = dark
                    )
                }

                if (showArchived) {
                    ArchivedConversationsContent(
                        archivedConversations = archivedConversations,
                        onConversationClick = onConversationClick,
                        onUnarchive = { viewModel.unarchiveConversation(it.id) },
                        onDeleteRequest = { conversationToDelete = it },
                        onBackClick = { showArchived = false }
                    )
                } else {
                    // Filtre chip'leri
                    FilterChipRow(
                        activeFilter = activeFilter,
                        onFilterChange = { f ->
                            activeFilter = f
                        }
                    )

                    // Filtre uygula — remember ile memoize et, gereksiz recomposition hesaplamasini onle
                    val filtered = remember(conversations, searchQuery, activeFilter) {
                        var result = conversations
                        if (searchQuery.isNotBlank()) {
                            result = result.filter {
                                it.peerName.contains(searchQuery, ignoreCase = true) ||
                                    (it.lastMessage?.contains(searchQuery, ignoreCase = true) ?: false)
                            }
                        }
                        when (activeFilter) {
                            ConversationFilter.UNREAD -> result.filter { it.unreadCount > 0 }
                            ConversationFilter.GROUPS -> result.filter { it.isGroup }
                            ConversationFilter.FAVORITES -> result.filter { it.isFavorite }
                            ConversationFilter.NONE -> result
                        }
                    }

                    // Konusma ID -> isim esleme — global arama sonuclari icin
                    val convNameMap = remember(conversations, archivedConversations) {
                        (conversations + archivedConversations).associate { it.id to it.peerName }
                    }

                    if (filtered.isEmpty() && archivedConversations.isEmpty() && searchQuery.isBlank() && activeFilter == ConversationFilter.NONE && globalSearchResults.isEmpty()) {
                        EmptyConversationsState(isSearching = false)
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            // Call readiness banner — eksik izin varsa goster
                            item(key = "call_readiness_banner") {
                                com.securechat.app.ui.components.CallReadinessBanner(
                                    onClick = onCallReadinessClick
                                )
                            }

                            // Arsiv banner
                            if (archivedConversations.isNotEmpty() && searchQuery.isBlank() && activeFilter == ConversationFilter.NONE) {
                                item(key = "archive_banner") {
                                    ArchiveBanner(
                                        count = archivedConversations.size,
                                        onClick = { showArchived = true }
                                    )
                                }
                            }

                            if (filtered.isEmpty() && globalSearchResults.isEmpty()) {
                                item {
                                    EmptyConversationsState(
                                        isSearching = searchQuery.isNotBlank() || activeFilter != ConversationFilter.NONE
                                    )
                                }
                            } else {
                                if (filtered.isNotEmpty()) {
                                    items(filtered, key = { it.id }) { conversation ->
                                        SwipeableConversationItem(
                                            conversation = conversation,
                                            isTyping = typingStates[conversation.peerId] == true,
                                            onClick = { handleConversationClick(conversation) },
                                            onInfoClick = { onConversationInfoClick(conversation) },
                                            onDeleteRequest = { conversationToDelete = conversation },
                                            onArchiveRequest = { viewModel.archiveConversation(conversation.id) },
                                            onFavoriteToggle = { viewModel.toggleFavorite(conversation.id, !conversation.isFavorite) },
                                            onMuteToggle = { viewModel.toggleMuted(conversation.id, !conversation.isMuted) }
                                        )
                                    }
                                }

                                // Global mesaj arama sonuclari
                                if (globalSearchResults.isNotEmpty() && searchQuery.length >= 2) {
                                    item(key = "global_search_header") {
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .padding(horizontal = 4.dp, vertical = 8.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Icon(
                                                Icons.Default.Forum,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.primary,
                                                modifier = Modifier.size(18.dp)
                                            )
                                            Spacer(modifier = Modifier.width(8.dp))
                                            Text(
                                                "Mesajlarda",
                                                style = MaterialTheme.typography.labelLarge,
                                                color = MaterialTheme.colorScheme.primary,
                                                fontWeight = FontWeight.SemiBold
                                            )
                                            Spacer(modifier = Modifier.width(6.dp))
                                            Badge(
                                                containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                                                contentColor = MaterialTheme.colorScheme.primary
                                            ) {
                                                Text("${globalSearchResults.size}", fontSize = 11.sp, fontWeight = FontWeight.Bold)
                                            }
                                        }
                                    }
                                    items(globalSearchResults, key = { "msg_${it.id}" }) { message ->
                                        GlobalSearchResultItem(
                                            message = message,
                                            conversationName = convNameMap[message.conversationId] ?: message.conversationId,
                                            searchQuery = searchQuery,
                                            onClick = { onConversationClick(message.conversationId) }
                                        )
                                    }
                                    item(key = "global_search_spacer") {
                                        Spacer(modifier = Modifier.height(80.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ─── Filtre chip'leri ────────────────────────────────────────────────

@Composable
private fun FilterChipRow(
    activeFilter: ConversationFilter,
    onFilterChange: (ConversationFilter) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        FilterChip(
            selected = activeFilter == ConversationFilter.NONE,
            onClick = { onFilterChange(ConversationFilter.NONE) },
            label = { Text("Tümü", fontSize = 13.sp) },
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                selectedLabelColor = MaterialTheme.colorScheme.primary,
                containerColor = Color.Transparent,
                labelColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            border = FilterChipDefaults.filterChipBorder(
                borderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                selectedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                enabled = true,
                selected = activeFilter == ConversationFilter.NONE
            )
        )
        FilterChip(
            selected = activeFilter == ConversationFilter.UNREAD,
            onClick = { onFilterChange(ConversationFilter.UNREAD) },
            label = { Text("Okunmamış", fontSize = 13.sp) },
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                selectedLabelColor = MaterialTheme.colorScheme.primary,
                containerColor = Color.Transparent,
                labelColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            border = FilterChipDefaults.filterChipBorder(
                borderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                selectedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                enabled = true,
                selected = activeFilter == ConversationFilter.UNREAD
            )
        )
        FilterChip(
            selected = activeFilter == ConversationFilter.GROUPS,
            onClick = { onFilterChange(ConversationFilter.GROUPS) },
            label = { Text("Gruplar", fontSize = 13.sp) },
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                selectedLabelColor = MaterialTheme.colorScheme.primary,
                containerColor = Color.Transparent,
                labelColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            border = FilterChipDefaults.filterChipBorder(
                borderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                selectedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                enabled = true,
                selected = activeFilter == ConversationFilter.GROUPS
            )
        )
        FilterChip(
            selected = activeFilter == ConversationFilter.FAVORITES,
            onClick = { onFilterChange(ConversationFilter.FAVORITES) },
            label = { Text("Favoriler", fontSize = 13.sp) },
            leadingIcon = if (activeFilter == ConversationFilter.FAVORITES) {
                { Icon(Icons.Default.Star, contentDescription = null, modifier = Modifier.size(16.dp)) }
            } else null,
            colors = FilterChipDefaults.filterChipColors(
                selectedContainerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                selectedLabelColor = MaterialTheme.colorScheme.primary,
                containerColor = Color.Transparent,
                labelColor = MaterialTheme.colorScheme.onSurfaceVariant
            ),
            border = FilterChipDefaults.filterChipBorder(
                borderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                selectedBorderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                enabled = true,
                selected = activeFilter == ConversationFilter.FAVORITES
            )
        )
    }
}

// ─── Arama cubugu ────────────────────────────────────────────────────

@Composable
private fun GlassSearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    dark: Boolean
) {
    TextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(24.dp))
            .glass(dark = dark, shape = RoundedCornerShape(24.dp)),
        placeholder = {
            Text(
                "Sohbet veya kişi ara...",
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
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            cursorColor = MaterialTheme.colorScheme.primary
        ),
        singleLine = true
    )
}

// ─── Swipe konusma satiri ────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SwipeableConversationItem(
    conversation: Conversation,
    isTyping: Boolean = false,
    onClick: () -> Unit,
    onInfoClick: (() -> Unit)? = null,
    onDeleteRequest: () -> Unit,
    onArchiveRequest: (() -> Unit)? = null,
    onFavoriteToggle: (() -> Unit)? = null,
    onMuteToggle: (() -> Unit)? = null
) {
    var showContextMenu by remember { mutableStateOf(false) }

    val dismissState = rememberSwipeToDismissBoxState(
        positionalThreshold = { totalDistance -> totalDistance * 0.4f },
        confirmValueChange = { dismissValue ->
            when (dismissValue) {
                SwipeToDismissBoxValue.EndToStart -> {
                    onDeleteRequest()
                    false
                }
                SwipeToDismissBoxValue.StartToEnd -> {
                    onArchiveRequest?.invoke()
                    false
                }
                else -> false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            if (direction == SwipeToDismissBoxValue.StartToEnd) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF00897B)),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(
                        modifier = Modifier.padding(start = 24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Archive, contentDescription = "Arşivle", tint = Color.White)
                        Text("Arşivle", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
            } else if (direction == SwipeToDismissBoxValue.EndToStart) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(16.dp))
                        .background(MaterialTheme.colorScheme.error),
                    contentAlignment = Alignment.CenterEnd
                ) {
                    Row(
                        modifier = Modifier.padding(end = 24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Delete, contentDescription = "Sil", tint = MaterialTheme.colorScheme.onError)
                        Text("Sil", color = MaterialTheme.colorScheme.onError, fontWeight = FontWeight.Bold)
                    }
                }
            }
        },
        enableDismissFromStartToEnd = onArchiveRequest != null,
        enableDismissFromEndToStart = true
    ) {
        Box(
            modifier = Modifier.glass(
                dark = LocalDarkTheme.current,
                shape = RoundedCornerShape(16.dp)
            )
        ) {
            ConversationItem(
                conversation = conversation,
                isTyping = isTyping,
                onClick = onClick,
                onLongClick = { showContextMenu = true }
            )

            GlassDropdownMenu(
                expanded = showContextMenu,
                onDismissRequest = { showContextMenu = false }
            ) {
                if (onInfoClick != null) {
                    DropdownMenuItem(
                        text = { Text("Bilgi") },
                        onClick = { showContextMenu = false; onInfoClick() },
                        leadingIcon = { Icon(Icons.Default.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                    )
                }
                // Favori toggle
                if (onFavoriteToggle != null) {
                    val isFav = conversation.isFavorite
                    DropdownMenuItem(
                        text = { Text(if (isFav) "Favorilerden Çıkar" else "Favorilere Ekle") },
                        onClick = { showContextMenu = false; onFavoriteToggle() },
                        leadingIcon = {
                            Icon(
                                if (isFav) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                                contentDescription = null,
                                tint = if (isFav) Color(0xFFE53935) else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    )
                }
                if (onMuteToggle != null) {
                    val isMuted = conversation.isMuted
                    DropdownMenuItem(
                        text = { Text(if (isMuted) "Sesi Aç" else "Sessize Al") },
                        onClick = { showContextMenu = false; onMuteToggle() },
                        leadingIcon = {
                            Icon(
                                if (isMuted) Icons.Default.Notifications else Icons.Default.NotificationsOff,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    )
                }
                if (onArchiveRequest != null) {
                    DropdownMenuItem(
                        text = { Text("Arşivle") },
                        onClick = { showContextMenu = false; onArchiveRequest() },
                        leadingIcon = { Icon(Icons.Default.Archive, contentDescription = null, tint = Color(0xFF00897B)) }
                    )
                }
                DropdownMenuItem(
                    text = { Text("Sohbeti Sil", color = MaterialTheme.colorScheme.error) },
                    onClick = { showContextMenu = false; onDeleteRequest() },
                    leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) }
                )
            }
        }
    }
}

// ─── Konusma satiri ──────────────────────────────────────────────────

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
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        GeneratedAvatar(
            name = conversation.peerName,
            isGroup = conversation.isGroup,
            size = 48.dp
        )

        Spacer(modifier = Modifier.width(16.dp))

        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = conversation.peerName,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = if (conversation.unreadCount > 0) FontWeight.Bold else FontWeight.Normal,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                if (conversation.isMuted) {
                    Icon(
                        Icons.Default.NotificationsOff,
                        contentDescription = "Sessiz",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                        modifier = Modifier
                            .size(16.dp)
                            .padding(start = 4.dp)
                    )
                }
                if (conversation.isFavorite) {
                    Icon(
                        Icons.Default.Star,
                        contentDescription = "Favori",
                        tint = Color(0xFFFFC107),
                        modifier = Modifier
                            .size(16.dp)
                            .padding(start = 4.dp)
                    )
                }
                if (conversation.isLocked) {
                    Icon(
                        Icons.Default.Lock,
                        contentDescription = "Kilitli",
                        tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f),
                        modifier = Modifier
                            .size(16.dp)
                            .padding(start = 4.dp)
                    )
                }
            }
            Spacer(modifier = Modifier.height(2.dp))
            if (isTyping) {
                Text(
                    text = "yazıyor...",
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    color = MaterialTheme.colorScheme.primary
                )
            } else if (conversation.isLocked) {
                Text(
                    text = "Bu sohbet gizlendi",
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                )
            } else {
                val rawLastMessage = conversation.lastMessage ?: ""
                // CALL| ile baslayan sistem mesajlarinda okunabilir metni goster
                val displayLastMessage = if (rawLastMessage.startsWith("CALL|")) {
                    rawLastMessage.split("|", limit = 6).getOrNull(5) ?: rawLastMessage
                } else rawLastMessage
                Text(
                    text = displayLastMessage,
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

        Column(
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = formatTimestamp(conversation.lastMessageTimestamp),
                style = MaterialTheme.typography.labelSmall,
                color = if (conversation.unreadCount > 0) MaterialTheme.colorScheme.secondary
                        else MaterialTheme.colorScheme.onSurfaceVariant,
                fontSize = 12.sp
            )
            if (conversation.unreadCount > 0) {
                Spacer(modifier = Modifier.height(4.dp))
                // Renk koru ayirt edilebilirlik icin border/outline eklendi
                Badge(
                    containerColor = MaterialTheme.colorScheme.secondary,
                    contentColor = Color.White,
                    modifier = Modifier
                        .border(
                            1.5.dp,
                            MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f),
                            CircleShape
                        )
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

// ─── Silme diyalogu ──────────────────────────────────────────────────

@Composable
private fun DeleteConversationDialog(
    conversationName: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    GlassDialog(onDismissRequest = onDismiss) {
        Text(
            "Sohbeti Sil",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            "\"$conversationName\" ile olan sohbeti silmek istediğinize emin misiniz? Bu işlem geri alınamaz.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(20.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End
        ) {
            TextButton(onClick = onDismiss) { Text("İptal") }
            Spacer(modifier = Modifier.width(8.dp))
            TextButton(onClick = onConfirm) {
                Text("Sil", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

// ─── Baglanti durumu ─────────────────────────────────────────────────

@Composable
fun ConnectionStatusBanner(state: ConnectionState) {
    val (text, icon, baseColor) = when (state) {
        is ConnectionState.Connecting -> Triple("Bağlanılıyor...", Icons.Default.SyncProblem, Color(0xFFFFA726))
        is ConnectionState.Error -> Triple("Bağlantı hatası", Icons.Default.WifiOff, MaterialTheme.colorScheme.error)
        is ConnectionState.Disconnected -> Triple("Bağlantı kesildi", Icons.Default.CloudOff, MaterialTheme.colorScheme.error)
        is ConnectionState.Connected -> return
    }

    val animatedColor by animateColorAsState(
        targetValue = baseColor, animationSpec = tween(500), label = "bannerColor"
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .glass(dark = LocalDarkTheme.current, shape = RoundedCornerShape(12.dp))
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp), tint = animatedColor)
            Spacer(modifier = Modifier.width(8.dp))
            Text(text, style = MaterialTheme.typography.labelMedium, color = animatedColor, fontWeight = FontWeight.Medium)
        }
    }
}

// ─── Arsiv banner ────────────────────────────────────────────────────

@Composable
private fun ArchiveBanner(count: Int, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark = LocalDarkTheme.current, shape = RoundedCornerShape(16.dp))
            .clickable { onClick() }
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Archive,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
                )
            }
            Spacer(modifier = Modifier.width(16.dp))
            Text(
                text = "Arşivlenmiş",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f)
            )
            Badge(
                containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                contentColor = MaterialTheme.colorScheme.primary
            ) {
                Text("$count", fontSize = 11.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

// ─── Arsivlenmis sohbetler ──────────────────────────────────────────

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
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBackClick) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Geri", tint = MaterialTheme.colorScheme.onSurface)
            }
            Text(
                "Arşivlenmiş Sohbetler",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }

        if (archivedConversations.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.Archive,
                        contentDescription = null,
                        modifier = Modifier.size(48.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "Arşivlenmiş sohbet yok",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(archivedConversations, key = { it.id }) { conversation ->
                    SwipeableArchivedItem(
                        conversation = conversation,
                        onClick = { onConversationClick(conversation.id) },
                        onUnarchive = { onUnarchive(conversation) },
                        onDeleteRequest = { onDeleteRequest(conversation) }
                    )
                }
            }
        }
    }
}

/**
 * Arsivlenmis sohbet satiri — saga kaydirarak arsivden cikarma destegi.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SwipeableArchivedItem(
    conversation: Conversation,
    onClick: () -> Unit,
    onUnarchive: () -> Unit,
    onDeleteRequest: () -> Unit
) {
    var showContextMenu by remember { mutableStateOf(false) }

    val dismissState = rememberSwipeToDismissBoxState(
        positionalThreshold = { totalDistance -> totalDistance * 0.4f },
        confirmValueChange = { dismissValue ->
            when (dismissValue) {
                SwipeToDismissBoxValue.StartToEnd -> {
                    onUnarchive()
                    false
                }
                SwipeToDismissBoxValue.EndToStart -> {
                    onDeleteRequest()
                    false
                }
                else -> false
            }
        }
    )

    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            val direction = dismissState.dismissDirection
            if (direction == SwipeToDismissBoxValue.StartToEnd) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color(0xFF00897B)),
                    contentAlignment = Alignment.CenterStart
                ) {
                    Row(
                        modifier = Modifier.padding(start = 24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Unarchive, contentDescription = "Arşivden Çıkar", tint = Color.White)
                        Text("Arşivden Çıkar", color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
            } else if (direction == SwipeToDismissBoxValue.EndToStart) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(16.dp))
                        .background(MaterialTheme.colorScheme.error),
                    contentAlignment = Alignment.CenterEnd
                ) {
                    Row(
                        modifier = Modifier.padding(end = 24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Delete, contentDescription = "Sil", tint = MaterialTheme.colorScheme.onError)
                        Text("Sil", color = MaterialTheme.colorScheme.onError, fontWeight = FontWeight.Bold)
                    }
                }
            }
        },
        enableDismissFromStartToEnd = true,
        enableDismissFromEndToStart = true
    ) {
        Box(
            modifier = Modifier.glass(
                dark = LocalDarkTheme.current,
                shape = RoundedCornerShape(16.dp)
            )
        ) {
            ConversationItem(
                conversation = conversation,
                onClick = onClick,
                onLongClick = { showContextMenu = true }
            )

            GlassDropdownMenu(
                expanded = showContextMenu,
                onDismissRequest = { showContextMenu = false }
            ) {
                DropdownMenuItem(
                    text = { Text("Arşivden Çıkar") },
                    onClick = { showContextMenu = false; onUnarchive() },
                    leadingIcon = { Icon(Icons.Default.Unarchive, contentDescription = null, tint = Color(0xFF00897B)) }
                )
                DropdownMenuItem(
                    text = { Text("Sil", color = MaterialTheme.colorScheme.error) },
                    onClick = { showContextMenu = false; onDeleteRequest() },
                    leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) }
                )
            }
        }
    }
}

// ─── Bos durum ───────────────────────────────────────────────────────

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
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Default.Forum,
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
                text = if (isSearching) "Farklı bir arama terimi deneyin."
                       else "Yeni sohbet başlatmak için\nsağ üstteki + ikonuna dokunun.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
    }
}

// ─── Global arama sonuc satiri ──────────────────────────────────────

@Composable
private fun GlobalSearchResultItem(
    message: com.securechat.storage.domain.LocalMessage,
    conversationName: String,
    searchQuery: String,
    onClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .glass(dark = dark, shape = RoundedCornerShape(14.dp))
            .clickable { onClick() }
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        GeneratedAvatar(name = conversationName, size = 40.dp)
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = conversationName,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            // Mesaj snippet'i — arama terimini vurgula
            val content = message.content
            val idx = content.lowercase().indexOf(searchQuery.lowercase())
            if (idx >= 0) {
                val start = (idx - 20).coerceAtLeast(0)
                val end = (idx + searchQuery.length + 30).coerceAtMost(content.length)
                val prefix = if (start > 0) "..." else ""
                val suffix = if (end < content.length) "..." else ""
                val snippet = prefix + content.substring(start, end) + suffix
                val annotated = androidx.compose.ui.text.buildAnnotatedString {
                    val queryStart = snippet.lowercase().indexOf(searchQuery.lowercase())
                    if (queryStart >= 0) {
                        append(snippet.substring(0, queryStart))
                        pushStyle(androidx.compose.ui.text.SpanStyle(
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        ))
                        append(snippet.substring(queryStart, queryStart + searchQuery.length))
                        pop()
                        append(snippet.substring(queryStart + searchQuery.length))
                    } else {
                        append(snippet)
                    }
                }
                Text(
                    text = annotated,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            } else {
                Text(
                    text = content,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = formatTimestamp(message.timestamp),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontSize = 11.sp
        )
    }
}

// ─── Zaman formatlama ────────────────────────────────────────────────

private fun formatTimestamp(timestamp: Long?): String {
    return com.securechat.app.util.TimeFormatter.formatTimestamp(timestamp)
}
