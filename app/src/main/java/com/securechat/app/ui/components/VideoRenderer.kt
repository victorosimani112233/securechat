package com.securechat.app.ui.components

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp

/**
 * Video frame renderer composable.
 * WebRTC video stream'lerini Bitmap olarak alır ve gösterir.
 */
@Composable
fun VideoRenderer(
    videoBitmap: Bitmap?,
    isLocalVideo: Boolean = false,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(if (isLocalVideo) RoundedCornerShape(12.dp) else RoundedCornerShape(0.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center
    ) {
        if (videoBitmap != null) {
            Image(
                bitmap = videoBitmap.asImageBitmap(),
                contentDescription = if (isLocalVideo) "Yerel video" else "Uzak video",
                modifier = Modifier.fillMaxSize(),
                contentScale = if (isLocalVideo) ContentScale.Crop else ContentScale.Fit
            )
        } else {
            // Video yok placeholder
            Icon(
                imageVector = Icons.Default.VideocamOff,
                contentDescription = "Video kapalı",
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
            )
        }
    }
}