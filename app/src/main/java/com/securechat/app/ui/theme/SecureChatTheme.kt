package com.securechat.app.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.securechat.app.ui.components.ThemeManager
import com.securechat.app.ui.components.shouldUseDarkTheme

private val tokens = AzureTokens()

private val AzureDarkScheme = darkColorScheme(
    background = tokens.night,
    surface = tokens.nightRaise,
    surfaceVariant = tokens.nightEdge,
    primary = tokens.azure,
    onPrimary = Color.White,
    primaryContainer = tokens.azureDeep,
    onPrimaryContainer = tokens.azureGlow,
    secondary = tokens.azureGlow,
    onSecondary = Color.White,
    secondaryContainer = tokens.nightEdge,
    onSecondaryContainer = tokens.frost,
    onBackground = tokens.frost,
    onSurface = tokens.frost,
    onSurfaceVariant = tokens.frostMute,
    error = tokens.danger,
    onError = Color.White,
    outline = tokens.nightEdge,
    inverseSurface = tokens.paper,
    inverseOnSurface = tokens.ink,
    surfaceTint = tokens.azure,
)

private val AzureLightScheme = lightColorScheme(
    background = tokens.paper,
    surface = Color.White,
    surfaceVariant = tokens.paperDim,
    primary = tokens.azure,
    onPrimary = Color.White,
    primaryContainer = tokens.azureGlow,
    onPrimaryContainer = tokens.azureDeep,
    secondary = tokens.azureDeep,
    onSecondary = Color.White,
    secondaryContainer = tokens.paperDim,
    onSecondaryContainer = tokens.ink,
    onBackground = tokens.ink,
    onSurface = tokens.ink,
    onSurfaceVariant = tokens.inkMute,
    error = tokens.danger,
    onError = Color.White,
    outline = tokens.paperDim,
    inverseSurface = tokens.night,
    inverseOnSurface = tokens.frost,
    surfaceTint = tokens.azure,
)

@Composable
fun SecureChatTheme(
    themeManager: ThemeManager? = null,
    darkTheme: Boolean = themeManager?.shouldUseDarkTheme() ?: isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) AzureDarkScheme else AzureLightScheme
    val useDoodle by (themeManager?.useDoodleBackground
        ?: kotlinx.coroutines.flow.flowOf(true)).collectAsState(initial = true)

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.background.toArgb()
            window.navigationBarColor = colorScheme.background.toArgb()
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = !darkTheme
            controller.isAppearanceLightNavigationBars = !darkTheme
        }
    }

    CompositionLocalProvider(
        LocalAzureTokens provides AzureTokens(),
        LocalDarkTheme provides darkTheme,
        LocalUseDoodleBackground provides useDoodle,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = AzureTypography,
            content = content,
        )
    }
}
