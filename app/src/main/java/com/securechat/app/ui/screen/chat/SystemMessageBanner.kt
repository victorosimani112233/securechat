package com.securechat.app.ui.screen.chat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass
import com.securechat.storage.domain.LocalMessage

/**
 * Faz 8: ChatScreen'den extract — sistem mesaji banner'i.
 *
 * Grup olaylari ("X gruba katildi", admin atamalari, vb.) ve arama olaylari
 * (CALL|... formati) icin ortalanmis kucuk pill-style banner.
 *
 * CALL formati: "CALL|direction|callType|status|duration|displayText"
 *   - status MISSED/REJECTED/FAILED/BUSY ise + direction GROUP_* degil ise
 *     "geri ara" tiklamasi etkin (callback dispatch)
 *
 * Diger SYSTEM mesajlar: sade Info ikonu + metin.
 */
@Composable
fun SystemMessageBanner(
    message: LocalMessage,
    onCallBack: ((callType: String) -> Unit)? = null
) {
    val dark = LocalDarkTheme.current
    val content = message.content
    val isCallMessage = content.startsWith("CALL|")

    val displayText: String
    val icon: androidx.compose.ui.graphics.vector.ImageVector
    val iconTint: Color
    var callType = ""
    var isCallbackable = false

    if (isCallMessage) {
        val parts = content.split("|", limit = 6)
        callType = parts.getOrNull(2) ?: ""
        val direction = parts.getOrNull(1) ?: ""
        val status = parts.getOrNull(3) ?: ""
        displayText = parts.getOrNull(5) ?: content
        // GROUP_STARTED/GROUP_ENDED'de geri arama yok
        isCallbackable = status in listOf("MISSED", "REJECTED", "FAILED", "BUSY") &&
                         direction != "GROUP_STARTED" && direction != "GROUP_ENDED"

        icon = if (callType == "VIDEO") Icons.Default.Videocam else Icons.Default.Call
        iconTint = when {
            direction == "GROUP_STARTED" -> Color(0xFF4CAF50)
            direction == "GROUP_ENDED" -> MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
            status in listOf("MISSED", "REJECTED", "FAILED", "BUSY") -> MaterialTheme.colorScheme.error
            direction == "OUTGOING" -> MaterialTheme.colorScheme.primary
            else -> Color(0xFF4CAF50)
        }
    } else {
        displayText = content
        icon = Icons.Default.Info
        iconTint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .glass(dark = dark, shape = RoundedCornerShape(100.dp))
                .then(
                    if (isCallbackable && onCallBack != null) {
                        Modifier.clickable { onCallBack(callType) }
                    } else Modifier
                )
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = iconTint
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = displayText,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (isCallbackable)
                        MaterialTheme.colorScheme.error
                    else if (dark) Color(0xFFECEEF2) else Color(0xFF13161B),
                    fontSize = 12.sp
                )
                if (isCallbackable) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Icon(
                        Icons.Default.Call,
                        contentDescription = "Geri Ara",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }
    }
}
