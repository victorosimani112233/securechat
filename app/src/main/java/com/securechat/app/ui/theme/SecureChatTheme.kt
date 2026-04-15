package com.securechat.app.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.hilt.navigation.compose.hiltViewModel
import com.securechat.app.ui.components.ThemeManager
import com.securechat.app.ui.components.shouldUseDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

/**
 * SecureChat "Midnight Teal" koyu tema renk paleti.
 * Derin lacivert/koyu gri arka planlar, canli cyan-teal vurgular ve ince gradyanlar.
 * Signal + Telegram X ilham kaynagi.
 */
private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF2979FF),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF0D3B82),
    onPrimaryContainer = Color(0xFFB3D4FF),
    secondary = Color(0xFF448AFF),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFF142D5E),
    onSecondaryContainer = Color(0xFFB3D4FF),
    tertiary = Color(0xFF536DFE),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFF1A237E),
    onTertiaryContainer = Color(0xFFC5CAE9),
    surface = Color(0xFF121820),
    onSurface = Color(0xFFE6EDF3),
    background = Color(0xFF0A0F18),
    onBackground = Color(0xFFE6EDF3),
    surfaceVariant = Color(0xFF1A2233),
    onSurfaceVariant = Color(0xFF8899AA),
    error = Color(0xFFF85149),
    onError = Color.White,
    errorContainer = Color(0xFF3D1518),
    onErrorContainer = Color(0xFFFFA4A0),
    outline = Color(0xFF253040),
    inverseSurface = Color(0xFFE6EDF3),
    inverseOnSurface = Color(0xFF121820),
    surfaceTint = Color(0xFF2979FF)
)

/**
 * SecureChat acik tema renk paleti.
 * Koyu tema ile tutarli, yumusak ama canlı tonlar.
 */
private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF00838F),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFB2EBF2),
    onPrimaryContainer = Color(0xFF00363D),
    secondary = Color(0xFF3DBDAD),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFB2DFDB),
    onSecondaryContainer = Color(0xFF00363D),
    tertiary = Color(0xFF651FFF),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFD1C4E9),
    onTertiaryContainer = Color(0xFF1A0052),
    surface = Color(0xFFF6F8FA),
    onSurface = Color(0xFF1B1F23),
    background = Color(0xFFEEF1F5),
    onBackground = Color(0xFF1B1F23),
    surfaceVariant = Color(0xFFE2E6EB),
    onSurfaceVariant = Color(0xFF57606A),
    error = Color(0xFFCF222E),
    onError = Color.White,
    errorContainer = Color(0xFFFFD7D5),
    onErrorContainer = Color(0xFF5A0000),
    outline = Color(0xFFD0D7DE),
    inverseSurface = Color(0xFF1B1F23),
    inverseOnSurface = Color(0xFFF6F8FA),
    surfaceTint = Color(0xFF00838F)
)

/**
 * SecureChat ozel Shapes.
 * Yuvarlatilmis koseler ile modern gorunum saglar.
 */
private val SecureChatShapes = Shapes(
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(24.dp)
)

/**
 * SecureChat ozel tipografi.
 * Daha okunan ve modern bir metin hiyerarsisi saglar.
 */
private val SecureChatTypography = Typography(
    headlineLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        lineHeight = 36.sp,
        letterSpacing = 0.sp
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 24.sp,
        lineHeight = 32.sp,
        letterSpacing = 0.sp
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Bold,
        fontSize = 20.sp,
        lineHeight = 28.sp,
        letterSpacing = 0.sp
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.15.sp
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.25.sp
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.4.sp
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.1.sp
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 0.5.sp
    )
)

/**
 * SecureChat ana tema composable'i.
 * Sistem temasına uyum sağlayabilir veya kullanıcı tercihine göre çalışır.
 * Status bar rengi arka plan rengine ayarlanir.
 */
@Composable
fun SecureChatTheme(
    themeManager: ThemeManager? = null,
    darkTheme: Boolean = themeManager?.shouldUseDarkTheme() ?: isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            // Status bar arka plan rengine uyumlu — koyu temada derin lacivert
            window.statusBarColor = colorScheme.background.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = SecureChatTypography,
        shapes = SecureChatShapes,
        content = content
    )
}
