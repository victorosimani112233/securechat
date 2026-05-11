package com.securechat.media

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
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
    private val mainHandler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null
    private var ringbackTone: ToneGenerator? = null
    private var ringbackHandler: Handler? = null
    private var ringbackRunnable: Runnable? = null
    private var ringingToken = 0
    private var ringbackToken = 0

    /**
     * Zil sesi ve titresimi baslatir.
     * Gelen arama alglandiginda cagirilir.
     *
     * Zil sesi: Cihazin varsayilan zil sesi (TYPE_RINGTONE)
     * Titresim deseni: 0ms bekle, 1000ms titre, 1000ms bekle (tekrarli)
     */
    @Synchronized
    fun startRinging() {
        stopRingingLocked()
        val token = ++ringingToken
        mainHandler.post {
            synchronized(this@RingtonePlayer) {
                if (token != ringingToken) return@synchronized
                try {
                    val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                    val newRingtone = RingtoneManager.getRingtone(context, ringtoneUri)
                    newRingtone?.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    newRingtone?.play()
                    ringtone = newRingtone
                } catch (e: Exception) {
                    android.util.Log.e("RingtonePlayer", "Zil sesi calinamadi", e)
                }

                try {
                    vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                        vm.defaultVibrator
                    } else {
                        @Suppress("DEPRECATION")
                        context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                    }

                    val pattern = longArrayOf(0, 1000, 1000)
                    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
                } catch (e: Exception) {
                    android.util.Log.e("RingtonePlayer", "Titresim baslatilmadi", e)
                }
            }
        }
    }

    /**
     * Zil sesi ve titresimi durdurur.
     * Arama kabul edildiginde, reddedildiginde veya sonlandirildiginda cagirilir.
     * Birden fazla kez cagrilmasi guvenlidir (idempotent).
     */
    @Synchronized
    fun stopRinging() {
        stopRingingLocked()
    }

    private fun stopRingingLocked() {
        ringingToken++
        val oldRingtone = ringtone
        val oldVibrator = vibrator
        ringtone = null
        vibrator = null
        mainHandler.post {
            try {
                oldRingtone?.stop()
            } catch (e: Exception) {
                android.util.Log.w("RingtonePlayer", "Zil sesi durdurma hatasi", e)
            }
            try {
                oldVibrator?.cancel()
            } catch (e: Exception) {
                android.util.Log.w("RingtonePlayer", "Titresim durdurma hatasi", e)
            }
        }
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
    @Synchronized
    fun startRingbackTone() {
        try {
            stopRingbackToneLocked()
            val token = ++ringbackToken

            mainHandler.post {
                try {
                    synchronized(this@RingtonePlayer) {
                        if (token != ringbackToken) return@synchronized
                        val toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
                        val handler = mainHandler
                        val runnable = object : Runnable {
                            override fun run() {
                                val active = synchronized(this@RingtonePlayer) {
                                    token == ringbackToken
                                }
                                if (!active) return
                                try {
                                    toneGenerator.startTone(ToneGenerator.TONE_SUP_RINGTONE, 1000)
                                    synchronized(this@RingtonePlayer) {
                                        if (token == ringbackToken) {
                                            handler.postDelayed(this, 3000)
                                        }
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.w("RingtonePlayer", "Ringback tone calma hatasi", e)
                                }
                            }
                        }
                        ringbackTone = toneGenerator
                        ringbackHandler = handler
                        ringbackRunnable = runnable
                        handler.postDelayed(runnable, 100)
                        android.util.Log.d("RingtonePlayer", "Ringback tone baslatildi")
                    }
                } catch (e: Exception) {
                    android.util.Log.e("RingtonePlayer", "Ringback tone baslatilmadi", e)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("RingtonePlayer", "Ringback tone baslatilmadi", e)
        }
    }

    /**
     * Ringback tonunu durdurur.
     */
    @Synchronized
    fun stopRingbackTone() {
        stopRingbackToneLocked()
    }

    private fun stopRingbackToneLocked() {
        try {
            ringbackToken++
            val oldRunnable = ringbackRunnable
            val oldHandler = ringbackHandler
            val oldTone = ringbackTone
            ringbackRunnable = null
            ringbackHandler = null
            ringbackTone = null

            mainHandler.post {
                oldRunnable?.let { runnable ->
                    oldHandler?.removeCallbacks(runnable)
                }
                oldTone?.let { toneGen ->
                    try {
                        toneGen.stopTone()
                    } catch (_: Exception) {}
                    try {
                        toneGen.release()
                    } catch (_: Exception) {}
                }
                android.util.Log.d("RingtonePlayer", "Ringback tone durduruldu")
            }
        } catch (e: Exception) {
            android.util.Log.w("RingtonePlayer", "Ringback tone durdurma hatasi", e)
        }
    }

    /**
     * Call-waiting tonu — aktif arama sirasinda ikinci bir arama gelirse
     * kullaniciya "biip-biip" sesi calar (telefon hat servisindeki gibi).
     * Tek sefer calinir, 1.5 saniye sonra otomatik biter.
     */
    fun playWaitingTone() {
        try {
            val toneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 60)
            mainHandler.postDelayed({
                try {
                    // TONE_SUP_CALL_WAITING — standart "call waiting" sinyali
                    toneGenerator.startTone(ToneGenerator.TONE_SUP_CALL_WAITING, 300)
                } catch (e: Exception) {
                    android.util.Log.w("RingtonePlayer", "Waiting tone calma hatasi", e)
                }
            }, 50)
            mainHandler.postDelayed({
                try {
                    toneGenerator.stopTone()
                    toneGenerator.release()
                } catch (_: Exception) {}
            }, 1500)
            android.util.Log.d("RingtonePlayer", "Waiting tone caliniyor")
        } catch (e: Exception) {
            android.util.Log.e("RingtonePlayer", "Waiting tone calinamadi", e)
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
