package com.securechat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Ortak avatar component.
 * Grup: grup ikonu, Kisi: insan silueti (WhatsApp tarzi).
 * Tum ekranlarda bu component kullanilmali.
 */
@Composable
fun GeneratedAvatar(
    name: String,
    isGroup: Boolean = false,
    size: Dp = 48.dp,
    modifier: Modifier = Modifier
) {
    val avatarColor = generateAvatarColor(name)

    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(avatarColor),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = if (isGroup) Icons.Default.Group else Icons.Default.Person,
            contentDescription = if (isGroup) "Grup" else "Kisi",
            tint = Color.White.copy(alpha = 0.9f),
            modifier = Modifier.size(size * 0.55f)
        )
    }
}

/**
 * Isim bazinda tutarli avatar rengi uretir -- Azure paleti.
 */
fun generateAvatarColor(name: String): Color {
    val colors = listOf(
        Color(0xFF3E7BFA), // azure
        Color(0xFF6B737D), // slate
        Color(0xFF8A929C), // silver
        Color(0xFF5D6570), // graphite
        Color(0xFF4A535E), // charcoal
        Color(0xFF9BA3AE), // mist
        Color(0xFF7B8491), // pebble
        Color(0xFF556070), // steel
    )

    var h = 0
    for (c in name) h = (h * 31 + c.code) and 0x7FFFFFFF
    return colors[h % colors.size]
}
