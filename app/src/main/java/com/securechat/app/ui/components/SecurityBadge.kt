package com.securechat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Güvenlik durumu rozeti.
 * Uçtan uca şifreleme, doğrulanmış kimlik gibi güvenlik özelliklerini gösterir.
 */
@Composable
fun SecurityBadge(
    type: SecurityBadgeType,
    modifier: Modifier = Modifier,
    showText: Boolean = true
) {
    val (icon, text, color) = when (type) {
        SecurityBadgeType.END_TO_END_ENCRYPTED -> Triple(
            Icons.Default.Lock,
            "Şifreli",
            Color(0xFF3E7BFA)
        )
        SecurityBadgeType.IDENTITY_VERIFIED -> Triple(
            Icons.Default.Verified,
            "Doğrulandı",
            Color(0xFF52C41A)
        )
        SecurityBadgeType.SECURE_CONNECTION -> Triple(
            Icons.Default.Security,
            "Güvenli",
            Color(0xFF2979FF)
        )
    }

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        color = color.copy(alpha = 0.12f)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = text,
                modifier = Modifier.size(12.dp),
                tint = color
            )

            if (showText) {
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = text,
                    style = MaterialTheme.typography.labelSmall,
                    color = color,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

enum class SecurityBadgeType {
    END_TO_END_ENCRYPTED,
    IDENTITY_VERIFIED,
    SECURE_CONNECTION
}