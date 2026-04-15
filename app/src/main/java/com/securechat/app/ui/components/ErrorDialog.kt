package com.securechat.app.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Standart hata diyalogu.
 * Consistent UX için tüm error handling'de kullanılır.
 */
@Composable
fun ErrorDialog(
    title: String = "Hata",
    message: String,
    icon: ImageVector = Icons.Default.Error,
    onDismiss: () -> Unit,
    confirmButtonText: String = "Tamam",
    onConfirm: (() -> Unit)? = null
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        icon = {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error
            )
        },
        confirmButton = {
            TextButton(
                onClick = onConfirm ?: onDismiss
            ) {
                Text(confirmButtonText)
            }
        }
    )
}

/**
 * Warning diyalogu variant'ı.
 */
@Composable
fun WarningDialog(
    title: String = "Uyarı",
    message: String,
    onDismiss: () -> Unit,
    onConfirm: (() -> Unit)? = null,
    confirmButtonText: String = "Tamam",
    dismissButtonText: String = "İptal"
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        icon = {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.secondary
            )
        },
        confirmButton = {
            TextButton(
                onClick = onConfirm ?: onDismiss
            ) {
                Text(confirmButtonText)
            }
        },
        dismissButton = if (onConfirm != null) {
            {
                TextButton(onClick = onDismiss) {
                    Text(dismissButtonText)
                }
            }
        } else null
    )
}