package com.securechat.app.ui.screen

import android.Manifest
import android.content.pm.PackageManager
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
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import com.securechat.contacts.PhoneNumberNormalizer

/**
 * Telefon doğrulama ve kayıt ekranı.
 * Midnight Teal tasarım: koyu arka plan, cyan gradient kalkan, cyan vurgulu alanlar.
 */
@Composable
fun PhoneVerificationScreen(
    onVerified: (name: String, phone: String) -> Unit
) {
    var displayName by remember { mutableStateOf("") }
    var phoneNumber by remember { mutableStateOf("") }
    var countryCode by remember { mutableStateOf("+90") }

    // Permission handling
    val context = LocalContext.current
    val requiredPermissions = arrayOf(
        Manifest.permission.READ_CONTACTS,
        Manifest.permission.RECORD_AUDIO,
        Manifest.permission.CAMERA,
        Manifest.permission.POST_NOTIFICATIONS
    )

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.values.all { it }
        if (allGranted) {
            // Tüm izinler verildi, kayıt işlemine devam et
            val rawPhone = "$countryCode$phoneNumber".replace(" ", "")
            val normalizedDigits = PhoneNumberNormalizer.normalizeDigits(rawPhone)
            onVerified(displayName.trim(), "+$normalizedDigits")
        } else {
            // İzinler reddedildi - kullanıcıya bilgi verilebilir
            // TODO: İsteğe bağlı - kullanıcıya neden izin gerektiğini açıklayan dialog göster
        }
    }

    fun requestPermissionsAndProceed() {
        val permissionsToRequest = requiredPermissions.filter { permission ->
            ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED
        }

        // DEBUG: Hangi izinlerin eksik olduğunu göster
        requiredPermissions.forEach { permission ->
            val granted = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
            android.util.Log.d("PermissionCheck", "$permission: ${if (granted) "GRANTED" else "DENIED"}")
        }

        if (permissionsToRequest.isEmpty()) {
            // Tüm izinler zaten var, direkt devam et
            android.util.Log.d("PermissionCheck", "Tüm izinler zaten var, devam ediliyor")
            val rawPhone = "$countryCode$phoneNumber".replace(" ", "")
            val normalizedDigits = PhoneNumberNormalizer.normalizeDigits(rawPhone)
            onVerified(displayName.trim(), "+$normalizedDigits")
        } else {
            // İzinleri talep et
            android.util.Log.d("PermissionCheck", "İzinler talep ediliyor: ${permissionsToRequest.joinToString()}")
            permissionLauncher.launch(requiredPermissions)
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background
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

            // Uygulama adı — cyan vurgulu
            Text(
                text = "ELÇİM",
                style = MaterialTheme.typography.headlineLarge,
                color = MaterialTheme.colorScheme.primary,
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

            // İsim girişi — koyu surfaceVariant arka plan, cyan focus border
            OutlinedTextField(
                value = displayName,
                onValueChange = { displayName = it },
                label = { Text("Adınız") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                placeholder = { Text("Örneğin: Ahmet Yılmaz") },
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
                    cursorColor = MaterialTheme.colorScheme.primary
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
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
                        cursorColor = MaterialTheme.colorScheme.primary
                    )
                )

                OutlinedTextField(
                    value = phoneNumber,
                    onValueChange = { phoneNumber = it },
                    label = { Text("Telefon Numarası") },
                    modifier = Modifier.weight(1f),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    singleLine = true,
                    placeholder = { Text("5XX XXX XX XX") },
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
                        focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                        unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f),
                        cursorColor = MaterialTheme.colorScheme.primary
                    )
                )
            }

            Spacer(modifier = Modifier.height(36.dp))

            // Başla butonu — canlı cyan
            Button(
                onClick = {
                    requestPermissionsAndProceed()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                enabled = displayName.isNotBlank() && phoneNumber.length >= 10,
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = Color(0xFF0D1117)
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
}
