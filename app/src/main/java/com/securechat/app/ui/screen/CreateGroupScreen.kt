package com.securechat.app.ui.screen

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Dialpad
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.DisplayFamily
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Surface
import androidx.compose.material3.TextButton
import androidx.compose.ui.text.input.KeyboardType
import com.securechat.app.ui.components.GlassDialog
import com.securechat.app.ui.viewmodel.CreateGroupViewModel
import com.securechat.app.ui.viewmodel.SelectableContact

/**
 * Grup oluşturma ekranı.
 * Azure glassmorphism tasarım: cam efektli kartlar, DoodleBackdrop arka plan.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun CreateGroupScreen(
    viewModel: CreateGroupViewModel = hiltViewModel(),
    onGroupCreated: (String) -> Unit,
    onBackClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    val groupName by viewModel.groupName.collectAsStateWithLifecycle()
    val contacts by viewModel.contacts.collectAsStateWithLifecycle()
    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val isLoadingContacts by viewModel.isLoadingContacts.collectAsStateWithLifecycle()
    val selectedMembers by viewModel.selectedMembers.collectAsStateWithLifecycle()
    val createdGroupId by viewModel.createdGroupId.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val phoneInput by viewModel.phoneInput.collectAsStateWithLifecycle()
    val isResolvingPhone by viewModel.isResolvingPhone.collectAsStateWithLifecycle()
    val phoneNotFound by viewModel.phoneNotFound.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var showPhoneInput by remember { mutableStateOf(false) }

    // Grup oluşturulunca sohbet ekranına navigate et
    LaunchedEffect(createdGroupId) {
        createdGroupId?.let { groupId ->
            onGroupCreated(groupId)
        }
    }

    // Hata mesajı göster
    LaunchedEffect(error) {
        error?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearError()
        }
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            "Yeni Grup",
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
                        containerColor = Color.Transparent,
                        titleContentColor = MaterialTheme.colorScheme.onSurface
                    ),
                    windowInsets = WindowInsets(0)
                )
            },
            snackbarHost = { SnackbarHost(snackbarHostState) },
            floatingActionButton = {
                if (groupName.isNotBlank() && selectedMembers.isNotEmpty()) {
                    FloatingActionButton(
                        onClick = { viewModel.createGroup() },
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = Color.White
                    ) {
                        Text("Oluştur", modifier = Modifier.padding(horizontal = 16.dp))
                    }
                }
            },
            containerColor = Color.Transparent,
            contentWindowInsets = WindowInsets(0)
        ) { padding ->
            Column(
                modifier = Modifier
                    .padding(padding)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp)
            ) {
                // Grup adı alanı
                OutlinedTextField(
                    value = groupName,
                    onValueChange = { viewModel.onGroupNameChanged(it) },
                    label = { Text("Grup Adı") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
                        cursorColor = MaterialTheme.colorScheme.primary
                    )
                )

                Spacer(modifier = Modifier.height(24.dp))

                // Seçili üyelerin chip listesi
                if (selectedMembers.isNotEmpty()) {
                    Text(
                        text = "Seçili Üyeler (${selectedMembers.size})",
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        selectedMembers.forEach { userId ->
                            // userId'den kişi adını bul
                            val contactName = contacts.find { it.userId == userId }?.displayName ?: userId
                            AssistChip(
                                onClick = { viewModel.toggleContactSelection(userId) },
                                label = {
                                    Text(
                                        contactName,
                                        color = MaterialTheme.colorScheme.primary
                                    )
                                },
                                trailingIcon = {
                                    Icon(
                                        Icons.Default.Close,
                                        contentDescription = "Çıkar",
                                        modifier = Modifier.padding(start = 4.dp),
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                },
                                colors = AssistChipDefaults.assistChipColors(
                                    containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
                                ),
                                border = AssistChipDefaults.assistChipBorder(
                                    enabled = true,
                                    borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f)
                                )
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))
                }

                // Numara ile ekle butonu
                Surface(
                    onClick = { showPhoneInput = !showPhoneInput },
                    color = Color.Transparent,
                    shape = RoundedCornerShape(20.dp)
                ) {
                    Row(
                        modifier = Modifier
                            .glass(dark = dark, shape = RoundedCornerShape(20.dp))
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Icon(
                            Icons.Default.Dialpad,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Text(
                            "Numara ile Ekle",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }

                // Telefon numarasi girisi
                AnimatedVisibility(
                    visible = showPhoneInput,
                    enter = expandVertically(),
                    exit = shrinkVertically()
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = phoneInput,
                            onValueChange = { viewModel.onPhoneInputChanged(it) },
                            placeholder = { Text("+90 5XX XXX XX XX") },
                            modifier = Modifier.weight(1f),
                            singleLine = true,
                            shape = RoundedCornerShape(12.dp),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = MaterialTheme.colorScheme.primary,
                                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                                unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
                                cursorColor = MaterialTheme.colorScheme.primary
                            )
                        )
                        IconButton(
                            onClick = { viewModel.addMemberByPhone() },
                            enabled = phoneInput.isNotBlank() && !isResolvingPhone
                        ) {
                            if (isResolvingPhone) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    strokeWidth = 2.dp,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            } else {
                                Icon(
                                    Icons.Default.PersonAdd,
                                    contentDescription = "Ekle",
                                    tint = if (phoneInput.isNotBlank()) MaterialTheme.colorScheme.primary
                                           else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Kullanici bulunamadi dialog
                phoneNotFound?.let { phone ->
                    GlassDialog(onDismissRequest = { viewModel.consumePhoneNotFound() }) {
                        Column(
                            modifier = Modifier.padding(24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                "Kullanıcı Bulunamadı",
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Spacer(modifier = Modifier.height(12.dp))
                            Text(
                                "$phone numarasına sahip Elçim kullanıcısı bulunamadı.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            TextButton(onClick = { viewModel.consumePhoneNotFound() }) {
                                Text("Tamam")
                            }
                        }
                    }
                }

                // Rehber listesi
                Text(
                    text = "Kayıtlı Kişiler",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Rehber arama alanı
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { viewModel.onSearchQueryChanged(it) },
                    placeholder = { Text("Kişi ara...") },
                    leadingIcon = {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = "Ara",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    },
                    trailingIcon = {
                        if (searchQuery.isNotEmpty()) {
                            IconButton(onClick = { viewModel.onSearchQueryChanged("") }) {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = "Temizle",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
                        cursorColor = MaterialTheme.colorScheme.primary
                    )
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Contact list container
                if (isLoadingContacts) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                } else if (contacts.isEmpty() && searchQuery.isNotBlank()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(200.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "\"$searchQuery\" ile eşleşen kişi bulunamadı",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(300.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(contacts) { selectableContact ->
                            ContactSelectionItem(
                                selectableContact = selectableContact,
                                dark = dark,
                                onSelectionChanged = { viewModel.toggleContactSelection(selectableContact.userId) }
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

/**
 * Rehberdeki bir kişiyi seçim için gösteren component.
 * Glass efektli kart ile gösterilir.
 */
@Composable
private fun ContactSelectionItem(
    selectableContact: SelectableContact,
    dark: Boolean,
    onSelectionChanged: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .glass(dark = dark, shape = RoundedCornerShape(16.dp))
            .clickable { onSelectionChanged() }
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Avatar placeholder — solid renk
        Box(
            modifier = Modifier
                .size(40.dp)
                .padding(end = 12.dp),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.Default.Person,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp)
            )
        }

        // Contact info
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = selectableContact.displayName,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = selectableContact.phoneNumber,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Selection checkbox
        Checkbox(
            checked = selectableContact.isSelected,
            onCheckedChange = { onSelectionChanged() },
            colors = CheckboxDefaults.colors(
                checkedColor = MaterialTheme.colorScheme.primary,
                uncheckedColor = MaterialTheme.colorScheme.outline
            )
        )
    }
}
