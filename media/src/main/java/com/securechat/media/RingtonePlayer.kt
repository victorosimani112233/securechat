package com.securechat.media

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Gelen arama sirasinda zil sesi ve titresim yoneten sinif.
 *
 * Sorumluluklari:
 * - Varsayilan zil sesini calmak (RingtoneManager.TYPE_RINGTONE)
 * - Tekrarli titresim deseni olusturmak
 * - Arama kabul edildiginde veya reddedildiginde durdurmak
 * - Arama baglantiginda kisa "connected" sinyali calmak (ToneGenerator)
 */
@Singleton
class RingtonePlayer @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var ringbackTone: ToneGenerator? = null
    private var ringbackHandler: android.os.Handler? = null
    private var ringbackRunnable: Runnable? = null

    /**
     * Zil sesi ve titresimi baslatir.
     * Gelen arama alglandiginda cagirilir.
     *
     * Zil sesi: Cihazin varsayilan zil sesi (TYPE_RINGTONE)
     * Titresim deseni: 0ms bekle, 1000ms titre, 1000ms bekle (tekrarli)
     */
    @Synchronized
    fun startRinging() {
        // Idempotent: zaten caliyorsa duplicate'i engelle (double-ring fix)
        if (ringtone?.isPlaying == true) {
            android.util.Log.d("RingtonePlayer", "Zaten caliyor — startRinging IGNORE")
            return
        }
        // Zil sesini cal
        try {
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(context, ringtoneUri)
            ringtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            ringtone?.play()
        } catch (e: Exception) {
            android.util.Log.e("RingtonePlayer", "Zil sesi calinamadi", e)
        }

        // Titresimi baslat
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            val pattern = longArrayOf(0, 1000, 1000) // bekle, titre, duraklat — tekrarli
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } catch (e: Exception) {
            android.util.Log.e("RingtonePlayer", "Titresim baslatilmadi", e)
        }
    }

    /**
     * Zil sesi ve titresimi durdurur.
     * Arama kabul edildiginde, reddedildiginde veya sonlandirildiginda cagirilir.
     * Birden fazla kez cagrilmasi guvenlidir (idempotent).
     */
    @Synchronized
    fun stopRinging() {
        ringtone?.stop()
        ringtone = null
        vibrator?.cancel()
        vibrator = null
    }

    /**
     * Arama baglantiginda kisa bir sinyal sesi calar.
     * ToneGenerator ile 200ms sureli TONE_PROP_PROMPT tonu olusturur.
     * Kullaniciya aramanin basariyla baglandigini bildirir.
     */
    /**
     * Arayan taraf icin ringback tonu baslatir (tuut... tuut... sesi).
     * Karsi taraf cevaplayana kadar calismaya devam eder.
     */
    fun startRingbackTone() {
        try {
            // Onceki ringback tonunu temizle
            stopRingbackTone()

            // STREAM_MUSIC kullanarak daha guvenli ToneGenerator olustur
            ringbackTone = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
            ringbackHandler = android.os.Handler(android.os.Looper.getMainLooper())

            ringbackRunnable = object : Runnable {
                override fun run() {
                    try {
                        // ToneGenerator'un hazir oldugundan emin ol
                        ringbackTone?.let { toneGen ->
                            toneGen.startTone(ToneGenerator.TONE_SUP_RINGTONE, 1000)
                            // Bir sonraki tonu planla
                            ringbackHandler?.postDelayed(this, 3000) // 1sn ton + 2sn sessizlik
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("RingtonePlayer", "Ringback tone calma hatasi", e)
                    }
                }
            }

            // ToneGenerator'in initialize olmasini beklemek icin kisa gecikme
            ringbackHandler?.postDelayed(ringbackRunnable!!, 100)
            android.util.Log.d("RingtonePlayer", "Ringback tone baslatildi")
        } catch (e: Exception) {
            android.util.Log.e("RingtonePlayer", "Ringback tone baslatilmadi", e)
            // Fallback: sessiz calismaya devam et
        }
    }

    /**
     * Ringback tonunu durdurur.
     */
    fun stopRingbackTone() {
        try {
            // Callback'leri temizle
            ringbackRunnable?.let { runnable ->
                ringbackHandler?.removeCallbacks(runnable)
            }
            ringbackRunnable = null
            ringbackHandler = null

            // ToneGenerator'u guvenli sekilde serbest birak
            ringbackTone?.let { toneGen ->
                try {
                    toneGen.stopTone()
                } catch (_: Exception) {}
                try {
                    toneGen.release()
                } catch (_: Exception) {}
            }
            ringbackTone = null
            android.util.Log.d("RingtonePlayer", "Ringback tone durduruldu")
        } catch (e: Exception) {
            android.util.Log.w("RingtonePlayer", "Ringback tone durdurma hatasi", e)
        }
    }

    fun playConnectedTone() {
        try {
            // STREAM_MUSIC kullanarak daha guvenli ToneGenerator olustur
            val toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 80)

            // Kisa gecikme ile ton cal
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    toneGenerator.startTone(ToneGenerator.TONE_PROP_PROMPT, 200)
                } catch (e: Exception) {
                    android.util.Log.w("RingtonePlayer", "Connected tone calma hatasi", e)
                }
            }, 50)

            // ToneGenerator'u ton bittikten sonra serbest birakmak icin
            // kisa bir gecikme ile release edilir (non-blocking)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    toneGenerator.stopTone()
                    toneGenerator.release()
                } catch (_: Exception) {}
            }, 700)
            android.util.Log.d("RingtonePlayer", "Connected tone caliniyor")
        } catch (e: Exception) {
            android.util.Log.e("RingtonePlayer", "Baglanti sesi calinamadi", e)
        }
    }
}
