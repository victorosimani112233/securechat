package com.securechat.app.ui.screen.chat.bubble

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.securechat.storage.model.MessageStatus

/**
 * Faz 8: ChatScreen'den extract edildi.
 *
 * Mesaj durum ikonu:
 *   SENDING  → saat (alpha 0.4)
 *   SENT     → tek tik (alpha 0.55)
 *   DELIVERED → cift tik gri (alpha 0.55)
 *   READ     → cift tik mavi (#3E7BFA)
 *   FAILED   → unlem (error color)
 *
 * A11y: contentDescription = status.name (TalkBack icin "READ" vb okur).
 */
@Composable
fun MessageStatusIcon(status: MessageStatus) {
    val (icon, tint) = when (status) {
        MessageStatus.SENDING -> Icons.Default.Schedule to MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.4f)
        MessageStatus.SENT -> Icons.Default.Check to MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.55f)
        MessageStatus.DELIVERED -> Icons.Default.DoneAll to MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.55f)
        MessageStatus.READ -> Icons.Default.DoneAll to Color(0xFF3E7BFA)
        MessageStatus.FAILED -> Icons.Default.Error to MaterialTheme.colorScheme.error
    }
    Icon(
        imageVector = icon,
        contentDescription = "Mesaj durumu: ${status.name}",
        modifier = Modifier
            .padding(start = 2.dp)
            .size(16.dp),
        tint = tint
    )
}
