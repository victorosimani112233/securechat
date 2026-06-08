package com.securechat.app.ui.theme

import androidx.activity.ComponentActivity
import androidx.compose.material3.windowsizeclass.WindowSizeClass
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalContext

/**
 * Tablet/foldable destegi — WindowSizeClass uzerinden 3 kademe:
 *
 *   Compact  → telefon dikey (mevcut UI, tek pane)
 *   Medium   → foldable yari acik / kucuk tablet (mevcut + genis padding)
 *   Expanded → tablet 10"+ (2-pane: sol konusma listesi, sag chat)
 *
 * Activity'de:
 *   val windowSizeClass = calculateWindowSizeClass(this)
 *   CompositionLocalProvider(LocalWindowSizeClass provides windowSizeClass) { ... }
 *
 * Ekranlarda:
 *   val sc = LocalWindowSizeClass.current
 *   when (sc.widthSizeClass) {
 *     WindowWidthSizeClass.Compact -> SinglePane()
 *     WindowWidthSizeClass.Medium -> SinglePane(extraPadding = true)
 *     WindowWidthSizeClass.Expanded -> TwoPane()
 *   }
 *
 * Bu commit foundation — ekran-ekran 2-pane migration'i ChatScreen refactor
 * (Faz 8) ile birlikte yapilacak. Su an sadece infrastructure.
 */
val LocalWindowSizeClass = staticCompositionLocalOf<WindowSizeClass> {
    error("LocalWindowSizeClass provider yok — Activity'de calculateWindowSizeClass + CompositionLocalProvider gerekir")
}

/**
 * Convenience flags — common patterns icin.
 */
@Composable
fun isCompactWidth(): Boolean =
    LocalWindowSizeClass.current.widthSizeClass == WindowWidthSizeClass.Compact

@Composable
fun isExpandedWidth(): Boolean =
    LocalWindowSizeClass.current.widthSizeClass == WindowWidthSizeClass.Expanded

@Composable
fun shouldUseTwoPaneLayout(): Boolean = isExpandedWidth()
