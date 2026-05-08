package com.securechat.app.util

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

/**
 * Aramalarin guvenilir calismasi icin gereken tum izinleri yoneten yardimci.
 *
 * 4 izin kategorisi:
 *  1. Pil optimizasyonu — Doze'a takilmasin (FCM gerçek zamanli gelsin)
 *  2. Tam ekran bildirim (Android 14+) — kilit ekraninda arama UI'i
 *  3. Bildirim izni (Android 13+) — heads-up arama bildirimi
 *  4. Diger uygulamalar uzerinde goster (overlay) — arka planda Activity acabilmek icin
 */
object CallReadinessHelper {

    enum class PermissionStatus { GRANTED, DENIED, NOT_APPLICABLE }

    data class State(
        val battery: PermissionStatus,
        val fullScreenIntent: PermissionStatus,
        val notification: PermissionStatus,
        val overlay: PermissionStatus
    ) {
        val allGranted: Boolean get() = listOf(battery, fullScreenIntent, notification, overlay)
            .all { it == PermissionStatus.GRANTED || it == PermissionStatus.NOT_APPLICABLE }

        val hasAnyMissing: Boolean get() = !allGranted
    }

    fun currentState(context: Context): State {
        return State(
            battery = if (BatteryOptimizationHelper.isIgnoring(context))
                PermissionStatus.GRANTED else PermissionStatus.DENIED,

            fullScreenIntent = when {
                Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> PermissionStatus.NOT_APPLICABLE
                else -> {
                    val nm = context.getSystemService(NotificationManager::class.java)
                    if (nm?.canUseFullScreenIntent() == true) PermissionStatus.GRANTED
                    else PermissionStatus.DENIED
                }
            },

            notification = when {
                Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> PermissionStatus.NOT_APPLICABLE
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                    == PackageManager.PERMISSION_GRANTED -> PermissionStatus.GRANTED
                else -> PermissionStatus.DENIED
            },

            overlay = if (Settings.canDrawOverlays(context))
                PermissionStatus.GRANTED else PermissionStatus.DENIED
        )
    }

    fun openFullScreenIntentSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
            }
        } catch (_: Exception) { }
    }

    fun openOverlaySettings(context: Context) {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
            }
        } catch (_: Exception) { }
    }

    fun openAppNotificationSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
            }
        } catch (_: Exception) { }
    }

    /** Onboarding bir kez gosterildi mi? */
    private const val PREFS = "call_readiness_prefs"
    private const val KEY_ONBOARDING_SHOWN = "onboarding_shown"

    fun isOnboardingShown(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ONBOARDING_SHOWN, false)

    fun markOnboardingShown(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ONBOARDING_SHOWN, true).apply()
    }

    /** Banner dismiss edildiyse ve son dismiss tarihi 24 saatten yeni ise gostermez. */
    private const val KEY_BANNER_DISMISSED_AT = "banner_dismissed_at"

    fun shouldShowBanner(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // Akilli tespit: son 24 saat icinde 30sn+ gecikmis push var ise
        // banner ZORLA goster (dismiss bayragini bypass et).
        val lastDelayedAt = prefs.getLong("last_delayed_push_at", 0L)
        val recentDelay = System.currentTimeMillis() - lastDelayedAt < 24 * 60 * 60 * 1000L
        if (recentDelay) return true

        // Normal akis: izinler eksik ve son 24 saatte dismiss edilmemis
        val state = currentState(context)
        if (state.allGranted) return false
        val dismissedAt = prefs.getLong(KEY_BANNER_DISMISSED_AT, 0L)
        return System.currentTimeMillis() - dismissedAt > 24 * 60 * 60 * 1000L
    }

    fun dismissBanner(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putLong(KEY_BANNER_DISMISSED_AT, System.currentTimeMillis()).apply()
    }
}
