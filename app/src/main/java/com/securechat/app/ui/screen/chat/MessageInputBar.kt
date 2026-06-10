package com.securechat.app.ui.screen.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass

/**
 * Faz 8: ChatScreen'den extract — mesaj giris cubugu.
 *
 * - Atasman ikonu (sol) → onAttachClick
 * - BasicTextField (orta, multi-line max 4) → onTextChange
 * - "1" toggle (saglik kenar) → tek gosterimlik isViewOnce state local
 * - Gonder butonu (sag, azure daire) → onSend(isViewOnce); gonderim sonrasi
 *   isViewOnce otomatik sifirlanir (her view-once kararinin bilincli olmasi).
 *
 * State: sadece isViewOnce yerel; metin caller'da (caller controlled input).
 */
@Composable
fun MessageInputBar(
    text: String,
    onTextChange: (String) -> Unit,
    onSend: (isViewOnce: Boolean) -> Unit,
    onAttachClick: () -> Unit,
    isReadOnlyLocked: Boolean = false
) {
    val dark = LocalDarkTheme.current
    var isViewOnce by remember { mutableStateOf(false) }

    if (isReadOnlyLocked) {
        // Read-only grup ve kullanici admin degil → input gizlenir, bilgilendirme banner gosterilir
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 6.dp)
                .glass(dark = dark, shape = RoundedCornerShape(20.dp))
                .padding(horizontal = 16.dp, vertical = 12.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "Sadece adminler yazabilir",
                style = MaterialTheme.typography.bodyMedium,
                color = if (dark) Color(0xFF9BA3AE) else Color(0xFF5D6570),
                fontWeight = FontWeight.Medium
            )
        }
        return
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .glass(dark = dark, shape = RoundedCornerShape(28.dp))
            .padding(start = 4.dp, end = 6.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        IconButton(
            onClick = onAttachClick,
            modifier = Modifier.size(40.dp)
        ) {
            Icon(
                Icons.Default.AttachFile,
                contentDescription = "Dosya ekle",
                tint = if (dark) Color(0xFF9BA3AE) else Color(0xFF5D6570),
                modifier = Modifier.size(22.dp)
            )
        }

        BasicTextField(
            value = text,
            onValueChange = onTextChange,
            modifier = Modifier.weight(1f).padding(vertical = 10.dp),
            textStyle = MaterialTheme.typography.bodyLarge.copy(
                color = if (dark) Color(0xFFECEEF2) else Color(0xFF13161B)
            ),
            cursorBrush = SolidColor(Color(0xFF3E7BFA)),
            maxLines = 4,
            decorationBox = { innerTextField ->
                if (text.isEmpty()) {
                    Text(
                        "Mesaj yazın...",
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (dark) Color(0xFF6B737D) else Color(0xFF8A929C)
                    )
                }
                innerTextField()
            }
        )

        Spacer(modifier = Modifier.width(6.dp))

        // Tek gosterimlik "1" toggle
        val inactiveBorder = if (dark) Color.White.copy(alpha = 0.25f) else Color(0xFF13161B).copy(alpha = 0.25f)
        val inactiveText = if (dark) Color.White.copy(alpha = 0.7f) else Color(0xFF5D6570)
        val inactiveBg = if (dark) Color.White.copy(alpha = 0.06f) else Color(0xFF13161B).copy(alpha = 0.04f)
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(
                    if (isViewOnce) Color(0xFF3E7BFA).copy(alpha = 0.18f)
                    else inactiveBg
                )
                .border(
                    width = 1.5.dp,
                    color = if (isViewOnce) Color(0xFF3E7BFA) else inactiveBorder,
                    shape = CircleShape
                )
                .clickable { isViewOnce = !isViewOnce },
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "1",
                color = if (isViewOnce) Color(0xFF3E7BFA) else inactiveText,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.width(6.dp))

        // Gonder butonu — azure daire
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(if (text.isNotBlank()) Color(0xFF3E7BFA) else Color(0xFF3E7BFA).copy(alpha = 0.5f))
                .clickable {
                    if (text.isNotBlank()) {
                        val vo = isViewOnce
                        isViewOnce = false  // Bilincli karar — gonderim sonrasi otomatik sifirla
                        onSend(vo)
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.AutoMirrored.Filled.Send,
                contentDescription = "Gönder",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
        }
    }
}
