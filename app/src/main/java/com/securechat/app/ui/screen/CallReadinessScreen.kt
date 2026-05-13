package com.securechat.app.ui.screen

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.BatteryFull
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import com.securechat.app.util.BatteryOptimizationHelper
import com.securechat.app.util.CallReadinessHelper

/**
 * "Aramaları kaçırmamak için" ekranı.
 *
 * 4 izin durumu listelenir; her biri tap'lanınca ilgili sistem dialog'u/ayar acilir.
 * Kullanici tum izinleri verince yesil tick gorur, "Devam Et" ile conversations'a gecer.
 *
 * Onboarding olarak ilk kayit sonrasi cagrilir. Settings'ten de erisilebilir.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallReadinessScreen(
    onContinue: () -> Unit,
    onSkip: (() -> Unit)? = null
) {
    val context = LocalContext.current
    var state by remember { mutableStateOf(CallReadinessHelper.currentState(context)) }

    // Lifecycle observer — Settings'ten donunce durumu yenile
    val lifecycleOwner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                state = CallReadinessHelper.currentState(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val notificationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {
        state = CallReadinessHelper.currentState(context)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Aramaları Kaçırma", fontWeight = FontWeight.SemiBold) },
                actions = {
                    if (onSkip != null) {
                        TextButton(onClick = onSkip) { Text("Atla") }
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(16.dp))

            Icon(
                Icons.Default.PhoneAndroid,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            Spacer(modifier = Modifier.height(16.dp))

            Text(
                text = "Aramalar gecikmesin",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Uygulama kapalıyken bile aramaların gerçek zamanlı gelmesi için bu izinleri verin. Tek tap'la tamamlayabilirsiniz.",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(24.dp))

            // 1. Pil optimizasyonu
            PermissionRow(
                icon = Icons.Default.BatteryFull,
                title = "Pil optimizasyonu",
                description = "FCM push'lar Doze moduna takılmasın",
                status = state.battery,
                onClick = {
                    BatteryOptimizationHelper.requestExemption(context)
                }
            )

            // 2. Tam ekran bildirim (Android 14+)
            if (state.fullScreenIntent != CallReadinessHelper.PermissionStatus.NOT_APPLICABLE) {
                Spacer(modifier = Modifier.height(8.dp))
                PermissionRow(
                    icon = Icons.Default.Fullscreen,
                    title = "Tam ekran bildirim",
                    description = "Kilit ekranında arama UI'ı için (Android 14+)",
                    status = state.fullScreenIntent,
                    onClick = {
                        CallReadinessHelper.openFullScreenIntentSettings(context)
                    }
                )
            }

            // 3. Bildirim izni (Android 13+)
            if (state.notification != CallReadinessHelper.PermissionStatus.NOT_APPLICABLE) {
                Spacer(modifier = Modifier.height(8.dp))
                PermissionRow(
                    icon = Icons.Default.Notifications,
                    title = "Bildirim izni",
                    description = "Mesaj ve arama bildirimleri",
                    status = state.notification,
                    onClick = {
                        if (state.notification == CallReadinessHelper.PermissionStatus.GRANTED) {
                            CallReadinessHelper.openAppNotificationSettings(context)
                        } else {
                            notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    }
                )
            }

            // 4. Diger uygulamalar uzerinde goster (overlay)
            Spacer(modifier = Modifier.height(8.dp))
            PermissionRow(
                icon = Icons.Default.PhoneAndroid,
                title = "Üstte göster",
                description = "Arka planda arama ekranı için",
                status = state.overlay,
                onClick = {
                    CallReadinessHelper.openOverlaySettings(context)
                }
            )

            Spacer(modifier = Modifier.height(32.dp))

            Button(
                onClick = {
                    CallReadinessHelper.markOnboardingShown(context)
                    onContinue()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .clip(RoundedCornerShape(12.dp))
            ) {
                Text(
                    text = if (state.allGranted) "Harika, devam et" else "Şimdilik devam et",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Bu ayarlara her zaman Ayarlar → Arama bölümünden ulaşabilirsiniz.",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun PermissionRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    description: String,
    status: CallReadinessHelper.PermissionStatus,
    onClick: () -> Unit
) {
    val granted = status == CallReadinessHelper.PermissionStatus.GRANTED
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp)),
        onClick = onClick,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (granted) MaterialTheme.colorScheme.primary
                       else MaterialTheme.colorScheme.error,
                modifier = Modifier.size(28.dp)
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(title, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                Text(
                    text = description,
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (granted) {
                Icon(
                    Icons.Default.CheckCircle,
                    contentDescription = "Verildi",
                    tint = Color(0xFF34A853)
                )
            } else {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowForward,
                    contentDescription = "Düzelt",
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}
