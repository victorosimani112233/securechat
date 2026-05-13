package com.securechat.media

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Arama sirasinda ses yonlendirmesini yoneten sinif.
 *
 * Sorumluluklari:
 * - Arama moduna gecis (MODE_IN_COMMUNICATION)
 * - Hoparlor acma/kapama
 * - Arama sonrasi onceki ses ayarlarina geri donme
 */
@Singleton
@Suppress("DEPRECATION") // isSpeakerphoneOn — Android 12+ setCommunicationDevice() var ama 26-31 destek korunuyor
class CallAudioManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var previousAudioMode: Int = AudioManager.MODE_NORMAL
    private var previousSpeakerState: Boolean = false
    private var audioFocusRequest: AudioFocusRequest? = null

    /**
     * Ses sistemini arama moduna gecirir.
     * Audio focus talep eder, onceki durumu kaydeder.
     */
    fun setCallMode() {
        previousAudioMode = audioManager.mode
        previousSpeakerState = audioManager.isSpeakerphoneOn

        // Audio focus talep et — bu olmadan Android ses yonlendirmesi duzgun calismaz
        try {
            val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .build()
            audioManager.requestAudioFocus(focusRequest)
            audioFocusRequest = focusRequest
        } catch (_: Exception) {
            // Bazi cihazlarda veya JVM test ortaminda AudioFocusRequest olusturulamayabilir
        }

        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = false
    }

    /**
     * Hoparloru acar veya kapatir.
     *
     * @param on true ise hoparlor acilir, false ise kapatilir
     */
    fun setSpeakerOn(on: Boolean) {
        audioManager.isSpeakerphoneOn = on
    }

    /**
     * Hoparlorun acik olup olmadigini dondurur.
     *
     * @return Hoparlor aciksa true
     */
    fun isSpeakerOn(): Boolean = audioManager.isSpeakerphoneOn

    /**
     * Ses sistemini arama oncesi durumuna geri yukler ve audio focus birakir.
     */
    fun resetAudioMode() {
        audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        audioFocusRequest = null
        audioManager.mode = previousAudioMode
        audioManager.isSpeakerphoneOn = previousSpeakerState
    }

    /**
     * Mevcut ses modunu dondurur.
     *
     * @return AudioManager modu (orn. MODE_NORMAL, MODE_IN_COMMUNICATION)
     */
    fun getCurrentAudioMode(): Int = audioManager.mode
}
