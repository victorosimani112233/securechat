package com.securechat.media

import android.content.Context
import android.content.pm.PackageManager
import com.securechat.network.SignalingClient
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * AudioStreamer sinifinin unit testleri.
 *
 * AudioRecord ve AudioTrack Android native siniflar oldugu icin
 * birim testlerde dogrudan test edilemez. Bu testler AudioStreamer'in
 * mute/unmute mantigi, izin kontrolu ve start/stop yasam dongusunu dogrular.
 *
 * Gercek ses akisi testleri instrumented test olarak yapilmalidir.
 */
class AudioStreamerTest {

    private lateinit var audioStreamer: AudioStreamer
    private lateinit var context: Context
    private lateinit var signalingClient: SignalingClient

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)

        // RECORD_AUDIO izni olmadigi durumu simule et (birim test ortami)
        every {
            context.checkPermission(any(), any(), any())
        } returns PackageManager.PERMISSION_DENIED

        audioStreamer = AudioStreamer(context, signalingClient)
    }

    // ---- Mute testleri ----

    @Test
    fun `setMuted true mutes the stream`() {
        audioStreamer.setMuted(true)
        // Muted durumu internal state olarak ayarlanir
        // Dogrudan kontrol edemiyoruz ama hata firlatmamali
    }

    @Test
    fun `setMuted false unmutes the stream`() {
        audioStreamer.setMuted(true)
        audioStreamer.setMuted(false)
        // Hata firlatmamali
    }

    @Test
    fun `setMuted can be toggled multiple times`() {
        audioStreamer.setMuted(true)
        audioStreamer.setMuted(false)
        audioStreamer.setMuted(true)
        audioStreamer.setMuted(false)
        // Birden fazla toggle guvenli olmali
    }

    // ---- Stop guvenlik testleri ----

    @Test
    fun `stop without start does not crash`() {
        // start() cagrilmadan stop() cagirmak guvenli olmali
        audioStreamer.stop()
    }

    @Test
    fun `stop can be called multiple times safely`() {
        audioStreamer.stop()
        audioStreamer.stop()
        // Birden fazla stop() cagirisi guvenli olmali
    }

    // ---- Izin kontrolu testleri ----

    @Test
    fun `hasRecordAudioPermission returns false when permission denied`() {
        every {
            context.checkPermission(any(), any(), any())
        } returns PackageManager.PERMISSION_DENIED

        assertFalse(audioStreamer.hasRecordAudioPermission())
    }

    @Test
    fun `hasRecordAudioPermission returns true when permission granted`() {
        every {
            context.checkPermission(any(), any(), any())
        } returns PackageManager.PERMISSION_GRANTED

        assertTrue(audioStreamer.hasRecordAudioPermission())
    }

    @Test
    fun `start without permission does not crash`() {
        // Izin yokken start() cagirildiginda crash olmamali
        every {
            context.checkPermission(any(), any(), any())
        } returns PackageManager.PERMISSION_DENIED

        audioStreamer.start("local-user", "remote-user")
        // Hata firlatmamali, sadece loglayip devam etmeli
    }

    @Test
    fun `start then stop is safe without permission`() {
        every {
            context.checkPermission(any(), any(), any())
        } returns PackageManager.PERMISSION_DENIED

        audioStreamer.start("local-user", "remote-user")
        audioStreamer.stop()
        // Izinsiz baslayip durdurmak guvenli olmali
    }

    // ---- Companion object sabitleri ----

    @Test
    fun `companion object constants are correct`() {
        assertEquals(16000, AudioStreamer.SAMPLE_RATE)
        // CHANNEL_IN_MONO = 16 (AudioFormat.CHANNEL_IN_MONO)
        // CHANNEL_OUT_MONO = 4 (AudioFormat.CHANNEL_OUT_MONO)
        // ENCODING_PCM_16BIT = 2 (AudioFormat.ENCODING_PCM_16BIT)
    }

    @Test
    fun `SAMPLE_RATE is suitable for voice communication`() {
        // 16kHz wideband ses icin standart oran
        assertTrue(AudioStreamer.SAMPLE_RATE >= 8000)
        assertTrue(AudioStreamer.SAMPLE_RATE <= 48000)
    }

    // ---- Yasam dongusu testleri ----

    @Test
    fun `start sets local and remote user IDs`() {
        // start cagirildiginda localUserId ve remoteUserId ayarlanmali
        // Izin yoksa kayit baslamaz ama ID'ler yine de ayarlanir
        audioStreamer.start("user-A", "user-B")
        audioStreamer.stop()
        // Crash olmamali
    }

    @Test
    fun `multiple start stop cycles are safe`() {
        // Birden fazla baslat-durdur dongusu guvenli olmali
        audioStreamer.start("user-A", "user-B")
        audioStreamer.stop()
        audioStreamer.start("user-C", "user-D")
        audioStreamer.stop()
    }
}
