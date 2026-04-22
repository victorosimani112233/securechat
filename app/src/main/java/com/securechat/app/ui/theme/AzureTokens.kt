package com.securechat.app.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Immutable
data class AzureTokens(
    // Neutral base
    val night: Color = Color(0xFF0D1014),
    val nightRaise: Color = Color(0xFF151A21),
    val nightEdge: Color = Color(0xFF1E242D),
    val paper: Color = Color(0xFFF4F2EC),
    val paperDim: Color = Color(0xFFEAE7DD),

    // Ink (dark text on light)
    val ink: Color = Color(0xFF13161B),
    val inkMute: Color = Color(0xFF5D6570),
    val inkSoft: Color = Color(0xFF8A929C),

    // Frost (light text on dark)
    val frost: Color = Color(0xFFECEEF2),
    val frostMute: Color = Color(0xFF9BA3AE),
    val frostSoft: Color = Color(0xFF6B737D),

    // PRIMARY — yalnız CTA + aktif durumlar
    val azure: Color = Color(0xFF3E7BFA),
    val azureDeep: Color = Color(0xFF1E52D9),
    val azureGlow: Color = Color(0xFF5EA3FF),

    // Status
    val ok: Color = Color(0xFF22C55E),
    val warn: Color = Color(0xFFFFB800),
    val danger: Color = Color(0xFFFF5E87),

    // Spacing (base 4)
    val s1: Dp = 4.dp, val s2: Dp = 8.dp, val s3: Dp = 12.dp,
    val s4: Dp = 16.dp, val s5: Dp = 20.dp, val s6: Dp = 24.dp,

    // Radii
    val rCard: Dp = 16.dp,
    val rPill: Dp = 100.dp,
    val rBubble: Dp = 20.dp,
    val rBubbleTail: Dp = 4.dp,
)

val LocalAzureTokens = staticCompositionLocalOf { AzureTokens() }
val LocalDarkTheme = staticCompositionLocalOf { false }

val androidx.compose.material3.MaterialTheme.azure: AzureTokens
    @Composable @ReadOnlyComposable
    get() = LocalAzureTokens.current
