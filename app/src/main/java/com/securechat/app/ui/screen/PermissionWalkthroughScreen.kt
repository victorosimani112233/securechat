package com.securechat.app.ui.screen

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.securechat.app.ui.theme.AzureDoodleBackdrop
import com.securechat.app.ui.theme.LocalDarkTheme

/**
 * Permission walkthrough — onboarding sonrasi sirayla 4 izin sunar:
 *   notif (Android 13+), contacts (rehber kesfi), mic (arama), camera (gorusme).
 *
 * Her satir karti:
 *   - ikon + baslik + aciklama ("Neden gerekli")
 *   - "Izin ver" butonu — Android runtime dialogu acar
 *   - Verildi ise yesil tick + buton disable
 *
 * Reddedilen permission'lar icin "Ayarlardan acabilirsiniz" snackbar yok —
 * kullanici devam edip uygulama icinde gerektiginde tekrar sorulur.
 */
private data class PermItem(
    val key: String,
    val icon: ImageVector,
    val accent: Color,
    val title: String,
    val rationale: String,
    val manifestPermission: String?
)

@Composable
fun PermissionWalkthroughScreen(
    onFinished: () -> Unit
) {
    val dark = LocalDarkTheme.current
    val context = LocalContext.current

    val items = remember {
        listOfNotNull(
            // POST_NOTIFICATIONS sadece Android 13+ (API 33)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                PermItem(
                    key = "notif",
                    icon = Icons.Default.Notifications,
                    accent = Color(0xFF3E7BFA),
                    title = "Bildirimler",
                    rationale = "Yeni mesaj ve aramalar için bildirim gösterilmesi gerekir.",
                    manifestPermission = Manifest.permission.POST_NOTIFICATIONS
                )
            } else null,
            PermItem(
                key = "contacts",
                icon = Icons.Default.Contacts,
                accent = Color(0xFF1F8E3D),
                title = "Rehber",
                rationale = "elçim kullanan kişileri rehberinizden keşfetmek için. Numaralar şifrelenmiş hash olarak gönderilir, sunucu plaintext görmez.",
                manifestPermission = Manifest.permission.READ_CONTACTS
            ),
            PermItem(
                key = "mic",
                icon = Icons.Default.Mic,
                accent = Color(0xFFEF6C00),
                title = "Mikrofon",
                rationale = "Sesli arama ve sesli mesaj kaydı için.",
                manifestPermission = Manifest.permission.RECORD_AUDIO
            ),
            PermItem(
                key = "camera",
                icon = Icons.Default.CameraAlt,
                accent = Color(0xFFAB47BC),
                title = "Kamera",
                rationale = "Görüntülü arama ve fotoğraf gönderimi için.",
                manifestPermission = Manifest.permission.CAMERA
            )
        )
    }

    // Granted state — her permission için
    val grantedMap: SnapshotStateMap<String, Boolean> = remember {
        mutableStateMapOf<String, Boolean>().apply {
            items.forEach { item ->
                val perm = item.manifestPermission
                this[item.key] = perm != null && ContextCompat.checkSelfPermission(context, perm) ==
                    PackageManager.PERMISSION_GRANTED
            }
        }
    }

    // Aktif izin isteği — hangi key için açıldı bilelim ki callback'te o key'i güncelleyelim
    var pendingKey by remember { androidx.compose.runtime.mutableStateOf<String?>(null) }

    val permLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        pendingKey?.let { grantedMap[it] = isGranted }
        pendingKey = null
    }

    Box(Modifier.fillMaxSize()) {
        AzureDoodleBackdrop(dark = dark)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
        ) {
            Spacer(Modifier.height(48.dp))
            Text(
                "Birkaç izin gerekiyor",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "İstediklerinizi şimdi verin, kalanları sonradan da verebilirsiniz.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(24.dp))

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(items, key = { it.key }) { item ->
                    PermissionCard(
                        item = item,
                        granted = grantedMap[item.key] == true,
                        onRequest = {
                            val perm = item.manifestPermission ?: return@PermissionCard
                            pendingKey = item.key
                            permLauncher.launch(perm)
                        }
                    )
                }
            }

            val allGranted = grantedMap.values.all { it }
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = onFinished,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
                shape = RoundedCornerShape(26.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                )
            ) {
                Text(
                    if (allGranted) "Hadi başlayalım" else "Devam et",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }
            if (!allGranted) {
                TextButton(
                    onClick = onFinished,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        "Bu izinleri sonra ver",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun PermissionCard(
    item: PermItem,
    granted: Boolean,
    onRequest: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                MaterialTheme.colorScheme.surface.copy(alpha = 0.6f),
                RoundedCornerShape(16.dp)
            )
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .background(item.accent.copy(alpha = 0.18f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                item.icon,
                contentDescription = null,
                tint = item.accent,
                modifier = Modifier.size(22.dp)
            )
        }
        Spacer(Modifier.size(14.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                item.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Spacer(Modifier.height(2.dp))
            Text(
                item.rationale,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.size(8.dp))
        if (granted) {
            Icon(
                Icons.Default.CheckCircle,
                contentDescription = "Verildi",
                tint = Color(0xFF1F8E3D),
                modifier = Modifier.size(28.dp)
            )
        } else {
            TextButton(onClick = onRequest) {
                Text("İzin ver", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
