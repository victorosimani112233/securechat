package com.securechat.app.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.media.model.CallState

/**
 * Bağlantı kalitesi indicator: 3 çubuklu sinyal göstergesi.
 * GOOD (3 yeşil çubuk), FAIR (2 sarı), POOR (1 kırmızı), RECONNECTING (yanıp sönen).
 */
enum class CallQuality { GOOD, FAIR, POOR, RECONNECTING }

@Composable
fun CallQualityIndicator(
    quality: CallQuality,
    modifier: Modifier = Modifier
) {
    val color = when (quality) {
        CallQuality.GOOD -> Color(0xFF4CAF50)
        CallQuality.FAIR -> Color(0xFFFFC107)
        CallQuality.POOR -> Color(0xFFF44336)
        CallQuality.RECONNECTING -> Color(0xFFFF5722)
    }

    val activeBars = when (quality) {
        CallQuality.GOOD -> 3
        CallQuality.FAIR -> 2
        CallQuality.POOR -> 1
        CallQuality.RECONNECTING -> 0
    }

    val infiniteTransition = rememberInfiniteTransition(label = "quality")
    val pulse by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(800),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse"
    )

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        repeat(3) { index ->
            val isActive = index < activeBars
            val barAlpha = if (quality == CallQuality.RECONNECTING) pulse
                else if (isActive) 1f else 0.25f
            Box(
                modifier = Modifier
                    .width(3.dp)
                    .height(((index + 1) * 4 + 4).dp)
                    .alpha(barAlpha)
                    .background(color, RoundedCornerShape(1.dp))
            )
        }
    }
}

/**
 * Aramayı state'e göre kalite seviyesi tahmin eder.
 * Gerçek WebRTC stats için ileride PeerConnectionManager.getStats() entegre edilebilir.
 */
fun CallState?.toCallQuality(): CallQuality = when (this) {
    CallState.RECONNECTING -> CallQuality.RECONNECTING
    CallState.ACTIVE -> CallQuality.GOOD
    else -> CallQuality.GOOD
}

/**
 * Reconnecting durumunda tam ekranın üstünde gösterilen banner.
 * isVideoCall ise auto-degrade önerisi de gösterir (Madde 10).
 */
@Composable
fun ReconnectingBanner(
    visible: Boolean,
    modifier: Modifier = Modifier,
    isVideoCall: Boolean = false,
    onDisableVideo: (() -> Unit)? = null
) {
    if (!visible) return
    androidx.compose.foundation.layout.Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFFFF5722).copy(alpha = 0.9f))
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CallQualityIndicator(quality = CallQuality.RECONNECTING)
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = "Yeniden bağlanıyor…",
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium
            )
        }
        // Madde 10: Video aramada auto-degrade önerisi
        if (isVideoCall && onDisableVideo != null) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Bağlantı zayıf — tap: video kapat (sesli devam)",
                color = Color.White.copy(alpha = 0.85f),
                fontSize = 12.sp,
                modifier = androidx.compose.ui.Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .padding(top = 4.dp)
                    .background(Color.Black.copy(alpha = 0.2f))
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            )
        }
    }
}
