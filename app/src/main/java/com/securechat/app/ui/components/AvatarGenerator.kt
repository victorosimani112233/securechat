package com.securechat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs

/**
 * İsim bazlı avatar generator.
 * Grup için grup ikonu, kişiler için isim harfi gösterir.
 * Tutarlı renk paleti kullanır.
 */
@Composable
fun GeneratedAvatar(
    name: String,
    isGroup: Boolean = false,
    size: Dp = 48.dp,
    modifier: Modifier = Modifier
) {
    val gradient = generateAvatarGradient(name)

    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(gradient),
        contentAlignment = Alignment.Center
    ) {
        if (isGroup) {
            Icon(
                imageVector = Icons.Default.Group,
                contentDescription = "Grup",
                tint = Color.White,
                modifier = Modifier.size(size * 0.5f)
            )
        } else {
            val initial = name.firstOrNull()?.uppercase() ?: "?"
            Text(
                text = initial,
                style = MaterialTheme.typography.titleMedium,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = (size.value * 0.4f).sp
            )
        }
    }
}

/**
 * İsim bazında tutarlı gradient renk üretir.
 */
private fun generateAvatarGradient(name: String): Brush {
    val colorPairs = listOf(
        Color(0xFF00897B) to Color(0xFF004D40), // Teal
        Color(0xFF00ACC1) to Color(0xFF006064), // Cyan
        Color(0xFF5C6BC0) to Color(0xFF283593), // Indigo
        Color(0xFF7E57C2) to Color(0xFF4527A0), // Deep Purple
        Color(0xFFEF5350) to Color(0xFFB71C1C), // Red
        Color(0xFFFF7043) to Color(0xFFBF360C), // Deep Orange
        Color(0xFF26A69A) to Color(0xFF00695C), // Teal Accent
        Color(0xFF42A5F5) to Color(0xFF1565C0), // Blue
        Color(0xFFEC407A) to Color(0xFF880E4F), // Pink
        Color(0xFF66BB6A) to Color(0xFF2E7D32)  // Green
    )

    val index = abs(name.hashCode()) % colorPairs.size
    val (startColor, endColor) = colorPairs[index]

    return Brush.radialGradient(
        colors = listOf(startColor, endColor)
    )
}