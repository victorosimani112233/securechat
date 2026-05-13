package com.securechat.app.ui.screen

import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.SelectAll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.material3.LocalContentColor
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.viewmodel.BulkMessageViewModel
import com.securechat.storage.domain.Conversation

/**
 * Toplu mesaj gonderim ekrani.
 * Birden fazla aliciya ayni mesaji tek seferde gondermeyi saglar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BulkMessageScreen(
    onBackClick: () -> Unit,
    viewModel: BulkMessageViewModel = hiltViewModel()
) {
    val dark = LocalDarkTheme.current
    val conversations by viewModel.conversations.collectAsStateWithLifecycle()
    val messageContent by viewModel.messageContent.collectAsStateWithLifecycle()
    val selectedIds by viewModel.selectedRecipientIds.collectAsStateWithLifecycle()
    val isSending by viewModel.isSending.collectAsStateWithLifecycle()

    // Gonderim tamamlandiginda geri don
    LaunchedEffect(Unit) {
        viewModel.sendComplete.collect {
            onBackClick()
        }
    }

    val canSend = messageContent.isNotBlank() && selectedIds.isNotEmpty() && !isSending

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            "Toplu Mesaj",
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onBackClick) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = "Geri",
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
            CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface) {
                Column(
                    modifier = Modifier
                        .padding(padding)
                        .fillMaxSize()
                ) {
                    // Mesaj icerigi alani
                    MessageInputSection(
                        dark = dark,
                        messageContent = messageContent,
                        onMessageChange = viewModel::setMessageContent
                    )

                    Spacer(Modifier.height(8.dp))

                    // Alici secimi basligi + Tumunu Sec
                    RecipientHeader(
                        conversations = conversations,
                        selectedIds = selectedIds,
                        onSelectAll = { viewModel.selectAll(conversations) },
                        onDeselectAll = { viewModel.deselectAll() }
                    )

                    // Kisi listesi
                    LazyColumn(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        items(conversations, key = { it.id }) { conversation ->
                            val isSelected = conversation.peerId in selectedIds
                            ContactRow(
                                dark = dark,
                                conversation = conversation,
                                isSelected = isSelected,
                                onClick = { viewModel.toggleRecipient(conversation.peerId) }
                            )
                        }

                        // Bos durum
                        if (conversations.isEmpty()) {
                            item {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = 48.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        "Henüz sohbet geçmişi yok",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                    )
                                }
                            }
                        }
                    }

                    // Gonder butonu
                    SendButton(
                        dark = dark,
                        canSend = canSend,
                        isSending = isSending,
                        selectedCount = selectedIds.size,
                        onClick = { viewModel.sendBulkMessage() }
                    )
                }
            }
        }
    }
}

// ─── Mesaj girisi bolumu ───────────────────────────────────────────

@Composable
private fun MessageInputSection(
    dark: Boolean,
    messageContent: String,
    onMessageChange: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .glass(dark = dark, shape = RoundedCornerShape(16.dp))
            .padding(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.AutoMirrored.Filled.Send,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp)
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "Mesaj İçeriği",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
        Spacer(Modifier.height(12.dp))
        OutlinedTextField(
            value = messageContent,
            onValueChange = onMessageChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("Mesajınızı yazın...") },
            minLines = 3,
            maxLines = 6,
            shape = RoundedCornerShape(12.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedBorderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f),
                cursorColor = MaterialTheme.colorScheme.primary
            )
        )
    }
}

// ─── Alici basligi + Tumunu Sec ────────────────────────────────────

@Composable
private fun RecipientHeader(
    conversations: List<Conversation>,
    selectedIds: Set<String>,
    onSelectAll: () -> Unit,
    onDeselectAll: () -> Unit
) {
    val allSelected = conversations.isNotEmpty() && conversations.all { it.peerId in selectedIds }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            "Alıcılar",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface
        )

        TextButton(
            onClick = { if (allSelected) onDeselectAll() else onSelectAll() },
            enabled = conversations.isNotEmpty()
        ) {
            Icon(
                Icons.Default.SelectAll,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(Modifier.width(4.dp))
            Text(
                if (allSelected) "Seçimi Kaldır" else "Tümünü Seç",
                color = MaterialTheme.colorScheme.primary,
                fontSize = 13.sp
            )
        }
    }
}

// ─── Tek bir kisi satiri ───────────────────────────────────────────

@Composable
private fun ContactRow(
    dark: Boolean,
    conversation: Conversation,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .then(
                if (isSelected) Modifier.glass(dark = dark, shape = RoundedCornerShape(12.dp))
                else Modifier
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        GeneratedAvatar(
            name = conversation.peerName,
            isGroup = conversation.isGroup,
            size = 40.dp
        )

        Spacer(Modifier.width(12.dp))

        Text(
            conversation.peerName,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f)
        )

        Spacer(Modifier.width(8.dp))

        Icon(
            imageVector = if (isSelected) Icons.Default.CheckBox else Icons.Default.CheckBoxOutlineBlank,
            contentDescription = if (isSelected) "Seçili" else "Seçilmedi",
            tint = if (isSelected) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            modifier = Modifier.size(24.dp)
        )
    }
}

// ─── Gonder butonu ─────────────────────────────────────────────────

@Composable
private fun SendButton(
    @Suppress("UNUSED_PARAMETER") dark: Boolean,
    canSend: Boolean,
    isSending: Boolean,
    selectedCount: Int,
    onClick: () -> Unit
) {
    val label = when {
        isSending -> "Gönderiliyor..."
        selectedCount == 0 -> "Gönder"
        else -> "Gönder ($selectedCount kişi)"
    }

    TextButton(
        onClick = onClick,
        enabled = canSend,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .height(48.dp)
            .background(
                if (canSend) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.2f),
                RoundedCornerShape(12.dp)
            )
    ) {
        if (isSending) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = Color.White
            )
            Spacer(Modifier.width(8.dp))
        }
        Text(
            label,
            color = if (canSend) Color.White
            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            fontWeight = FontWeight.SemiBold
        )
    }
}
