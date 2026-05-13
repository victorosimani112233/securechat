package com.securechat.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback

/**
 * Haptic feedback yardimcilari.
 *
 * Mevcut sorun: dokunma feedback'i sadece arama ekraninda kullaniliyor.
 * Cogu butonda hic titresim yok — kullanici "premium hissiyat" alamaz.
 *
 * Bu helper Compose tarafindan native, ekstra kutuphane gerektirmez.
 *
 * Kullanim:
 * ```
 * val haptic = rememberHaptic()
 * Button(onClick = { haptic.light(); doSomething() }) { ... }
 * IconButton(onClick = { haptic.longPress(); deleteItem() }) { ... }
 * ```
 */
class HapticController(private val raw: HapticFeedback) {
    /** Hafif dokunma — tipik click, switch toggle. */
    fun light() {
        try {
            raw.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        } catch (_: Exception) {}
    }

    /** Uzun basma / onemli aksiyon — sil, gonder, kabul. */
    fun longPress() {
        try {
            raw.performHapticFeedback(HapticFeedbackType.LongPress)
        } catch (_: Exception) {}
    }
}

/**
 * Composable scope'ta haptic controller — memoize edilmis.
 */
@Composable
fun rememberHaptic(): HapticController {
    val raw = LocalHapticFeedback.current
    return remember(raw) { HapticController(raw) }
}
