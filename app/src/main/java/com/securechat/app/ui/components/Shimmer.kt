package com.securechat.app.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import com.securechat.app.ui.theme.LocalDarkTheme

/**
 * Shimmer placeholder — yukleme suresinde "akan gradient" efekti.
 *
 * Compose tarafindan native, accompanist gerektirmez. `infiniteTransition` ile
 * gradient offset'i animate eder, 1.2sn'de bir akar.
 *
 * Kullanim:
 * ```
 * ShimmerBox(modifier = Modifier.height(20.dp).width(120.dp))
 * ShimmerBox(modifier = Modifier.size(48.dp), shape = CircleShape)
 * ```
 */
@Composable
fun ShimmerBox(
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(6.dp)
) {
    val dark = LocalDarkTheme.current
    val baseColor = if (dark) Color(0xFF2A2D33) else Color(0xFFE8EAEE)
    val highlightColor = if (dark) Color(0xFF3A3D43) else Color(0xFFF5F6F8)

    val transition = rememberInfiniteTransition(label = "shimmer")
    val offset by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "shimmerOffset"
    )

    val brush = Brush.linearGradient(
        colors = listOf(baseColor, highlightColor, baseColor),
        start = Offset(offset * 600f - 300f, 0f),
        end = Offset(offset * 600f, 0f)
    )

    Box(
        modifier = modifier
            .clip(shape)
            .background(brush)
    )
}

/**
 * Konusma listesi icin shimmer item — Conversations ekrani initial loading.
 *
 * Avatar (48dp circle) + 2 satir (isim + son mesaj) + timestamp.
 */
@Composable
fun ConversationShimmerItem(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ShimmerBox(
            modifier = Modifier.size(48.dp),
            shape = CircleShape
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            ShimmerBox(
                modifier = Modifier
                    .height(14.dp)
                    .fillMaxWidth(fraction = 0.55f)
            )
            Spacer(modifier = Modifier.height(8.dp))
            ShimmerBox(
                modifier = Modifier
                    .height(12.dp)
                    .fillMaxWidth(fraction = 0.8f)
            )
        }
        Spacer(modifier = Modifier.width(8.dp))
        ShimmerBox(
            modifier = Modifier
                .height(10.dp)
                .width(40.dp)
        )
    }
}

/**
 * Mesaj listesi icin shimmer item — Chat ekrani initial loading.
 *
 * Iki yonlu (gelen + giden) baloncuk simulasyonu.
 */
@Composable
fun MessageShimmerItem(
    modifier: Modifier = Modifier,
    isOutgoing: Boolean = false
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = if (isOutgoing) Arrangement.End else Arrangement.Start
    ) {
        ShimmerBox(
            modifier = Modifier
                .height(38.dp)
                .fillMaxWidth(fraction = 0.45f + (if (isOutgoing) 0.1f else 0f)),
            shape = RoundedCornerShape(16.dp)
        )
    }
}

/**
 * Kisi listesi icin shimmer item — Contacts ekrani initial loading.
 *
 * Avatar + tek satir isim.
 */
@Composable
fun ContactShimmerItem(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ShimmerBox(
            modifier = Modifier.size(44.dp),
            shape = CircleShape
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            ShimmerBox(
                modifier = Modifier
                    .height(14.dp)
                    .fillMaxWidth(fraction = 0.5f)
            )
            Spacer(modifier = Modifier.height(6.dp))
            ShimmerBox(
                modifier = Modifier
                    .height(11.dp)
                    .fillMaxWidth(fraction = 0.35f)
            )
        }
    }
}

