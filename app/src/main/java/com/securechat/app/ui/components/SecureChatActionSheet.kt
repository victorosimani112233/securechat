package com.securechat.app.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Material 3 ModalBottomSheet wrapper — diyaloglara modern alternatif.
 *
 * Action list pattern: gondericinin uzerine basildiginda cikan menu, mesaj
 * uzerinde long-press menu, "Avatar degistir" akisi gibi yerlerde kullanilir.
 *
 * Kullanim:
 * ```
 * SecureChatActionSheet(
 *     title = "Mesaj islemleri",
 *     items = listOf(
 *         ActionItem("Yanitla", Icons.AutoMirrored.Filled.Reply) { ... },
 *         ActionItem("Sil", Icons.Default.Delete, danger = true) { ... },
 *     ),
 *     onDismiss = { showSheet = false }
 * )
 * ```
 *
 * NOT: Dialog yerine bottom sheet kullanim avantajlari:
 *   - Tek elle erisilebilir (alt yari ekran)
 *   - Material 3'un onerdigi modern UX pattern
 *   - Sistem geri tusu/swipe ile kapanir, manuel dismissButton gerekmez
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecureChatActionSheet(
    title: String,
    items: List<ActionItem>,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp)
            )
            items.forEach { item ->
                ActionRow(item, onClick = {
                    item.onClick()
                    onDismiss()
                })
            }
        }
    }
}

@Composable
private fun ActionRow(item: ActionItem, onClick: () -> Unit) {
    val tint = if (item.danger) MaterialTheme.colorScheme.error
    else MaterialTheme.colorScheme.onSurface

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Icon(
            imageVector = item.icon,
            contentDescription = null, // ActionRow'un kendisi tiklanabilir → text okunur
            modifier = Modifier.size(24.dp),
            tint = if (item.iconTint != Color.Unspecified) item.iconTint else tint
        )
        Text(
            text = item.label,
            style = MaterialTheme.typography.bodyLarge,
            color = tint,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

data class ActionItem(
    val label: String,
    val icon: ImageVector,
    /** danger = true → tehlikeli aksiyon (silme), kirmizi renk tonu. */
    val danger: Boolean = false,
    /** Ozel tint istenirse — yoksa danger'a gore otomatik. */
    val iconTint: Color = Color.Unspecified,
    val onClick: () -> Unit
)
