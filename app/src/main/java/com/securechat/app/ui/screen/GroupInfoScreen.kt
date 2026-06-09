package com.securechat.app.ui.screen

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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import com.securechat.app.ui.components.GlassDropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.res.stringResource
import com.securechat.app.R
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.viewmodel.GroupInfoViewModel
import com.securechat.storage.entity.MessageEntity
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.theme.MonoFamily
import com.securechat.app.ui.theme.DisplayFamily
import kotlin.math.abs

private val AZ_AVATAR_COLORS_GROUP = listOf(
    Color(0xFF3E7BFA), Color(0xFF6B737D), Color(0xFF8A929C),
    Color(0xFF5D6570), Color(0xFF4A535E), Color(0xFF9BA3AE),
)

/**
 * Grup bilgileri ekranı.
 * Grup adını, üyelerini gösterir ve admin yetkisi varsa üye ekleme/çıkartma,
 * grup adı değiştirme gibi işlemleri yapabilir.
 * Azure glassmorphism tasarım.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupInfoScreen(
    groupId: String,
    viewModel: GroupInfoViewModel = hiltViewModel(),
    onBackClick: () -> Unit,
    onAddMember: () -> Unit = {},
    onMemberClick: (String) -> Unit = {},
    onExportHistoryClick: () -> Unit = {},
    onMessageClick: (String) -> Unit = {},
    onMediaClick: (MessageEntity) -> Unit = {}
) {
    val groupInfo by viewModel.groupInfo.collectAsStateWithLifecycle()
    val isAdmin by viewModel.isAdmin.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val mediaMessages by viewModel.mediaMessages.collectAsStateWithLifecycle()
    val documentMessages by viewModel.documentMessages.collectAsStateWithLifecycle()
    val starredMessages by viewModel.starredMessages.collectAsStateWithLifecycle()
    val disappearingDuration by viewModel.disappearingDuration.collectAsStateWithLifecycle()
    val isLocked by viewModel.isLocked.collectAsStateWithLifecycle()
    val isExportEnabled by viewModel.isExportEnabled.collectAsStateWithLifecycle()

    var currentTab by remember { mutableStateOf(GroupInfoTab.MAIN) }
    var showEditGroupDialog by remember { mutableStateOf(false) }
    var showDisappearingDialog by remember { mutableStateOf(false) }
    var showRemoveMemberDialog by remember { mutableStateOf<String?>(null) }
    var editedGroupName by remember { mutableStateOf("") }

    val snackbarHostState = remember { SnackbarHostState() }
    val dark = LocalDarkTheme.current

    // Grup bilgilerini yükle
    LaunchedEffect(groupId) {
        viewModel.loadGroupInfo(groupId)
    }

    // Hata mesajlarını göster
    LaunchedEffect(error) {
        error?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    // Grup adı edit dialog açıldığında mevcut adı doldur
    LaunchedEffect(groupInfo, showEditGroupDialog) {
        if (showEditGroupDialog && editedGroupName.isEmpty()) {
            editedGroupName = groupInfo?.name ?: ""
        }
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        when (currentTab) {
                            GroupInfoTab.MAIN -> "Grup Bilgileri"
                            GroupInfoTab.MEDIA -> "Medyalar"
                            GroupInfoTab.DOCUMENTS -> "Dokümanlar"
                            GroupInfoTab.STARRED -> "Yıldızlı Mesajlar"
                        },
                        color = MaterialTheme.colorScheme.onSurface
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (currentTab == GroupInfoTab.MAIN) {
                            onBackClick()
                        } else {
                            currentTab = GroupInfoTab.MAIN
                        }
                    }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Geri",
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                },
                actions = {
                    // Sadece admin kullanicilar grup adini duzenleyebilir
                    if (currentTab == GroupInfoTab.MAIN && isAdmin) {
                        IconButton(onClick = { showEditGroupDialog = true }) {
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = "Grup Ad\u0131n\u0131 D\u00FCzenle",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onSurface
                ),
                windowInsets = WindowInsets(0)
            )
        },
        floatingActionButton = {
            if (isAdmin && currentTab == GroupInfoTab.MAIN) {
                FloatingActionButton(
                    onClick = onAddMember,
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = Color.White,
                    shape = CircleShape
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Üye Ekle")
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0)
    ) { padding ->
        when (currentTab) {
            GroupInfoTab.MAIN -> {
                LazyColumn(
                    modifier = Modifier
                        .padding(padding)
                        .fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    // Grup header bilgisi
                    item {
                        GroupHeader(
                            groupName = groupInfo?.name ?: "",
                            memberCount = groupInfo?.members?.size ?: 0,
                            isLoading = isLoading
                        )
                    }

                    // Üyeler başlığı
                    item {
                        Text(
                            text = "Üyeler (${groupInfo?.members?.size ?: 0})",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                    }

                    // Üye listesi
                    groupInfo?.let { info ->
                        items(info.members) { member ->
                            MemberItem(
                                member = member,
                                displayName = info.memberNames[member.userId] ?: member.userId,
                                phoneNumber = info.memberPhones[member.userId],
                                isCurrentUser = member.isCurrentUser,
                                isAdmin = member.isAdmin,
                                canRemove = isAdmin && !member.isCurrentUser,
                                canToggleAdmin = isAdmin && !member.isCurrentUser,
                                onRemoveClick = { showRemoveMemberDialog = member.userId },
                                onToggleAdminClick = {
                                    if (member.isAdmin) {
                                        viewModel.demoteFromAdmin(groupId, member.userId)
                                    } else {
                                        viewModel.promoteToAdmin(groupId, member.userId)
                                    }
                                },
                                onViewProfile = { onMemberClick(member.userId) }
                            )
                        }
                    }

                    // Bölüm ayırıcı
                    item {
                        GroupSectionDivider()
                    }

                    // Medyalar menü ögesi
                    item {
                        GroupInfoMenuItem(
                            icon = Icons.Default.Image,
                            title = "Medyalar",
                            subtitle = if (mediaMessages.isNotEmpty()) "${mediaMessages.size} medya" else "Medya yok",
                            onClick = { currentTab = GroupInfoTab.MEDIA }
                        )
                    }

                    // Dokümanlar menü ögesi
                    item {
                        GroupInfoMenuItem(
                            icon = Icons.Default.Description,
                            title = "Dokümanlar",
                            subtitle = if (documentMessages.isNotEmpty()) "${documentMessages.size} doküman" else "Doküman yok",
                            onClick = { currentTab = GroupInfoTab.DOCUMENTS }
                        )
                    }

                    // Yıldızlı mesajlar menü ögesi
                    item {
                        GroupInfoMenuItem(
                            icon = Icons.Default.Star,
                            iconTint = Color(0xFFFFD700),
                            title = "Yıldızlı Mesajlar",
                            subtitle = if (starredMessages.isNotEmpty()) "${starredMessages.size} mesaj" else "Yıldızlı mesaj yok",
                            onClick = { currentTab = GroupInfoTab.STARRED }
                        )
                    }

                    // Bölüm ayırıcı
                    item {
                        GroupSectionDivider()
                    }

                    // Sureli mesajlar menu ogesi — sadece admin degistirebilir
                    item {
                        GroupInfoMenuItem(
                            icon = Icons.Default.Schedule,
                            iconTint = Color(0xFF00897B),
                            title = "S\u00FCreli Mesajlar",
                            subtitle = if (isAdmin)
                                formatGroupDisappearingLabel(disappearingDuration)
                            else
                                "${formatGroupDisappearingLabel(disappearingDuration)} (Sadece y\u00F6netici de\u011Fi\u015Ftirebilir)",
                            onClick = {
                                if (isAdmin) {
                                    showDisappearingDialog = true
                                }
                                // Admin degil ise tiklama etkisiz
                            }
                        )
                    }

                    // Biyometrik kilit
                    item {
                        GroupInfoMenuItem(
                            icon = if (isLocked) Icons.Default.Lock else Icons.Default.LockOpen,
                            iconTint = if (isLocked) MaterialTheme.colorScheme.primary else Color(0xFF78909C),
                            title = if (isLocked) "Sohbet Kilitli" else "Sohbet Kilidi",
                            subtitle = if (isLocked) "Biyometrik doğrulama açık" else "Biyometrik kilit ekle",
                            onClick = { viewModel.toggleLocked(groupId) }
                        )
                    }

                    // Disa Aktarma Gecmisi — sadece admin gorur. Lokal DB'den okur,
                    // sunucudan veri cekilmez (zero-knowledge audit).
                    if (isAdmin) {
                        item {
                            GroupInfoMenuItem(
                                icon = Icons.Default.History,
                                iconTint = Color(0xFF1976D2),
                                title = "Dışa Aktarma Geçmişi",
                                subtitle = "Bu grupta yapılan dışa aktarmaları görüntüle",
                                onClick = onExportHistoryClick
                            )
                        }
                    }

                    // Sohbet disa aktarma izni (sadece admin toggle eder).
                    // Kapaliyken: mesaj kopyalama + "Sohbeti Disa Aktar" menu item gizlenir.
                    // Acikken: yeni katilanlara one-time bilgi banner gosterilir, export
                    // yapildiginda diger admin'lere E2EE log gonderilir.
                    item {
                        val exportTitle = if (isExportEnabled) "Sohbet Dışa Aktarma Açık" else "Sohbet Dışa Aktarma Kapalı"
                        val exportSubtitle = when {
                            !isAdmin -> if (isExportEnabled)
                                "Açık (sadece yönetici değiştirebilir)"
                            else
                                "Kapalı (sadece yönetici değiştirebilir)"
                            isExportEnabled -> "Üyeler sohbeti dışa aktarabilir/kopyalayabilir"
                            else -> "Kopyalama ve dışa aktarma engelli"
                        }
                        GroupInfoMenuItem(
                            icon = if (isExportEnabled) Icons.Default.Share else Icons.Default.Block,
                            iconTint = if (isExportEnabled) Color(0xFFEF6C00) else Color(0xFF78909C),
                            title = exportTitle,
                            subtitle = exportSubtitle,
                            onClick = {
                                if (isAdmin) {
                                    viewModel.toggleExportEnabled(groupId)
                                }
                                // Admin degilse tiklama etkisiz
                            }
                        )
                    }

                    // Boş alan
                    item {
                        Spacer(modifier = Modifier.height(80.dp))
                    }
                }
            }

            GroupInfoTab.MEDIA -> {
                GroupMediaContent(
                    modifier = Modifier.padding(padding),
                    mediaMessages = mediaMessages,
                    isLoading = isLoading,
                    onMediaClick = onMediaClick
                )
            }

            GroupInfoTab.DOCUMENTS -> {
                GroupDocumentsContent(
                    modifier = Modifier.padding(padding),
                    documentMessages = documentMessages,
                    isLoading = isLoading,
                    onDocumentClick = onMediaClick
                )
            }

            GroupInfoTab.STARRED -> {
                GroupStarredMessagesContent(
                    modifier = Modifier.padding(padding),
                    starredMessages = starredMessages,
                    isLoading = isLoading,
                    onMessageClick = onMessageClick
                )
            }
        }
    }
    } // Box

    // Grup adı düzenleme dialog'u
    if (showEditGroupDialog) {
        AlertDialog(
            onDismissRequest = { showEditGroupDialog = false },
            title = { Text(stringResource(R.string.edit_group_name)) },
            text = {
                OutlinedTextField(
                    value = editedGroupName,
                    onValueChange = { editedGroupName = it },
                    label = { Text(stringResource(R.string.group_name)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        cursorColor = MaterialTheme.colorScheme.primary
                    )
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (editedGroupName.isNotBlank()) {
                            viewModel.updateGroupName(groupId, editedGroupName.trim())
                            showEditGroupDialog = false
                            editedGroupName = ""
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = Color.White
                    )
                ) {
                    Text(stringResource(R.string.save))
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showEditGroupDialog = false
                    editedGroupName = ""
                }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }

    // Üye çıkartma onay dialog'u
    showRemoveMemberDialog?.let { memberId ->
        val memberName = groupInfo?.memberNames?.get(memberId) ?: memberId
        AlertDialog(
            onDismissRequest = { showRemoveMemberDialog = null },
            title = { Text(stringResource(R.string.remove_member_confirm)) },
            text = { Text("$memberName kullanıcısını gruptan çıkarmak istediğinizden emin misiniz?") },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.removeMember(groupId, memberId)
                        showRemoveMemberDialog = null
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text(stringResource(R.string.remove))
                }
            },
            dismissButton = {
                TextButton(onClick = { showRemoveMemberDialog = null }) {
                    Text(stringResource(R.string.cancel))
                }
            }
        )
    }

    // Süreli mesaj dialog
    if (showDisappearingDialog) {
        DisappearingTimerDialog(
            currentDuration = disappearingDuration,
            onDurationSelected = { duration ->
                viewModel.setDisappearingDuration(groupId, duration)
                showDisappearingDialog = false
            },
            onDismiss = { showDisappearingDialog = false }
        )
    }
}

/**
 * Grup başlık bilgisi.
 * Grup ikonu, ismi ve üye sayısını gösterir.
 */
@Composable
private fun GroupHeader(
    groupName: String,
    memberCount: Int,
    isLoading: Boolean
) {
    val dark = LocalDarkTheme.current

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
            .glass(dark),
    ) {
        Row(
            modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Grup avatarı — insan silueti
            GeneratedAvatar(
                name = groupName,
                isGroup = true,
                size = 64.dp
            )

            Spacer(modifier = Modifier.width(16.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (isLoading) "Yükleniyor..." else groupName,
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = if (isLoading) "..." else "$memberCount üye",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * Üye liste ögesi.
 * Üye adını, rolünü gösterir ve admin ise çıkartma butonu ekler.
 */
@Composable
private fun MemberItem(
    member: GroupMember,
    displayName: String,
    phoneNumber: String? = null,
    isCurrentUser: Boolean,
    isAdmin: Boolean,
    canRemove: Boolean,
    canToggleAdmin: Boolean = false,
    onRemoveClick: () -> Unit,
    onToggleAdminClick: () -> Unit = {},
    onViewProfile: () -> Unit = {}
) {
    var showMenu by remember { mutableStateOf(false) }
    val dark = LocalDarkTheme.current

    ListItem(
        leadingContent = {
            GeneratedAvatar(
                name = displayName,
                size = 40.dp
            )
        },
        headlineContent = {
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (isCurrentUser) "$displayName (Sen)" else displayName,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                if (isAdmin) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.2f),
                        modifier = Modifier.padding(start = 8.dp)
                    ) {
                        Text(
                            text = "Admin",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        },
        supportingContent = {
            Text(
                text = phoneNumber ?: member.userId,
                fontFamily = MonoFamily,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        trailingContent = {
            Box {
                IconButton(onClick = { showMenu = true }) {
                    Icon(
                        Icons.Default.Settings,
                        contentDescription = "Üye İşlemleri",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                GlassDropdownMenu(
                    expanded = showMenu,
                    onDismissRequest = { showMenu = false }
                ) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.group_view_profile)) },
                        onClick = {
                            showMenu = false
                            onViewProfile()
                        },
                        leadingIcon = {
                            Icon(
                                Icons.Default.Person,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    )
                    if (canToggleAdmin || canRemove) {
                        HorizontalDivider()
                    }
                    if (canToggleAdmin) {
                        DropdownMenuItem(
                            text = {
                                Text(
                                    if (isAdmin) "Yöneticilikten Al" else "Yönetici Yap",
                                    color = if (isAdmin) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                                )
                            },
                            onClick = {
                                showMenu = false
                                onToggleAdminClick()
                            },
                            leadingIcon = {
                                Icon(
                                    Icons.Default.Security,
                                    contentDescription = null,
                                    tint = if (isAdmin) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
                                )
                            }
                        )
                    }
                    if (canRemove) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.group_leave), color = MaterialTheme.colorScheme.error) },
                            onClick = {
                                showMenu = false
                                onRemoveClick()
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
        },
        colors = ListItemDefaults.colors(
            containerColor = Color.Transparent
        ),
        modifier = Modifier
            .padding(horizontal = 8.dp)
            .glass(dark, shape = RoundedCornerShape(16.dp))
    )
}

/**
 * Grup bilgi ekranı sekmeleri.
 */
enum class GroupInfoTab {
    MAIN, MEDIA, DOCUMENTS, STARRED
}

// --- Medyalar, Dokümanlar, Yıldızlı Mesajlar için menü ögesi ---

@Composable
private fun GroupInfoMenuItem(
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
private fun GroupSectionDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(vertical = 8.dp),
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f)
    )
}

// --- Medya Ekranı ---

@Composable
private fun GroupMediaContent(
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
            GroupEmptyStateMessage("Medya yok")
        }
    } else {
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            items(mediaMessages) { message ->
                GroupMediaThumbnail(
                    message = message,
                    onClick = { onMediaClick(message) }
                )
            }
        }
    }
}

@Composable
private fun GroupMediaThumbnail(
    @Suppress("UNUSED_PARAMETER") message: MessageEntity,
    onClick: () -> Unit
) {
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
            modifier = Modifier
                .fillMaxSize()
                .padding(4.dp),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.Image,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f)
            )
        }
    }
}

// --- Dokümanlar Ekranı ---

@Composable
private fun GroupDocumentsContent(
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
            GroupEmptyStateMessage("Doküman yok")
        }
    } else {
        LazyColumn(
            modifier = modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(documentMessages) { message ->
                GroupDocumentItem(
                    message = message,
                    onClick = { onDocumentClick(message) }
                )
            }
        }
    }
}

@Composable
private fun GroupDocumentItem(
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

// --- Yıldızlı Mesajlar Ekranı ---

@Composable
private fun GroupStarredMessagesContent(
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
            GroupEmptyStateMessage("Yıldızlı mesaj yok")
        }
    } else {
        LazyColumn(
            modifier = modifier.fillMaxSize().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(starredMessages) { message ->
                GroupMessageResultItem(
                    message = message,
                    showStar = true,
                    onClick = { onMessageClick(message.id) }
                )
            }
        }
    }
}

@Composable
private fun GroupMessageResultItem(
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

// --- Boş durum mesajı ---

@Composable
private fun GroupEmptyStateMessage(text: String) {
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

/**
 * Süreli mesaj süresini okunabilir etikete çevirir.
 */
private fun formatGroupDisappearingLabel(duration: Long): String {
    return when (duration) {
        0L -> "Kapalı"
        30_000L -> "30 saniye"
        60_000L -> "1 dakika"
        300_000L -> "5 dakika"
        3_600_000L -> "1 saat"
        86_400_000L -> "24 saat"
        else -> "Açık"
    }
}

/**
 * Grup üye modeli.
 */
data class GroupMember(
    val userId: String,
    val isAdmin: Boolean = false,
    val isCurrentUser: Boolean = false
)