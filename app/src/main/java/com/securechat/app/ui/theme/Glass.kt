package com.securechat.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

/**
 * Azure glassmorphism modifier.
 * Yarim saydam arka plan + ince border ile buzlu cam efekti.
 *
 * Not: Jetpack Compose'da gercek backdrop blur destegi bulunmadigi icin
 * daha yuksek alpha degerleri kullanilarak buzlu cam gorunumu saglanir.
 * Bu yaklasim performans dostu olup tum API seviyelerinde tutarli calisir.
 *
 * @param dark Koyu tema aktif mi
 * @param strong Daha opak / belirgin cam efekti (dialog, popup icin)
 * @param shape Uygulanacak sekil (varsayilan: 16dp radius)
 */
fun Modifier.glass(
    dark: Boolean,
    strong: Boolean = false,
    shape: Shape = RoundedCornerShape(16.dp),
): Modifier = composed {
    val bg = if (dark) Color.White.copy(alpha = if (strong) 0.14f else 0.07f)
             else Color.White.copy(alpha = if (strong) 0.85f else 0.62f)
    val borderColor = if (dark) Color.White.copy(alpha = if (strong) 0.20f else 0.12f)
                      else Color(0xFF13161B).copy(alpha = if (strong) 0.10f else 0.04f)

    this
        .clip(shape)
        .background(bg, shape)
        .border(1.dp, borderColor, shape)
}
