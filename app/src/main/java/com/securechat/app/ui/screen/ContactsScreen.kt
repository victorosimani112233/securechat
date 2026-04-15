package com.securechat.app.ui.screen

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContactPhone
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.viewmodel.ContactsViewModel
import com.securechat.contacts.PhoneNumberNormalizer
import com.securechat.contacts.model.DeviceContact
import com.securechat.contacts.model.RegisteredContact
import com.securechat.storage.domain.Conversation
import kotlin.math.abs

/**
 * Kişi listesi ekranı.
 * Midnight Teal tasarım: koyu arka plan, canlı avatar gradientleri, koyu search bar.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContactsScreen(
    viewModel: ContactsViewModel = hiltViewModel(),
    onContactClick: (String) -> Unit,
    onBackClick: () -> Unit
) {
    val contacts by viewModel.contacts.collectAsStateWithLifecycle()
    val phoneContacts by viewModel.phoneContacts.collectAsStateWithLifecycle()
    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val permissionGranted by viewModel.permissionGranted.collectAsStateWithLifecycle()
    val isDiscovering by viewModel.isDiscovering.collectAsStateWithLifecycle()
    val manualUserId by viewModel.manualUserId.collectAsStateWithLifecycle()
    val recentConversations by viewModel.recentConversations.collectAsStateWithLifecycle()

    // Compose-uyumlu izin isteği launcher'ı
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            viewModel.onPermissionGranted()
        } else {
            viewModel.onPermissionDenied()
        }
    }

    // İzin zaten verilmişse ekran açıldığında keşfi ve rehber yüklemesini başlatır
    LaunchedEffect(permissionGranted) {
        if (permissionGranted) {
            viewModel.loadPhoneContacts()
            viewModel.discoverUsers()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Kişi Seç",
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
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
        ) {
            // Manuel kullanıcı ID girişi bölümü — EN ÜSTE, birincil yöntem
            item {
                ManualUserIdSection(
                    manualUserId = manualUserId,
                    onManualUserIdChanged = { viewModel.onManualUserIdChanged(it) },
                    onStartChat = {
                        val normalized = PhoneNumberNormalizer.normalizeToUserId(manualUserId.trim())
                        onContactClick(normalized)
                    }
                )

                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                    thickness = 0.5.dp
                )
            }

            // Geçmiş konuşmalar bölümü — hızlı erişim
            if (recentConversations.isNotEmpty()) {
                item {
                    Text(
                        text = "Geçmiş Konuşmalar",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                    )
                }
                items(recentConversations, key = { "conv_${it.id}" }) { conversation ->
                    RecentConversationItem(
                        conversation = conversation,
                        onClick = { onContactClick(conversation.peerId) }
                    )
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 72.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        thickness = 0.5.dp
                    )
                }
                item {
                    HorizontalDivider(
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        thickness = 0.5.dp
                    )
                }
            }

            // Arama çubuğu — koyu surface
            item {
                TextField(
                    value = searchQuery,
                    onValueChange = { viewModel.onSearchQueryChanged(it) },
                    modifier = Modifier.fillMaxWidth(),
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
                                Icon(Icons.Default.Close, contentDescription = "Temizle")
                            }
                        }
                    },
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        cursorColor = MaterialTheme.colorScheme.primary
                    ),
                    singleLine = true
                )
            }

            // Keşif işlemi devam ederken gösterge
            if (isDiscovering) {
                item {
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.2f),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Kişiler taranıyor...",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                }
            }

            // İzin verilmemişse izin isteği bölümü
            if (!permissionGranted) {
                item {
                    PermissionRequestSection(
                        onRequestPermission = {
                            permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
                        }
                    )
                }
            }

            // Kişi listesi veya boş durum
            val hasAnyContacts = contacts.isNotEmpty() || phoneContacts.isNotEmpty()
            if (!hasAnyContacts && recentConversations.isEmpty()) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 48.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        EmptyContactsState(
                            isSearching = searchQuery.isNotEmpty(),
                            hasPermission = permissionGranted
                        )
                    }
                }
            }

            // Kayıtlı (Elçi kullanan) kişiler
            if (contacts.isNotEmpty()) {
                item {
                    Text(
                        text = "Elçi Kullanıcıları",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                    )
                }
                items(contacts, key = { "reg_${it.userId}" }) { contact ->
                    ContactItem(
                        contact = contact,
                        onClick = { onContactClick(contact.userId) }
                    )
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 72.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        thickness = 0.5.dp
                    )
                }
            }

            // Telefon rehberindeki kişiler — izin verilmişse gösterilir
            if (phoneContacts.isNotEmpty()) {
                item {
                    Text(
                        text = "Telefon Rehberi",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.secondary,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                    )
                }
                items(phoneContacts, key = { "phone_${it.id}_${it.phoneNumber}" }) { contact ->
                    PhoneContactItem(
                        contact = contact,
                        onClick = {
                            // E.164 formatındaki numarayı userId formatına dönüştür
                            val normalized = PhoneNumberNormalizer.normalizeToUserId(
                                contact.phoneNumber.replace("+", "")
                            )
                            onContactClick(normalized)
                        }
                    )
                    HorizontalDivider(
                        modifier = Modifier.padding(start = 72.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                        thickness = 0.5.dp
                    )
                }
            }
        }
    }
}

/**
 * Manuel kullanıcı ID girişi bölümü.
 * Koyu surfaceVariant arka plan, cyan vurgulu alan.
 */
@Composable
private fun ManualUserIdSection(
    manualUserId: String,
    onManualUserIdChanged: (String) -> Unit,
    onStartChat: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
        ) {
            Text(
                text = "Telefon numarası ile sohbet başlat",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 8.dp)
            )
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = manualUserId,
                    onValueChange = onManualUserIdChanged,
                    modifier = Modifier.weight(1f),
                    placeholder = { Text("Telefon numarası girin") },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                        cursorColor = MaterialTheme.colorScheme.primary
                    )
                )
                Spacer(modifier = Modifier.width(8.dp))
                IconButton(
                    onClick = onStartChat,
                    enabled = manualUserId.isNotBlank()
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.Send,
                        contentDescription = "Sohbet başlat",
                        tint = if (manualUserId.isNotBlank())
                            MaterialTheme.colorScheme.primary
                        else
                            MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                    )
                }
            }
            Text(
                text = "Örnek: 5551234567, 05551234567 veya 905551234567",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                modifier = Modifier.padding(top = 4.dp)
            )
        }
    }
}

/**
 * Rehber izin isteği bölümü.
 * Koyu arka plan, cyan vurgulu buton.
 */
@Composable
private fun PermissionRequestSection(
    onRequestPermission: () -> Unit
) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 16.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = Icons.Default.ContactPhone,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Rehber erişimi ile Elçi kullanan kişilerinizi görebilirsiniz.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(12.dp))
            Button(
                onClick = onRequestPermission,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = Color(0xFF0D1117)
                )
            ) {
                Text("Rehber Erişimi Ver")
            }
        }
    }
}

/**
 * Boş kişi durumu mesajı.
 * Cyan tonlu ikon ve metin.
 */
@Composable
private fun EmptyContactsState(
    isSearching: Boolean,
    hasPermission: Boolean
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
                .background(
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.PersonSearch,
                contentDescription = null,
                modifier = Modifier.size(40.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        val titleText = when {
            isSearching -> "Sonuç bulunamadı"
            !hasPermission -> "Rehber izni gerekli"
            else -> "Kayıtlı kişi bulunamadı"
        }

        val bodyText = when {
            isSearching -> "Farklı bir arama terimi deneyin."
            !hasPermission -> "Kişilerinizi görmek için rehber erişimi verin\nveya yukarıdaki alandan numara ile sohbet başlatabilirsiniz."
            else -> "Elçi kullanan bir kişiniz bulunamadı.\nYukarıdaki alandan numara ile sohbet başlatabilirsiniz."
        }

        Text(
            text = titleText,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = bodyText,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

/**
 * Avatar için isim bazlı gradient renk paleti oluşturur.
 * Midnight Teal ile uyumlu, daha koyu ve canlı gradient çiftleri.
 */
private fun contactAvatarGradient(name: String): Brush {
    val colorPairs = listOf(
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
    val index = abs(name.hashCode()) % colorPairs.size
    val (startColor, endColor) = colorPairs[index]
    return Brush.linearGradient(colors = listOf(startColor, endColor))
}

/**
 * Kişi listesindeki tek bir kişi satırı.
 * Gradient dairesi içinde başlangıç harfi, isim ve telefon numarası gösterir.
 */
@Composable
fun ContactItem(
    contact: RegisteredContact,
    onClick: () -> Unit
) {
    ListItem(
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(vertical = 2.dp),
        headlineContent = {
            Text(
                text = contact.displayName,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
        },
        supportingContent = {
            Text(
                text = contact.phoneNumber,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        leadingContent = {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(contactAvatarGradient(contact.displayName)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = contact.displayName.firstOrNull()?.uppercase() ?: "?",
                    style = MaterialTheme.typography.titleSmall,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp
                )
            }
        },
        colors = ListItemDefaults.colors(
            containerColor = MaterialTheme.colorScheme.background
        )
    )
}

/**
 * Telefon rehberindeki tek bir kişi satırı.
 * Gradient dairesi içinde başlangıç harfi, isim ve telefon numarası gösterir.
 * Dokunulduğunda numara normalize edilerek sohbet başlatılır.
 */
@Composable
fun PhoneContactItem(
    contact: DeviceContact,
    onClick: () -> Unit
) {
    ListItem(
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(vertical = 2.dp),
        headlineContent = {
            Text(
                text = contact.displayName,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
        },
        supportingContent = {
            Text(
                text = contact.phoneNumber,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        leadingContent = {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(contactAvatarGradient(contact.displayName)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = contact.displayName.firstOrNull()?.uppercase() ?: "?",
                    style = MaterialTheme.typography.titleSmall,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp
                )
            }
        },
        colors = ListItemDefaults.colors(
            containerColor = MaterialTheme.colorScheme.background
        )
    )
}

/**
 * Geçmiş konuşma satırı.
 * Veritabanındaki mevcut konuşmalardan hızlı erişim sağlar.
 */
@Composable
private fun RecentConversationItem(
    conversation: Conversation,
    onClick: () -> Unit
) {
    val displayName = conversation.peerName.ifBlank { conversation.peerId }
    ListItem(
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(vertical = 2.dp),
        headlineContent = {
            Text(
                text = displayName,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface
            )
        },
        supportingContent = {
            Text(
                text = conversation.lastMessage ?: "Mesaj yok",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
        },
        leadingContent = {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(contactAvatarGradient(displayName)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = displayName.firstOrNull()?.uppercase() ?: "?",
                    style = MaterialTheme.typography.titleSmall,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp
                )
            }
        },
        colors = ListItemDefaults.colors(
            containerColor = MaterialTheme.colorScheme.background
        )
    )
}
