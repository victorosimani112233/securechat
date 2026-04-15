package com.securechat.media

import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Vibrator
import android.os.VibratorManager
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test

/**
 * RingtonePlayer sinifinin unit testleri.
 *
 * Zil sesi baslatma/durdurma, titresim baslatma/durdurma ve
 * baglanti sesi calma islemleri test edilir.
 *
 * NOT: Android framework siniflari (Ringtone, Vibrator, ToneGenerator)
 * mock'lanir. unitTests.isReturnDefaultValues = true ayari sayesinde
 * static metod cagirilari varsayilan deger dondurur.
 */
class RingtonePlayerTest {

    private lateinit var ringtonePlayer: RingtonePlayer
    private lateinit var context: Context
    private lateinit var vibrator: Vibrator

    @Before
    fun setup() {
        vibrator = mockk(relaxed = true)
        context = mockk(relaxed = true) {
            every { getSystemService(Context.VIBRATOR_SERVICE) } returns vibrator
        }

        ringtonePlayer = RingtonePlayer(context)
    }

    @Test
    fun `RingtonePlayer is created successfully`() {
        assertNotNull(ringtonePlayer)
    }

    @Test
    fun `stopRinging is safe to call without startRinging`() {
        // stopRinging hicbir sey baslatilmamissa hata vermemeli (idempotent)
        ringtonePlayer.stopRinging()
        // Hata firlatilmadiysa test basarili
    }

    @Test
    fun `stopRinging can be called multiple times safely`() {
        // Birden fazla stopRinging cagrisi hata vermemeli
        ringtonePlayer.stopRinging()
        ringtonePlayer.stopRinging()
        ringtonePlayer.stopRinging()
        // Hata firlatilmadiysa test basarili
    }

    @Test
    fun `playConnectedTone does not throw`() {
        // ToneGenerator static factory oldugu icin dogrudan test edilemez,
        // ancak exception firlatmamasi dogrulanir
        ringtonePlayer.playConnectedTone()
        // Hata firlatilmadiysa test basarili
    }

    @Test
    fun `startRinging then stopRinging lifecycle`() {
        // startRinging -> stopRinging yasam dongusu hatasiz calismali
        // Android framework siniflari returnDefaultValues=true ile mock'lanir
        ringtonePlayer.startRinging()
        ringtonePlayer.stopRinging()
        // Hata firlatilmadiysa test basarili
    }
}
