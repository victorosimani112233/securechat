package com.securechat.app.ui.screen.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Faz 8: ChatScreen banner composable'lari extract edildi.
 * Pure UI — state'siz, sadece callback alir.
 *
 * - ActiveGroupCallBanner: devam eden grup aramasi (devam eden cagriya katilim)
 * - ExportEnabledBanner: admin export izni acik, yeni katilanlar uyari
 *
 * Refactor sonraki adimlari (SystemMessageBanner, ChatTopBar, MessageList, vb.)
 * ayri sprint'lerde extract edilecek — bu commit foundation.
 */

/**
 * Aktif grup aramasi banner'i — sohbet ekranin ust kisminda.
 * Kullanici sohbeti acinca devam eden grup aramasi varsa gosterilir; tap → katilim.
 */
@Composable
fun ActiveGroupCallBanner(
    callType: String,
    onJoinClick: () -> Unit
) {
    val icon = if (callType == "VIDEO") Icons.Default.Videocam else Icons.Default.Call
    val label = if (callType == "VIDEO") "Görüntülü grup araması devam ediyor"
                else "Sesli grup araması devam ediyor"
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF1F8E3D))
            .clickable { onJoinClick() }
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(
                icon,
                contentDescription = "Aktif grup araması ikonu",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = label,
                color = Color.White,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f)
            )
            Text(
                text = "Katıl",
                color = Color.White,
                fontWeight = FontWeight.SemiBold,
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

/**
 * Sohbet disa aktarma izni acik oldugunda yeni katilanlara veya admin durumu acan
 * uyelere gosterilen one-time bilgi banner'i. Kullanici X ile kapatinca SharedPrefs'e
 * ack yazilir; toggle KAPANIP tekrar acilirsa banner tekrar belirir.
 */
@Composable
fun ExportEnabledBanner(onDismiss: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFFEF6C00))
            .padding(horizontal = 16.dp, vertical = 10.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(
                Icons.Default.Share,
                contentDescription = "Sohbet dışa aktarma açık ikonu",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = "Bu grupta sohbet dışa aktarma açık. Mesajlarınız diğer üyeler tarafından dışarı aktarılabilir.",
                color = Color.White,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.weight(1f)
            )
            Spacer(modifier = Modifier.width(8.dp))
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(28.dp)
            ) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = "Bilgilendirmeyi kapat",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}
