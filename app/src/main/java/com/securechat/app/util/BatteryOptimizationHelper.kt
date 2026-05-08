package com.securechat.app.util

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings

/**
 * Pil optimizasyonu (Doze Mode) yardimcisi.
 *
 * FCM data-only push'lar ve arama sinyalleri Doze'da gecikir veya hic ulasmaz.
 * SecureChat icin kullanici muafiyet vermeli — yoksa aramalar geç gelir.
 *
 * Bu helper:
 *  - Mevcut izin durumunu kontrol eder
 *  - Sistem dialog'unu (tek tap) acar — kullanici manuel ayara gitmeden onaylar
 *  - "Tekrar sorma" yerine "izin alınana kadar her zaman sor" mantigi
 */
object BatteryOptimizationHelper {

    /** Pil optimizasyonu KAPALI mi (yani SecureChat muaf mi)? */
    fun isIgnoring(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Pil optimizasyonu kaldirma dialog'unu acar.
     * Bu sistem dialog'udur — kullanici tek tap ile [İzin Ver]/[İptal] secebilir.
     * Settings'e gitmek gerekmez.
     *
     * @return true = dialog acildi, false = sistem destekleyemiyor (Oppo/Xiaomi'da bazen)
     */
    fun requestExemption(context: Context): Boolean {
        return try {
            if (isIgnoring(context)) return true // zaten muaf
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent)
                true
            } else {
                // OEM destekleemiyor — fallback: genel pil ayarlari
                openBatterySettings(context)
            }
        } catch (e: Exception) {
            openBatterySettings(context)
        }
    }

    /** Genel pil ayarlari ekrani — fallback. */
    private fun openBatterySettings(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (intent.resolveActivity(context.packageManager) != null) {
                context.startActivity(intent); true
            } else false
        } catch (_: Exception) { false }
    }

    /**
     * "Tekrar gosterilmesin" tercih kontrolu.
     * Kullanici dialog'u "İptal" ettiginde bu flag YALNIZCA Settings'te
     * "bana tekrar sorma" derse set edilir — varsayilan olarak her acilista sorulabilir.
     */
    private const val PREFS_NAME = "battery_optimization_prefs"
    private const val KEY_DONT_ASK_AGAIN = "dont_ask_again"

    fun shouldPromptOnLaunch(context: Context): Boolean {
        if (isIgnoring(context)) return false // zaten muaf — sorma
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return !prefs.getBoolean(KEY_DONT_ASK_AGAIN, false)
    }

    fun setDontAskAgain(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_DONT_ASK_AGAIN, value).apply()
    }
}
