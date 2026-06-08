package com.securechat.app.ui.screen.chat

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import coil.request.ImageRequest

/**
 * Faz 8: ChatScreen'den extract edilen tek-gosterimlik viewer'lar.
 *
 * Activity FLAG_SECURE aktif oldugu icin ekran goruntusu sistem tarafindan
 * engellenir. Dismiss callback caller'da markViewOnceAsViewed cagrir.
 *
 * Iki varyant:
 *   - ViewOnceImageViewer: AsyncImage ile dosyadan resim
 *   - ViewOnceTextViewer: secilemez metin (SelectionContainer yok)
 */

@Composable
fun ViewOnceImageViewer(
    filePath: String,
    onDismiss: () -> Unit
) {
    val ctx = LocalContext.current
    BackHandler(onBack = onDismiss)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) { detectTapGestures(onTap = { onDismiss() }) }
    ) {
        AsyncImage(
            model = ImageRequest.Builder(ctx)
                .data(java.io.File(filePath))
                .crossfade(true)
                .build(),
            contentDescription = "Tek gösterimlik fotoğraf",
            modifier = Modifier.fillMaxSize().padding(16.dp),
            contentScale = ContentScale.Fit
        )
        TopChromeBar(onDismiss = onDismiss)
    }
}

@Composable
fun ViewOnceTextViewer(
    content: String,
    onDismiss: () -> Unit
) {
    BackHandler(onBack = onDismiss)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) { detectTapGestures(onTap = { onDismiss() }) }
    ) {
        TopChromeBar(onDismiss = onDismiss)
        Text(
            text = content,
            color = Color.White,
            style = MaterialTheme.typography.headlineSmall,
            lineHeight = 32.sp,
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = 32.dp, vertical = 80.dp)
        )
        Text(
            text = "Kapatmak için dokunun · bir daha açılamaz",
            color = Color.White.copy(alpha = 0.55f),
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 24.dp)
        )
    }
}

/** Ust bilgi cubugu — "tek gosterimlik" + kapat ikonu (her iki viewer ortak). */
@Composable
private fun androidx.compose.foundation.layout.BoxScope.TopChromeBar(onDismiss: () -> Unit) {
    Row(
        modifier = Modifier
            .align(Alignment.TopCenter)
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Default.Lock,
            contentDescription = "Tek gösterimlik içerik kilidi",
            tint = Color.White.copy(alpha = 0.85f),
            modifier = Modifier.size(18.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "Tek gösterimlik · ekran görüntüsü engellendi",
            color = Color.White.copy(alpha = 0.85f),
            style = MaterialTheme.typography.bodyMedium
        )
        Spacer(modifier = Modifier.weight(1f))
        IconButton(onClick = onDismiss) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = "Kapat",
                tint = Color.White
            )
        }
    }
}
