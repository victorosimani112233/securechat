package com.securechat.media

import android.content.Context
import android.media.AudioManager
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import io.mockk.verifyOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * CallAudioManager sinifinin unit testleri.
 *
 * Ses yonlendirmesi (hoparlor, arama modu) ve
 * onceki durum kaydetme/yukleme islemleri test edilir.
 */
class CallAudioManagerTest {

    private lateinit var callAudioManager: CallAudioManager
    private lateinit var context: Context
    private lateinit var audioManager: AudioManager

    @Before
    fun setup() {
        audioManager = mockk(relaxed = true)
        context = mockk(relaxed = true) {
            every { getSystemService(Context.AUDIO_SERVICE) } returns audioManager
        }

        callAudioManager = CallAudioManager(context)
    }

    @Test
    fun `setCallMode saves previous state`() {
        every { audioManager.mode } returns AudioManager.MODE_NORMAL
        every { audioManager.isSpeakerphoneOn } returns true

        callAudioManager.setCallMode()

        // Moda MODE_IN_COMMUNICATION ayarlanmali
        verify { audioManager.mode = AudioManager.MODE_IN_COMMUNICATION }
        // Hoparlor kapatilmali
        verify { audioManager.isSpeakerphoneOn = false }
    }

    @Test
    fun `setCallMode sets MODE_IN_COMMUNICATION`() {
        every { audioManager.mode } returns AudioManager.MODE_NORMAL
        every { audioManager.isSpeakerphoneOn } returns false

        callAudioManager.setCallMode()

        verify { audioManager.mode = AudioManager.MODE_IN_COMMUNICATION }
    }

    @Test
    fun `setSpeakerOn delegates to AudioManager`() {
        callAudioManager.setSpeakerOn(true)
        verify { audioManager.isSpeakerphoneOn = true }

        callAudioManager.setSpeakerOn(false)
        verify { audioManager.isSpeakerphoneOn = false }
    }

    @Test
    fun `isSpeakerOn returns AudioManager state`() {
        every { audioManager.isSpeakerphoneOn } returns true
        assertTrue(callAudioManager.isSpeakerOn())

        every { audioManager.isSpeakerphoneOn } returns false
        assertFalse(callAudioManager.isSpeakerOn())
    }

    @Test
    fun `resetAudioMode restores previous state`() {
        // Onceki durumu kaydet: MODE_RINGTONE ve hoparlor acik
        every { audioManager.mode } returns AudioManager.MODE_RINGTONE
        every { audioManager.isSpeakerphoneOn } returns true

        callAudioManager.setCallMode()

        // Simdi sifirla
        callAudioManager.resetAudioMode()

        // Onceki degerler geri yuklenmeli
        verify { audioManager.mode = AudioManager.MODE_RINGTONE }
        verify { audioManager.isSpeakerphoneOn = true }
    }

    @Test
    fun `resetAudioMode restores MODE_NORMAL when previous was NORMAL`() {
        every { audioManager.mode } returns AudioManager.MODE_NORMAL
        every { audioManager.isSpeakerphoneOn } returns false

        callAudioManager.setCallMode()
        callAudioManager.resetAudioMode()

        verify { audioManager.mode = AudioManager.MODE_NORMAL }
        verify { audioManager.isSpeakerphoneOn = false }
    }

    @Test
    fun `getCurrentAudioMode returns current mode`() {
        every { audioManager.mode } returns AudioManager.MODE_IN_COMMUNICATION
        assertEquals(AudioManager.MODE_IN_COMMUNICATION, callAudioManager.getCurrentAudioMode())
    }

    @Test
    fun `setCallMode then resetAudioMode preserves order`() {
        every { audioManager.mode } returns AudioManager.MODE_NORMAL
        every { audioManager.isSpeakerphoneOn } returns false

        callAudioManager.setCallMode()
        callAudioManager.resetAudioMode()

        verifyOrder {
            // Arama moduna gec
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            // Sonra geri yukle
            audioManager.mode = AudioManager.MODE_NORMAL
        }
    }
}
