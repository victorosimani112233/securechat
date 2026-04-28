package com.securechat.app.ui.screen

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.TelephonyManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.ui.res.painterResource
import com.securechat.app.R
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.securechat.contacts.PhoneNumberNormalizer
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.app.ui.theme.MonoFamily
import com.securechat.app.ui.theme.DisplayFamily

/**
 * Telefon doğrulama ve kayıt ekranı.
 * Azure glassmorphism tasarım.
 */
@Composable
fun PhoneVerificationScreen(
    onVerified: (name: String, phone: String) -> Unit
) {
    var displayName by remember { mutableStateOf("") }
    var phoneNumber by remember { mutableStateOf("") }
    var countryCode by remember { mutableStateOf("+90") }
    var showContactsPermissionDialog by remember { mutableStateOf(false) }

    // Permission handling
    val context = LocalContext.current

    // Telefon numarasi izni — SDK 33+ icin READ_PHONE_NUMBERS, onceki icin READ_PHONE_STATE
    val phonePermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Manifest.permission.READ_PHONE_NUMBERS
    } else {
        Manifest.permission.READ_PHONE_STATE
    }

    val requiredPermissions = arrayOf(
        Manifest.permission.READ_CONTACTS,
        Manifest.permission.RECORD_AUDIO,
        Manifest.permission.CAMERA,
        Manifest.permission.POST_NOTIFICATIONS,
        phonePermission
    )

    /**
     * SIM karttan telefon numarasini okur.
     * Numara +90 ile basliyorsa ulke kodunu ayirir ve sadece yerel kismi dondurur.
     * Operator numarayi SIM'de saklamiyorsa bos doner.
     */
    fun readPhoneNumber(): String {
        try {
            val hasPermission = ContextCompat.checkSelfPermission(context, phonePermission) == PackageManager.PERMISSION_GRANTED
            if (!hasPermission) return ""

            val tm = context.getSystemService(android.content.Context.TELEPHONY_SERVICE) as? TelephonyManager
            @Suppress("DEPRECATION")
            val line = tm?.line1Number
            if (line.isNullOrBlank()) return ""

            // Numarayi temizle: +, bosluk, tire kaldir
            val digits = line.replace(Regex("[^0-9]"), "")

            // Turkiye formati: 90XXXXXXXXXX (12 hane) → yerel kisim: 5XXXXXXXXX
            if (digits.startsWith("90") && digits.length == 12) {
                return digits.substring(2) // "5551234567"
            }
            // 05XXXXXXXXX (11 hane) → yerel kisim
            if (digits.startsWith("0") && digits.length == 11) {
                return digits.substring(1)
            }
            // 5XXXXXXXXX (10 hane) → oldugu gibi
            if (digits.length == 10) {
                return digits
            }
            // Diger ulke formatlari: tum rakamlari dondur
            return digits
        } catch (e: Exception) {
            android.util.Log.e("PhoneVerification", "Numara okunamadi: ${e.message}")
            return ""
        }
    }

    // Ekran acildiginda izin varsa numarayi oku
    LaunchedEffect(Unit) {
        val number = readPhoneNumber()
        if (number.isNotBlank() && phoneNumber.isBlank()) {
            phoneNumber = number
            android.util.Log.d("PhoneVerification", "SIM numara otomatik dolduruldu: ${number.take(4)}...")
        }
    }

    /** Kullanici adi icin tehlikeli karakterleri temizle. */
    fun sanitizeName(name: String): String {
        return name.trim()
            .replace(Regex("[;'\"\\\\\\-\\-]"), "")
            .replace(Regex("\\s+"), " ")
            .take(50)
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        // Telefon izni verildiyse ve numara bossa, SIM'den oku
        val phoneGranted = permissions[phonePermission] == true
        if (phoneGranted && phoneNumber.isBlank()) {
            val number = readPhoneNumber()
            if (number.isNotBlank()) {
                phoneNumber = number
                android.util.Log.d("PhoneVerification", "Izin sonrasi numara dolduruldu: ${number.take(4)}...")
                // Numara yeni doldurulduysa kullaniciya gosterelim, hemen devam etmeyelim
                return@rememberLauncherForActivityResult
            }
        }

        // READ_CONTACTS zorunlu — verilmediyse kaydi engelle ve aciklama goster
        val contactsGranted = permissions[Manifest.permission.READ_CONTACTS] == true
        if (!contactsGranted) {
            android.util.Log.w("PermissionCheck", "READ_CONTACTS reddedildi, kayit engellendi")
            showContactsPermissionDialog = true
            return@rememberLauncherForActivityResult
        }

        // READ_CONTACTS verildi, diger izinler opsiyonel — devam et
        if (phoneNumber.length >= 10) {
            val rawPhone = "$countryCode$phoneNumber".replace(" ", "")
            val normalizedDigits = PhoneNumberNormalizer.normalizeDigits(rawPhone)
            onVerified(sanitizeName(displayName), "+$normalizedDigits")
        }
    }

    fun requestPermissionsAndProceed() {
        val permissionsToRequest = requiredPermissions.filter { permission ->
            ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED
        }

        // DEBUG: Hangi izinlerin eksik oldugunu goster
        requiredPermissions.forEach { permission ->
            val granted = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
            android.util.Log.d("PermissionCheck", "$permission: ${if (granted) "GRANTED" else "DENIED"}")
        }

        // READ_CONTACTS zorunlu izin kontrol — verilmemisse izin iste
        val contactsGranted = ContextCompat.checkSelfPermission(
            context, Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED

        if (permissionsToRequest.isEmpty()) {
            // Tum izinler zaten var, direkt devam et
            android.util.Log.d("PermissionCheck", "Tum izinler zaten var, devam ediliyor")
            val rawPhone = "$countryCode$phoneNumber".replace(" ", "")
            val normalizedDigits = PhoneNumberNormalizer.normalizeDigits(rawPhone)
            onVerified(sanitizeName(displayName), "+$normalizedDigits")
        } else if (!contactsGranted) {
            // READ_CONTACTS henuz verilmedi — tum izinleri talep et
            android.util.Log.d("PermissionCheck", "READ_CONTACTS gerekli, izinler talep ediliyor")
            permissionLauncher.launch(requiredPermissions)
        } else {
            // READ_CONTACTS var ama diger izinler eksik — opsiyonel izinleri iste, devam et
            android.util.Log.d("PermissionCheck", "Opsiyonel izinler talep ediliyor: ${permissionsToRequest.joinToString()}")
            permissionLauncher.launch(requiredPermissions)
        }
    }

    // Rehber izni zorunlu aciklama dialog'u
    if (showContactsPermissionDialog) {
        AlertDialog(
            onDismissRequest = { showContactsPermissionDialog = false },
            title = { Text("Rehber Erisimi Gerekli") },
            text = {
                Text(
                    "Rehber erisimi uygulamanin temel islevleri icin gereklidir. " +
                    "Kisilarinizi bulabilmek ve guvenli mesajlasma baslatabilmek icin " +
                    "lutfen rehber erisim iznini verin."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showContactsPermissionDialog = false
                    // Izinleri tekrar iste
                    permissionLauncher.launch(requiredPermissions)
                }) {
                    Text("Tekrar Dene")
                }
            },
            dismissButton = {
                TextButton(onClick = { showContactsPermissionDialog = false }) {
                    Text("Iptal")
                }
            }
        )
    }

    val dark = LocalDarkTheme.current

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

    Scaffold(
        containerColor = Color.Transparent
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Spacer(modifier = Modifier.height(48.dp))

            // Uygulama logosu
            Image(
                painter = painterResource(id = R.mipmap.ic_launcher_foreground),
                contentDescription = "ELÇİM",
                modifier = Modifier
                    .size(96.dp)
                    .clip(RoundedCornerShape(20.dp))
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Uygulama adı
            Text(
                text = "ELÇİM",
                style = MaterialTheme.typography.headlineLarge,
                color = Color(0xFF3E7BFA),
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Alt başlık
            Text(
                text = "Güvenli mesajlaşma",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(12.dp))

            // E2E şifreleme açıklaması
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.padding(horizontal = 16.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Lock,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.secondary
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "Mesajlarınız uçtan uca şifrelenir. Kimse okuyamaz.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    fontSize = 12.sp
                )
            }

            Spacer(modifier = Modifier.height(48.dp))

            // Form area with glass
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .glass(dark, strong = true)
                    .padding(24.dp)
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    // Kayıt başlığı
                    Text(
                        text = "Kayıt Ol",
                        style = MaterialTheme.typography.titleLarge,
                        textAlign = TextAlign.Center,
                        color = MaterialTheme.colorScheme.onSurface,
                        fontWeight = FontWeight.SemiBold
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    Text(
                        text = "Bilgilerinizi girerek başlayabilirsiniz.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center
                    )

                    Spacer(modifier = Modifier.height(28.dp))

                    // İsim girişi
                    OutlinedTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        label = { Text("Adınız") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        placeholder = { Text("Örneğin: Ahmet Yılmaz") },
                        shape = RoundedCornerShape(12.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color(0xFF3E7BFA),
                            unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                            cursorColor = Color(0xFF3E7BFA)
                        )
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    // Ülke kodu ve telefon numarası — yan yana
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        OutlinedTextField(
                            value = countryCode,
                            onValueChange = { countryCode = it },
                            label = { Text("Kod") },
                            modifier = Modifier.width(90.dp),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                            singleLine = true,
                            shape = RoundedCornerShape(12.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = Color(0xFF3E7BFA),
                                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                cursorColor = Color(0xFF3E7BFA)
                            )
                        )

                        OutlinedTextField(
                            value = phoneNumber,
                            onValueChange = { phoneNumber = it.filter { c -> c.isDigit() }.take(10) },
                            label = { Text("Telefon Numarası") },
                            modifier = Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                            visualTransformation = com.securechat.app.util.PhoneVisualTransformation(),
                            singleLine = true,
                            placeholder = { Text("5XX XXX XX XX") },
                            shape = RoundedCornerShape(12.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = Color(0xFF3E7BFA),
                                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                cursorColor = Color(0xFF3E7BFA)
                            )
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(36.dp))

            // Başla butonu — azure pill
            Button(
                onClick = {
                    requestPermissionsAndProceed()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                enabled = displayName.isNotBlank() && phoneNumber.length >= 10,
                shape = RoundedCornerShape(100.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF3E7BFA),
                    contentColor = Color.White
                )
            ) {
                Text(
                    "Başla",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Spacer(modifier = Modifier.height(48.dp))
        }
    }
    } // Box
}
