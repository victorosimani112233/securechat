package com.securechat.media

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.util.Log
import androidx.core.content.ContextCompat
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton

/**
 * WebSocket uzerinden ses akisi yoneten sinif.
 *
 * WebRTC PeerConnection yerine, ses verisini dogrudan signaling WebSocket
 * baglantisi uzerinden iletir. Bu yaklasim, TURN relay portlarinin
 * adb reverse ile yonlendirilememesi sorununu cozer.
 *
 * Islem akisi:
 * 1. AudioRecord ile mikrofondan PCM ses yakalanir
 * 2. PCM verisi Base64 ile encode edilir
 * 3. SignalingClient uzerinden AudioData mesaji olarak gonderilir
 * 4. Gelen AudioData mesajlari decode edilir
 * 5. AudioTrack ile hoparlorden/kulaklktan calinir
 *
 * Ses parametreleri: 16000 Hz, mono, 16-bit PCM (ses icin yeterli kalite).
 */
@Singleton
class AudioStreamer @Inject constructor(
    @ApplicationContext private val context: Context,
    private val signalingClient: SignalingClient
) {
    companion object {
        private const val TAG = "AudioStreamer"
        const val SAMPLE_RATE = 16000
        const val CHANNEL_CONFIG_IN = AudioFormat.CHANNEL_IN_MONO
        const val CHANNEL_CONFIG_OUT = AudioFormat.CHANNEL_OUT_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        /** Minimum buffer boyutunun kati — gercek zamanli ses icin 2x yeterli. */
        private const val BUFFER_SIZE_MULTIPLIER = 2
    }

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var recordJob: Job? = null
    private var playJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var localUserId: String = ""
    private var remoteUserId: String = ""
    private var isMuted: Boolean = false

    /** Media stream failure callback. */
    var onMediaFailure: ((String) -> Unit)? = null

    /** Izin durumunu kontrol eder, dogrudan crash yerine false dondurur. */
    internal fun hasRecordAudioPermission(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * Ses akisini baslatir. Hem kayit hem oynatma ayni anda calisir.
     *
     * RECORD_AUDIO izni yoksa kayit baslatilmaz ancak oynatma yine de
     * baslatilir (karsi tarafin sesini duymak icin). Uygulama crash olmaz.
     *
     * @param localId Yerel kullanicinin ID'si (gonderilen mesajlarda senderId)
     * @param remoteId Karsi tarafin ID'si (gonderilen mesajlarda recipientId)
     */
    fun start(localId: String, remoteId: String) {
        Log.d(TAG, "start() cagirildi: localId=$localId, remoteId=$remoteId")
        localUserId = localId
        remoteUserId = remoteId
        startRecording()
        startPlaying()
    }

    /**
     * Ses akisini durdurur ve tum kaynaklari serbest birakir.
     */
    fun stop() {
        Log.d(TAG, "stop() cagirildi")
        recordJob?.cancel()
        playJob?.cancel()
        recordJob = null
        playJob = null

        try {
            audioRecord?.stop()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "audioRecord.stop() hatasi: ${e.message}")
        }
        audioRecord?.release()
        audioRecord = null

        try {
            audioTrack?.stop()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "audioTrack.stop() hatasi: ${e.message}")
        }
        audioTrack?.release()
        audioTrack = null
        Log.d(TAG, "stop() tamamlandi, tum kaynaklar serbest birakildi")
    }

    /**
     * Mikrofon sessiz/acik durumunu ayarlar.
     * Sessiz modda kayit devam eder ancak veri gonderilmez.
     *
     * @param muted true ise mikrofon sessiz, false ise acik
     */
    fun setMuted(muted: Boolean) {
        isMuted = muted
        Log.d(TAG, "setMuted($muted)")
    }

    /**
     * Mikrofondan ses yakalama ve signaling uzerinden gonderme islemini baslatir.
     * RECORD_AUDIO izni yoksa islem baslatilmaz ancak hata firlatilmaz.
     */
    private fun startRecording() {
        if (!hasRecordAudioPermission()) {
            Log.e(TAG, "RECORD_AUDIO izni yok! Kayit baslatilAMAZ. " +
                "Kullanici izni verdikten sonra aramayi yeniden baslatmali.")
            return
        }

        val minBufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG_IN, AUDIO_FORMAT)
        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            Log.e(TAG, "AudioRecord.getMinBufferSize hatasi: $minBufferSize")
            return
        }
        val bufferSize = minBufferSize * BUFFER_SIZE_MULTIPLIER
        Log.d(TAG, "Kayit buffer boyutu: minBuffer=$minBufferSize, kullanilan=$bufferSize")

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                SAMPLE_RATE,
                CHANNEL_CONFIG_IN,
                AUDIO_FORMAT,
                bufferSize
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "AudioRecord olusturma hatasi (SecurityException): ${e.message}")
            return
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            val errorMsg = "AudioRecord baslatma basarisiz, state=${audioRecord?.state}"
            Log.e(TAG, errorMsg)
            audioRecord?.release()
            audioRecord = null
            // Critical failure - notify CallManager
            onMediaFailure?.invoke("Mikrofon baslatma hatasi: $errorMsg")
            return
        }

        audioRecord?.startRecording()
        Log.d(TAG, "Kayit baslatildi, bufferSize=$bufferSize, sampleRate=$SAMPLE_RATE")

        recordJob = scope.launch {
            val buffer = ByteArray(minBufferSize)
            var packetCount = 0L
            while (isActive) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: break
                if (read > 0 && !isMuted) {
                    try {
                        val encoded = Base64.getEncoder().encodeToString(buffer.copyOf(read))
                        val sent = signalingClient.sendSignal(
                            SignalMessage.AudioData(
                                senderId = localUserId,
                                recipientId = remoteUserId,
                                timestamp = System.currentTimeMillis(),
                                data = encoded
                            )
                        )
                        packetCount++
                        if (packetCount % 100 == 0L) {
                            Log.d(TAG, "Ses paketi gonderildi: #$packetCount, boyut=$read bytes, gonderim=$sent")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Ses paketi gonderme hatasi: ${e.message}")
                    }
                } else if (read < 0) {
                    Log.w(TAG, "AudioRecord.read hatasi: $read")
                }
            }
            Log.d(TAG, "Kayit dongusu sona erdi, toplam paket=$packetCount")
        }
    }

    /**
     * Gelen ses verisini dinleme ve oynatma islemini baslatir.
     * SignalingClient'in incomingSignals Flow'unu dinler ve
     * remote kullanicidan gelen AudioData mesajlarini AudioTrack ile calar.
     */
    private fun startPlaying() {
        val minBufferSize = AudioTrack.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG_OUT, AUDIO_FORMAT)
        if (minBufferSize == AudioTrack.ERROR || minBufferSize == AudioTrack.ERROR_BAD_VALUE) {
            Log.e(TAG, "AudioTrack.getMinBufferSize hatasi: $minBufferSize")
            return
        }
        val bufferSize = minBufferSize * BUFFER_SIZE_MULTIPLIER
        Log.d(TAG, "Oynatma buffer boyutu: minBuffer=$minBufferSize, kullanilan=$bufferSize")

        try {
            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AUDIO_FORMAT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(CHANNEL_CONFIG_OUT)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "AudioTrack olusturma hatasi: ${e.message}")
            return
        }

        if (audioTrack?.state != AudioTrack.STATE_INITIALIZED) {
            val errorMsg = "AudioTrack baslatma basarisiz, state=${audioTrack?.state}"
            Log.e(TAG, errorMsg)
            audioTrack?.release()
            audioTrack = null
            // Critical failure - notify CallManager
            onMediaFailure?.invoke("Ses oynatma hatasi: $errorMsg")
            return
        }

        audioTrack?.play()
        Log.d(TAG, "Oynatma baslatildi, bufferSize=$bufferSize, sampleRate=$SAMPLE_RATE")

        playJob = scope.launch {
            var packetCount = 0L
            signalingClient.incomingSignals.collect { signal ->
                if (signal is SignalMessage.AudioData && signal.senderId == remoteUserId) {
                    try {
                        val decoded = Base64.getDecoder().decode(signal.data)
                        val written = audioTrack?.write(decoded, 0, decoded.size) ?: 0
                        packetCount++
                        if (packetCount % 100 == 0L) {
                            Log.d(TAG, "Ses paketi alindi ve oynatildi: #$packetCount, " +
                                "boyut=${decoded.size} bytes, yazilan=$written")
                        }
                        if (written < 0) {
                            Log.w(TAG, "AudioTrack.write hatasi: $written")
                        }
                    } catch (e: IllegalArgumentException) {
                        Log.e(TAG, "Base64 decode hatasi: ${e.message}")
                    } catch (e: Exception) {
                        Log.e(TAG, "Ses oynatma hatasi: ${e.message}")
                    }
                }
            }
        }
    }
}
