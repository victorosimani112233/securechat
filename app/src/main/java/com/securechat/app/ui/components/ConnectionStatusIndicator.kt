package com.securechat.app.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.dp
import com.securechat.network.model.ConnectionState

/**
 * Bağlantı durumu göstergesi - küçük renkli nokta.
 * Toolbar'da veya conversation item'larda kullanılır.
 */
@Composable
fun ConnectionStatusIndicator(
    connectionState: ConnectionState,
    modifier: Modifier = Modifier
) {
    val targetColor = when (connectionState) {
        is ConnectionState.Connected -> Color(0xFF22C55E) // Yeşil - çevrimiçi
        is ConnectionState.Connecting -> Color(0xFFFFA726) // Amber - bağlanıyor
        is ConnectionState.Disconnected -> Color(0xFF6C757D) // Gray - çevrimdışı
        is ConnectionState.Error -> MaterialTheme.colorScheme.error // Red - hata
    }

    val animatedColor by animateColorAsState(
        targetValue = targetColor,
        animationSpec = tween(300),
        label = "connectionColor"
    )

    val animatedAlpha by animateFloatAsState(
        targetValue = if (connectionState is ConnectionState.Connecting) 0.5f else 1f,
        animationSpec = tween(1000),
        label = "connectionAlpha"
    )

    Box(
        modifier = modifier
            .size(8.dp)
            .clip(CircleShape)
    ) {
        Canvas(
            modifier = Modifier.size(8.dp)
        ) {
            drawConnectionDot(animatedColor.copy(alpha = animatedAlpha))
        }
    }
}

private fun DrawScope.drawConnectionDot(color: Color) {
    drawCircle(
        color = color,
        radius = size.minDimension / 2
    )
}