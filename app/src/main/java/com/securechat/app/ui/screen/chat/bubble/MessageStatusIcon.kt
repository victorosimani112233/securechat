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
import androidx.compose.ui.unit.dp
import com.securechat.app.ui.theme.azure
import com.securechat.storage.model.MessageStatus

/**
 * Faz 8: ChatScreen'den extract edildi.
 *
 * Mesaj durum ikonu — yalnizca giden (outgoing) bubble'da gosterilir.
 * Bubble arka plani azureDeep/azureGlow (mavi) oldugundan tick rengi mavi olursa
 * karisir; bu yuzden frost (beyaz) ve ok (yesil) token'larini kullaniyoruz:
 *
 *   SENDING   → saat, frost @ 60%      (beyazimsi soluk, "gonderiliyor" hissi)
 *   SENT      → tek tik, frost @ 90%   (parlak beyaz, mavi uzerinde net)
 *   DELIVERED → cift tik, frost @ 90%  (sekil farki ile SENT'ten ayrilir)
 *   READ      → cift tik, ok (yesil)   (renk farki ile DELIVERED'dan ayrilir,
 *                                       mavi bubble uzerinde guclu kontrast)
 *   FAILED    → unlem, error color
 *
 * 17dp boyut — onceden 16dp, mavi uzerinde okunaksizdi.
 * A11y: contentDescription = status.name (TalkBack icin "READ" vb okur).
 */
@Composable
fun MessageStatusIcon(status: MessageStatus) {
    val az = MaterialTheme.azure
    val (icon, tint) = when (status) {
        MessageStatus.SENDING -> Icons.Default.Schedule to az.frost.copy(alpha = 0.60f)
        MessageStatus.SENT -> Icons.Default.Check to az.frost.copy(alpha = 0.90f)
        MessageStatus.DELIVERED -> Icons.Default.DoneAll to az.frost.copy(alpha = 0.90f)
        MessageStatus.READ -> Icons.Default.DoneAll to az.ok
        MessageStatus.FAILED -> Icons.Default.Error to MaterialTheme.colorScheme.error
    }
    Icon(
        imageVector = icon,
        contentDescription = "Mesaj durumu: ${status.name}",
        modifier = Modifier
            .padding(start = 2.dp)
            .size(17.dp),
        tint = tint
    )
}
