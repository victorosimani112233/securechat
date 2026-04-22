package com.securechat.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.securechat.app.ui.theme.LocalDarkTheme
import com.securechat.app.ui.theme.glass

/**
 * Glassmorphism dialog -- yari saydam arka plan + border.
 * Tum popup/dialog'lar icin ortak stil.
 *
 * @param onDismissRequest Dialog kapatildiginda cagrilir
 * @param shape Dialog sekli (varsayilan: 20dp radius)
 * @param properties Dialog davranisi (dismissOnBackPress, dismissOnClickOutside vb.)
 * @param content Dialog icerigi
 */
@Composable
fun GlassDialog(
    onDismissRequest: () -> Unit,
    shape: Shape = RoundedCornerShape(20.dp),
    properties: DialogProperties = DialogProperties(),
    content: @Composable ColumnScope.() -> Unit
) {
    val dark = LocalDarkTheme.current
    val baseBg = if (dark) Color(0xFF0D1014).copy(alpha = 0.88f)
                 else Color(0xFFF5F5F5).copy(alpha = 0.92f)
    Dialog(
        onDismissRequest = onDismissRequest,
        properties = properties
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 380.dp)
                .background(baseBg, shape)
                .glass(dark = dark, strong = true, shape = shape)
                .padding(20.dp),
            content = content
        )
    }
}

/**
 * Glassmorphism popup -- kucuk bilgi penceresi.
 * Toast benzeri bildirimler veya tooltip icin kullanilir.
 *
 * @param onDismissRequest Popup kapatildiginda cagrilir
 * @param alignment Popup'in ekrandaki konumu
 * @param shape Popup sekli (varsayilan: 16dp radius)
 * @param content Popup icerigi
 */
@Composable
fun GlassPopup(
    onDismissRequest: () -> Unit,
    alignment: Alignment = Alignment.Center,
    shape: Shape = RoundedCornerShape(16.dp),
    content: @Composable ColumnScope.() -> Unit
) {
    val dark = LocalDarkTheme.current
    Popup(
        alignment = alignment,
        onDismissRequest = onDismissRequest,
        properties = PopupProperties(focusable = true)
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 340.dp)
                .glass(dark = dark, strong = true, shape = shape)
                .padding(16.dp),
            content = content
        )
    }
}

/**
 * Glassmorphism dropdown menu.
 * Material 3 DropdownMenu uzerinde glass efekt uygular.
 * Surface rengi yari saydam yapilarak cam gorunumu saglanir.
 *
 * @param expanded Menu acik mi
 * @param onDismissRequest Menu kapatildiginda cagrilir
 * @param offset Menu konumu icin offset
 * @param content Menu icerigi (DropdownMenuItem'lar)
 */
@Composable
fun GlassDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    offset: DpOffset = DpOffset(0.dp, 0.dp),
    content: @Composable ColumnScope.() -> Unit
) {
    val dark = LocalDarkTheme.current

    MaterialTheme(
        colorScheme = MaterialTheme.colorScheme.copy(
            surface = if (dark) Color(0xFF0D1014).copy(alpha = 0.92f)
                      else Color.White.copy(alpha = 0.92f),
            surfaceContainer = if (dark) Color(0xFF0D1014).copy(alpha = 0.92f)
                               else Color.White.copy(alpha = 0.92f)
        )
    ) {
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = onDismissRequest,
            offset = offset,
            modifier = Modifier
                .border(
                    1.dp,
                    if (dark) Color.White.copy(alpha = 0.12f)
                    else Color(0xFF13161B).copy(alpha = 0.10f),
                    RoundedCornerShape(12.dp)
                ),
            content = content
        )
    }
}
