package com.securechat.app.ui.screen

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContactPhone
import androidx.compose.material.icons.filled.Dialpad
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Share
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
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.securechat.app.ui.components.GeneratedAvatar
import com.securechat.app.ui.components.GlassDialog
import com.securechat.app.ui.viewmodel.ContactsViewModel
import com.securechat.contacts.PhoneNumberNormalizer
import android.content.Intent
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import com.securechat.app.ui.components.COUNTRY_CODES
import com.securechat.app.ui.components.CountryCodePicker
import com.securechat.contacts.model.DeviceContact
import com.securechat.contacts.model.RegisteredContact
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.theme.MonoFamily
import com.securechat.app.ui.theme.DisplayFamily
import kotlin.math.abs

private val AZ_AVATAR_COLORS_CONTACTS = listOf(
    Color(0xFF3E7BFA), Color(0xFF6B737D), Color(0xFF8A929C),
    Color(0xFF5D6570), Color(0xFF4A535E), Color(0xFF9BA3AE),
)

/**
 * Kişi listesi ekranı.
 * Azure glassmorphism tasarım.
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
    val resolvedUserId by viewModel.resolvedUserId.collectAsStateWithLifecycle()
    val userNotFound by viewModel.userNotFound.collectAsStateWithLifecycle()

    // Sunucudan UUID cozumlendiginde sohbete git
    LaunchedEffect(resolvedUserId) {
        val uid = resolvedUserId
        if (uid != null) {
            viewModel.consumeResolvedUserId()
            onContactClick(uid)
        }
    }

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

    val dark = LocalDarkTheme.current
    var showManualInput by remember { mutableStateOf(false) }
    val context = androidx.compose.ui.platform.LocalContext.current

    // Kullanıcı bulunamadı popup'ı
    userNotFound?.let { phoneNumber ->
        GlassDialog(onDismissRequest = { viewModel.consumeUserNotFound() }) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(8.dp)
            ) {
                Icon(
                    Icons.Default.PersonSearch,
                    contentDescription = null,
                    modifier = Modifier.size(40.dp),
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    "Kullanıcı Bulunamadı",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurface
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    "$phoneNumber numaralı kullanıcı Elçim'de kayıtlı değil.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(20.dp))
                Button(
                    onClick = {
                        viewModel.consumeUserNotFound()
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(
                                Intent.EXTRA_TEXT,
                                "Elçim uygulamasını indir, güvenli bir şekilde mesajlaşalım! https://elcim.app"
                            )
                        }
                        context.startActivity(Intent.createChooser(shareIntent, "Davet gönder"))
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = Color.White
                    ),
                    shape = RoundedCornerShape(20.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Davet Gönder")
                }
                Spacer(modifier = Modifier.height(8.dp))
                TextButton(onClick = { viewModel.consumeUserNotFound() }) {
                    Text("Kapat")
                }
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

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
                actions = {
                    val active = showManualInput
                    Surface(
                        onClick = { showManualInput = !showManualInput },
                        shape = RoundedCornerShape(20.dp),
                        color = if (active) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                                else Color.Transparent,
                        modifier = Modifier.padding(end = 8.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(
                                Icons.Default.Dialpad,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                                tint = if (active) MaterialTheme.colorScheme.primary
                                       else MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                "Numara Gir",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.Medium,
                                color = if (active) MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.onSurfaceVariant
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
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets(0)
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 8.dp)
        ) {
            // Manuel kullanıcı ID girişi bölümü — tuş ikonu ile açılır
            item {
                AnimatedVisibility(
                    visible = showManualInput,
                    enter = expandVertically(),
                    exit = shrinkVertically()
                ) {
                    Column {
                        ManualUserIdSection(
                            manualUserId = manualUserId,
                            onManualUserIdChanged = { viewModel.onManualUserIdChanged(it) },
                            onStartChat = { countryCode ->
                                val raw = manualUserId.trim()
                                // Ulke kodunu basina ekle (+ ile baslamiyorsa)
                                val input = if (raw.startsWith("+")) raw
                                            else "$countryCode$raw"
                                val normalizedInput = PhoneNumberNormalizer.normalizeDigits(input)
                                val match = contacts.firstOrNull { reg ->
                                    PhoneNumberNormalizer.normalizeDigits(reg.phoneNumber) == normalizedInput
                                }
                                if (match != null) {
                                    onContactClick(match.userId)
                                } else if (raw.length == 36 && raw.contains("-")) {
                                    onContactClick(raw)
                                } else {
                                    viewModel.resolvePhoneToUuid(input)
                                }
                            }
                        )
                        HorizontalDivider(
                            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
                            thickness = 0.5.dp
                        )
                    }
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
            if (!hasAnyContacts) {
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

            // Kayıtlı (Elçim kullanan) kişiler
            if (contacts.isNotEmpty()) {
                item {
                    Text(
                        text = "Elçim Kullanıcıları",
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
                val registeredNumbers = contacts.map {
                    PhoneNumberNormalizer.normalizeDigits(it.phoneNumber)
                }.toSet()

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
                    val normalized = PhoneNumberNormalizer.normalizeDigits(contact.phoneNumber)
                    val isRegistered = normalized in registeredNumbers
                    PhoneContactItem(
                        contact = contact,
                        isRegistered = isRegistered,
                        onClick = {
                            val match = contacts.firstOrNull { reg ->
                                PhoneNumberNormalizer.normalizeDigits(reg.phoneNumber) == normalized
                            }
                            if (match != null) {
                                onContactClick(match.userId)
                            }
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
    } // Box
}

/**
 * Manuel kullanıcı ID girişi bölümü.
 * Koyu surfaceVariant arka plan, cyan vurgulu alan.
 */
@Composable
private fun ManualUserIdSection(
    manualUserId: String,
    onManualUserIdChanged: (String) -> Unit,
    onStartChat: (countryCode: String) -> Unit
) {
    var selectedCountryCode by remember { mutableStateOf(COUNTRY_CODES.first()) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        CountryCodePicker(
            selectedCode = selectedCountryCode,
            onCodeSelected = { selectedCountryCode = it }
        )
        OutlinedTextField(
            value = manualUserId,
            onValueChange = { onManualUserIdChanged(it.filter { c -> c.isDigit() }.take(10)) },
            modifier = Modifier.weight(1f),
            placeholder = { Text("5XX XXX XX XX") },
            singleLine = true,
            shape = RoundedCornerShape(12.dp),
            textStyle = MaterialTheme.typography.bodyMedium,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
            visualTransformation = com.securechat.app.util.PhoneVisualTransformation(),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = MaterialTheme.colorScheme.primary,
                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                cursorColor = MaterialTheme.colorScheme.primary
            )
        )
        Spacer(modifier = Modifier.width(2.dp))
        IconButton(
            onClick = { onStartChat(selectedCountryCode.code) },
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
}

/**
 * Rehber izin isteği bölümü.
 * Koyu arka plan, cyan vurgulu buton.
 */
@Composable
private fun PermissionRequestSection(
    onRequestPermission: () -> Unit
) {
    val dark = LocalDarkTheme.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp)
            .glass(dark, strong = true)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
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
                text = "Rehber erişimi ile Elçim kullanan kişilerinizi görebilirsiniz.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(12.dp))
            Button(
                onClick = onRequestPermission,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF3E7BFA),
                    contentColor = Color.White
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
            else -> "Elçim kullanan bir kişiniz bulunamadı.\nYukarıdaki alandan numara ile sohbet başlatabilirsiniz."
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
 * Kişi listesindeki tek bir kişi satırı.
 * Gradient dairesi içinde başlangıç harfi, isim ve telefon numarası gösterir.
 */
@Composable
fun ContactItem(
    contact: RegisteredContact,
    onClick: () -> Unit
) {
    val dark = LocalDarkTheme.current

    ListItem(
        modifier = Modifier
            .padding(horizontal = 12.dp)
            .glass(dark, shape = RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
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
            GeneratedAvatar(
                name = contact.displayName,
                size = 48.dp
            )
        },
        colors = ListItemDefaults.colors(
            containerColor = Color.Transparent
        )
    )
}

/**
 * Telefon rehberindeki tek bir kişi satırı.
 * Kayıtlı değilse "Davet Et" butonu gösterir.
 */
@Composable
fun PhoneContactItem(
    contact: DeviceContact,
    isRegistered: Boolean = false,
    onClick: () -> Unit
) {
    val dark = LocalDarkTheme.current
    val context = androidx.compose.ui.platform.LocalContext.current

    ListItem(
        modifier = Modifier
            .padding(horizontal = 12.dp)
            .glass(dark, shape = RoundedCornerShape(16.dp))
            .then(if (isRegistered) Modifier.clickable(onClick = onClick) else Modifier),
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
            GeneratedAvatar(
                name = contact.displayName,
                size = 48.dp
            )
        },
        trailingContent = if (!isRegistered) {
            {
                Button(
                    onClick = {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(
                                Intent.EXTRA_TEXT,
                                "Elçim uygulamasını indir, güvenli bir şekilde mesajlaşalım! https://elcim.app"
                            )
                        }
                        context.startActivity(Intent.createChooser(shareIntent, "Davet gönder"))
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                        contentColor = MaterialTheme.colorScheme.primary
                    ),
                    contentPadding = ButtonDefaults.ContentPadding.let {
                        androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                    },
                    shape = RoundedCornerShape(20.dp)
                ) {
                    Icon(
                        Icons.Default.Share,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Davet Et", fontSize = 12.sp)
                }
            }
        } else null,
        colors = ListItemDefaults.colors(
            containerColor = Color.Transparent
        )
    )
}

