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
import androidx.compose.foundation.text.KeyboardActions
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.securechat.app.ui.util.PhoneFormValidation
import com.securechat.contacts.PhoneNumberNormalizer
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.azure
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
    // Form girdileri ve UI ilerleme `rememberSaveable` ile saklanir — rotation veya
    // process death sonrasi kullanicinin yazdiklari korunur. Dialog flag'leri de
    // saveable: orientation degisirken dialog kapanmaz.
    var displayName by rememberSaveable { mutableStateOf("") }
    var phoneNumber by rememberSaveable { mutableStateOf("") }
    var countryCode by rememberSaveable { mutableStateOf("+90") }
    var showContactsPermissionDialog by rememberSaveable { mutableStateOf(false) }
    // Submit-attempt bayragi: kullanici "Basla" butonuna basana kadar hatalar
    // gosterilmez — typing sirasinda anlik kirmizi flash UX'i bozar. Submit'ten
    // sonra hata + odaklanma + supportingText akisi devreye girer.
    var submitAttempted by rememberSaveable { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current

    // Validation sonuclari — submitAttempted true ise UI'da gosterilir.
    val nameError = PhoneFormValidation.validateName(displayName)
    val countryCodeError = PhoneFormValidation.validateCountryCode(countryCode)
    val phoneError = PhoneFormValidation.validatePhone(phoneNumber)
    val isFormValid = nameError == null && countryCodeError == null && phoneError == null

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

    /** Validasyon hata mesajlari — UI label haritalama. Kullanici dostu metinler. */
    fun nameErrorMessage(e: PhoneFormValidation.NameError?): String? = when (e) {
        null -> null
        PhoneFormValidation.NameError.Empty -> "Adınızı giriniz"
        PhoneFormValidation.NameError.TooShort -> "En az ${PhoneFormValidation.MIN_NAME_LENGTH} karakter"
        PhoneFormValidation.NameError.TooLong -> "En fazla ${PhoneFormValidation.MAX_NAME_LENGTH} karakter"
        PhoneFormValidation.NameError.InvalidChars -> "Yalnızca harf, boşluk, tire ve kesme işareti"
    }
    fun countryCodeErrorMessage(e: PhoneFormValidation.CountryCodeError?): String? = when (e) {
        null -> null
        PhoneFormValidation.CountryCodeError.Empty -> "Ülke kodu boş"
        PhoneFormValidation.CountryCodeError.MissingPlus -> "+ ile başlamalı"
        PhoneFormValidation.CountryCodeError.NonDigit -> "Yalnızca rakam"
        PhoneFormValidation.CountryCodeError.TooShort -> "En az 1 hane"
        PhoneFormValidation.CountryCodeError.TooLong -> "En fazla 4 hane"
    }
    fun phoneErrorMessage(e: PhoneFormValidation.PhoneError?): String? = when (e) {
        null -> null
        PhoneFormValidation.PhoneError.Empty -> "Telefon numaranızı giriniz"
        PhoneFormValidation.PhoneError.TooShort -> "10 hane gerekli"
        PhoneFormValidation.PhoneError.TooLong -> "Sadece 10 hane"
        PhoneFormValidation.PhoneError.NonDigit -> "Yalnızca rakam"
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
                color = MaterialTheme.azure.azure,
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
                    val showNameError = submitAttempted && nameError != null
                    OutlinedTextField(
                        value = displayName,
                        onValueChange = { displayName = it },
                        label = { Text("Adınız") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        placeholder = { Text("Örneğin: Ahmet Yılmaz") },
                        shape = RoundedCornerShape(12.dp),
                        isError = showNameError,
                        supportingText = if (showNameError) {
                            { Text(nameErrorMessage(nameError) ?: "") }
                        } else null,
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Text,
                            imeAction = ImeAction.Next
                        ),
                        keyboardActions = KeyboardActions(
                            onNext = { focusManager.moveFocus(FocusDirection.Down) }
                        ),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = MaterialTheme.azure.azure,
                            unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                            cursorColor = MaterialTheme.azure.azure
                        )
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    // Ülke kodu ve telefon numarası — yan yana
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        val showCountryError = submitAttempted && countryCodeError != null
                        OutlinedTextField(
                            value = countryCode,
                            onValueChange = { countryCode = it },
                            label = { Text("Kod") },
                            modifier = Modifier.width(90.dp),
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Phone,
                                imeAction = ImeAction.Next
                            ),
                            keyboardActions = KeyboardActions(
                                onNext = { focusManager.moveFocus(FocusDirection.Right) }
                            ),
                            singleLine = true,
                            shape = RoundedCornerShape(12.dp),
                            isError = showCountryError,
                            supportingText = if (showCountryError) {
                                { Text(countryCodeErrorMessage(countryCodeError) ?: "") }
                            } else null,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = MaterialTheme.azure.azure,
                                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                cursorColor = MaterialTheme.azure.azure
                            )
                        )

                        val showPhoneError = submitAttempted && phoneError != null
                        OutlinedTextField(
                            value = phoneNumber,
                            onValueChange = { phoneNumber = it.filter { c -> c.isDigit() }.take(10) },
                            label = { Text("Telefon Numarası") },
                            modifier = Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Phone,
                                imeAction = ImeAction.Done
                            ),
                            keyboardActions = KeyboardActions(
                                onDone = {
                                    keyboardController?.hide()
                                    submitAttempted = true
                                    if (isFormValid) requestPermissionsAndProceed()
                                }
                            ),
                            visualTransformation = com.securechat.app.util.PhoneVisualTransformation(),
                            singleLine = true,
                            placeholder = { Text("5XX XXX XX XX") },
                            shape = RoundedCornerShape(12.dp),
                            isError = showPhoneError,
                            supportingText = if (showPhoneError) {
                                { Text(phoneErrorMessage(phoneError) ?: "") }
                            } else null,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedBorderColor = MaterialTheme.azure.azure,
                                unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                                cursorColor = MaterialTheme.azure.azure
                            )
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(36.dp))

            // Başla butonu — azure pill
            // Buton DAIMA enabled — kullanici tikladiginda submitAttempted true olur
            // ve hatalar gosterilir (best practice: kullanici neden gidemedigini gorur).
            // Form valid degilse onClick noop'a duser, kullanici hatalari gorur.
            Button(
                onClick = {
                    submitAttempted = true
                    if (isFormValid) {
                        keyboardController?.hide()
                        requestPermissionsAndProceed()
                    } else {
                        // Hatali alana focus ver — ilk hatali alana atla
                        when {
                            nameError != null -> focusManager.moveFocus(FocusDirection.Up)
                            countryCodeError != null -> { /* zaten odak alabilir */ }
                            phoneError != null -> { /* phone field zaten son */ }
                        }
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(100.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.azure.azure,
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
