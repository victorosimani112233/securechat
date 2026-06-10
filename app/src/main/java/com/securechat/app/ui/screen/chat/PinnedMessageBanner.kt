package com.securechat.app.ui.screen.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.storage.domain.LocalMessage

/**
 * Chat header altinda gosterilen sabitlenmis mesaj banner'i.
 *
 * - Sol: pin ikonu (azure)
 * - Orta: "Sabitlenmiş Mesaj" ust, mesaj preview alt (tek satir, ellipsis)
 * - Sag: pin kaldir butonu (admin'e gosterilir, 1:1'de her iki taraf)
 *
 * Banner tiklaninca onClick — sabitlenmis mesaja scroll ederiz (caller listState).
 */
@Composable
fun PinnedMessageBanner(
    message: LocalMessage,
    canUnpin: Boolean,
    onClick: () -> Unit,
    onUnpin: () -> Unit,
    modifier: Modifier = Modifier
) {
    val dark = LocalDarkTheme.current
    val accent = Color(0xFF3E7BFA)
    val bg = if (dark) Color(0xFF1A1F26).copy(alpha = 0.96f) else Color(0xFFF1F4F9)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Default.PushPin,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(18.dp)
            )
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 10.dp, end = 8.dp)
            ) {
                Text(
                    text = "Sabitlenmiş Mesaj",
                    style = MaterialTheme.typography.labelMedium,
                    color = accent
                )
                Text(
                    text = message.previewText,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (dark) Color(0xFFC8CDD4) else Color(0xFF3A4250),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            if (canUnpin) {
                IconButton(
                    onClick = onUnpin,
                    modifier = Modifier.size(28.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Sabit kaldir",
                        tint = if (dark) Color(0xFF8A929C) else Color(0xFF5D6570),
                        modifier = Modifier.size(18.dp)
                    )
                }
            }
        }
    }
}
