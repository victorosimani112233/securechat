package com.securechat.app.ui.screen

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonRemove
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.viewmodel.GroupInfoViewModel
import com.securechat.storage.entity.MessageEntity
import kotlin.math.abs

/**
 * Grup bilgileri ekranı.
 * Grup adını, üyelerini gösterir ve admin yetkisi varsa üye ekleme/çıkartma,
 * grup adı değiştirme gibi işlemleri yapabilir.
 * Midnight Teal tasarım: koyu arka plan, cyan vurgular.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupInfoScreen(
    groupId: String,
    viewModel: GroupInfoViewModel = hiltViewModel(),
    onBackClick: () -> Unit,
    onAddMember: () -> Unit = {},
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

    var currentTab by remember { mutableStateOf(GroupInfoTab.MAIN) }
    var showEditGroupDialog by remember { mutableStateOf(false) }
    var showDisappearingDialog by remember { mutableStateOf(false) }
    var showAddMemberDialog by remember { mutableStateOf(false) }
    var showRemoveMemberDialog by remember { mutableStateOf<String?>(null) }
    var editedGroupName by remember { mutableStateOf("") }
    var newMemberInput by remember { mutableStateOf("") }

    val snackbarHostState = remember { SnackbarHostState() }

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
                    if (currentTab == GroupInfoTab.MAIN) {
                        IconButton(onClick = { showEditGroupDialog = true }) {
                            Icon(
                                Icons.Default.Edit,
                                contentDescription = "Grup Adını Düzenle",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.onSurface
                ),
                modifier = Modifier.drawBehind {
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
            if (isAdmin && currentTab == GroupInfoTab.MAIN) {
                FloatingActionButton(
                    onClick = { showAddMemberDialog = true },
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = Color(0xFF0D1117)
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Üye Ekle")
                }
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.background
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
                                canPromote = isAdmin && !member.isAdmin && !member.isCurrentUser,
                                onRemoveClick = { showRemoveMemberDialog = member.userId },
                                onPromoteClick = { viewModel.promoteToAdmin(groupId, member.userId) }
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

                    // Süreli mesajlar menü ögesi
                    item {
                        GroupInfoMenuItem(
                            icon = Icons.Default.Schedule,
                            iconTint = Color(0xFF00897B),
                            title = "Süreli Mesajlar",
                            subtitle = formatGroupDisappearingLabel(disappearingDuration),
                            onClick = { showDisappearingDialog = true }
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

    // Grup adı düzenleme dialog'u
    if (showEditGroupDialog) {
        AlertDialog(
            onDismissRequest = { showEditGroupDialog = false },
            title = { Text("Grup Adını Düzenle") },
            text = {
                OutlinedTextField(
                    value = editedGroupName,
                    onValueChange = { editedGroupName = it },
                    label = { Text("Grup Adı") },
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
                        contentColor = Color(0xFF0D1117)
                    )
                ) {
                    Text("Kaydet")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showEditGroupDialog = false
                    editedGroupName = ""
                }) {
                    Text("İptal")
                }
            }
        )
    }

    // Üye ekleme dialog'u
    if (showAddMemberDialog) {
        AlertDialog(
            onDismissRequest = { showAddMemberDialog = false },
            title = { Text("Yeni Üye Ekle") },
            text = {
                OutlinedTextField(
                    value = newMemberInput,
                    onValueChange = { newMemberInput = it },
                    label = { Text("Kullanıcı ID") },
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
                        if (newMemberInput.isNotBlank()) {
                            viewModel.addMember(groupId, newMemberInput.trim())
                            showAddMemberDialog = false
                            newMemberInput = ""
                        }
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = Color(0xFF0D1117)
                    )
                ) {
                    Text("Ekle")
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    showAddMemberDialog = false
                    newMemberInput = ""
                }) {
                    Text("İptal")
                }
            }
        )
    }

    // Üye çıkartma onay dialog'u
    showRemoveMemberDialog?.let { memberId ->
        val memberName = groupInfo?.memberNames?.get(memberId) ?: memberId
        AlertDialog(
            onDismissRequest = { showRemoveMemberDialog = null },
            title = { Text("Üyeyi Çıkar") },
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
                    Text("Çıkar")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRemoveMemberDialog = null }) {
                    Text("İptal")
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
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Row(
            modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Grup avatarı
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(groupAvatarGradient(groupName)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Group,
                    contentDescription = "Grup",
                    tint = Color.White,
                    modifier = Modifier.size(32.dp)
                )
            }

            Spacer(modifier = Modifier.width(16.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (isLoading) "Yükleniyor..." else groupName,
                    style = MaterialTheme.typography.headlineSmall,
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
    canPromote: Boolean = false,
    onRemoveClick: () -> Unit,
    onPromoteClick: () -> Unit = {}
) {
    var showMenu by remember { mutableStateOf(false) }

    ListItem(
        leadingContent = {
            // Üye avatarı
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(memberAvatarGradient(member.userId)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = "Kişi",
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
            }
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
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        trailingContent = {
            if (canRemove || canPromote) {
                Box {
                    IconButton(onClick = { showMenu = true }) {
                        Icon(
                            Icons.Default.Settings,
                            contentDescription = "Üye İşlemleri",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    DropdownMenu(
                        expanded = showMenu,
                        onDismissRequest = { showMenu = false }
                    ) {
                        if (canPromote) {
                            DropdownMenuItem(
                                text = { Text("Yönetici Yap", color = MaterialTheme.colorScheme.primary) },
                                onClick = {
                                    showMenu = false
                                    onPromoteClick()
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Security,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            )
                        }
                        if (canRemove) {
                            DropdownMenuItem(
                                text = { Text("Gruptan Çıkar", color = MaterialTheme.colorScheme.error) },
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
            }
        },
        colors = ListItemDefaults.colors(
            containerColor = Color.Transparent
        ),
        modifier = Modifier.padding(horizontal = 8.dp)
    )
}

/**
 * Grup avatarı için gradient renk oluşturur.
 */
private fun groupAvatarGradient(name: String): Brush {
    val colors = listOf(
        Color(0xFF00897B) to Color(0xFF004D40),
        Color(0xFF00ACC1) to Color(0xFF006064),
        Color(0xFF5C6BC0) to Color(0xFF283593),
        Color(0xFF7E57C2) to Color(0xFF4527A0)
    )
    val index = abs(name.hashCode()) % colors.size
    val (start, end) = colors[index]
    return Brush.linearGradient(listOf(start, end))
}

/**
 * Üye avatarı için gradient renk oluşturur.
 */
private fun memberAvatarGradient(userId: String): Brush {
    val colors = listOf(
        Color(0xFF4ECDC4) to Color(0xFF26A69A),
        Color(0xFF42A5F5) to Color(0xFF1976D2),
        Color(0xFF7C4DFF) to Color(0xFF512DA8),
        Color(0xFFFF7043) to Color(0xFFD84315),
        Color(0xFFEC407A) to Color(0xFFC2185B),
        Color(0xFF66BB6A) to Color(0xFF388E3C)
    )
    val index = abs(userId.hashCode()) % colors.size
    val (start, end) = colors[index]
    return Brush.linearGradient(listOf(start, end))
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
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
        color = Color(0xFF30363D)
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
    message: MessageEntity,
    onClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .size(110.dp)
            .clickable { onClick() },
        shape = RoundedCornerShape(4.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
        )
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
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
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(vertical = 12.dp),
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
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.15f)
        ),
        shape = RoundedCornerShape(12.dp)
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