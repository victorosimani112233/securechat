package com.securechat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.securechat.app.util.CallReadinessHelper

/**
 * Conversations ekraninin ustunde gosterilen sari uyari.
 *
 * Gosterilme kosullari:
 *  - En az 1 izin verilmemis (battery / full-screen / notification / overlay)
 *  - Son 24 saatte dismiss edilmemis
 *
 * Tap → CallReadinessScreen acilir.
 * Sag X → 24 saat boyunca gizlenir.
 */
@Composable
fun CallReadinessBanner(
    onClick: () -> Unit
) {
    val context = LocalContext.current
    var visible by remember { mutableStateOf(CallReadinessHelper.shouldShowBanner(context)) }

    // Lifecycle observer — Settings/permissions ekranindan donunce yenile
    val lifecycleOwner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                visible = CallReadinessHelper.shouldShowBanner(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    if (!visible) return

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFFFFC107).copy(alpha = 0.15f))
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            Icons.Default.Warning,
            contentDescription = null,
            tint = Color(0xFFE65100)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Aramalar gecikebilir",
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = "Tap → Düzelt (1 dakika sürer)",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        IconButton(onClick = {
            CallReadinessHelper.dismissBanner(context)
            visible = false
        }) {
            Icon(
                Icons.Default.Close,
                contentDescription = "Gizle",
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
