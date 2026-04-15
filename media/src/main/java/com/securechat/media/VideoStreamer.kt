package com.securechat.media

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.media.ImageReader
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton

/**
 * WebSocket uzerinden video frame akisi yoneten sinif.
 *
 * Camera2 API ile kameradan JPEG frame'leri yakalanir,
 * Base64 ile encode edilir ve SignalingClient uzerinden
 * VideoData mesaji olarak gonderilir.
 *
 * Gelen VideoData mesajlari decode edilerek Bitmap olarak
 * StateFlow uzerinden UI'a sunulur.
 *
 * Performans parametreleri:
 * - Cozunurluk: 320x240 (dusuk bant genisligi icin)
 * - JPEG kalitesi: %25
 * - Hedef FPS: ~8 (Camera2 repeating request ile)
 * - On kamera varsayilan, switchCamera ile degistirilebilir
 */
@Singleton
class VideoStreamer @Inject constructor(
    @ApplicationContext private val context: Context,
    private val signalingClient: SignalingClient
) {
    companion object {
        private const val TAG = "VideoStreamer"
        const val WIDTH = 320
        const val HEIGHT = 240
        const val JPEG_QUALITY = 25
        const val TARGET_FPS = 8
        /** Ardisik frame'ler arasindaki minimum sure (ms). */
        private const val FRAME_INTERVAL_MS = 1000L / TARGET_FPS
    }

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var receiveJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var localUserId = ""
    private var remoteUserId = ""
    internal var isRunning = false
        private set
    internal var useFrontCamera = true
        private set

    /** Son frame gonderim zamani — FPS sinirlamasi icin. */
    private var lastFrameTime = 0L

    /** Media stream failure callback. */
    var onMediaFailure: ((String) -> Unit)? = null

    private val _remoteVideoFrame = MutableStateFlow<Bitmap?>(null)
    /** Karsi tarafin video frame'i — UI tarafindan observe edilir. */
    val remoteVideoFrame: StateFlow<Bitmap?> = _remoteVideoFrame.asStateFlow()

    private val _localVideoFrame = MutableStateFlow<Bitmap?>(null)
    /** Yerel kamera onizleme frame'i — PIP penceresi icin. */
    val localVideoFrame: StateFlow<Bitmap?> = _localVideoFrame.asStateFlow()

    /** Kamera izni kontrolu. */
    internal fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * Video akisini baslatir.
     * Kamera acilir ve gelen frame'leri dinlemeye baslar.
     *
     * CAMERA izni yoksa kamera baslatilmaz ancak gelen frame'ler
     * yine de dinlenir (karsi tarafin goruntusunu gormek icin).
     *
     * @param localId Yerel kullanicinin ID'si
     * @param remoteId Karsi tarafin ID'si
     */
    fun start(localId: String, remoteId: String) {
        Log.d(TAG, "start() cagirildi: localId=$localId, remoteId=$remoteId")
        localUserId = localId
        remoteUserId = remoteId
        isRunning = true
        startCamera()
        startReceiving()
    }

    /**
     * Video akisini durdurur ve tum kaynaklari serbest birakir.
     */
    fun stop() {
        Log.d(TAG, "stop() cagirildi")
        isRunning = false
        receiveJob?.cancel()
        receiveJob = null

        try {
            captureSession?.close()
        } catch (e: Exception) {
            Log.w(TAG, "captureSession.close() hatasi: ${e.message}")
        }
        captureSession = null

        try {
            cameraDevice?.close()
        } catch (e: Exception) {
            Log.w(TAG, "cameraDevice.close() hatasi: ${e.message}")
        }
        cameraDevice = null

        try {
            imageReader?.close()
        } catch (e: Exception) {
            Log.w(TAG, "imageReader.close() hatasi: ${e.message}")
        }
        imageReader = null

        _remoteVideoFrame.value = null
        _localVideoFrame.value = null
        Log.d(TAG, "stop() tamamlandi, tum kaynaklar serbest birakildi")
    }

    /**
     * On ve arka kamera arasinda gecis yapar.
     * Mevcut kamera oturumu kapatilir ve yeni kamera ile yeniden baslatilir.
     */
    fun switchCamera() {
        useFrontCamera = !useFrontCamera
        Log.d(TAG, "switchCamera: useFrontCamera=$useFrontCamera")
        // Mevcut kamerayi kapat ve yeniden baslat
        try {
            captureSession?.close()
        } catch (e: Exception) {
            Log.w(TAG, "switchCamera captureSession.close() hatasi: ${e.message}")
        }
        captureSession = null
        try {
            cameraDevice?.close()
        } catch (e: Exception) {
            Log.w(TAG, "switchCamera cameraDevice.close() hatasi: ${e.message}")
        }
        cameraDevice = null
        startCamera()
    }

    /**
     * Camera2 API ile kamerayi acar ve frame yakalamaya baslar.
     * CAMERA izni yoksa islem baslatilmaz.
     */
    private fun startCamera() {
        if (!hasCameraPermission()) {
            Log.e(TAG, "CAMERA izni yok! Kamera baslatilAMAZ.")
            return
        }

        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = getCameraId(cameraManager)
        if (cameraId == null) {
            Log.e(TAG, "Uygun kamera bulunamadi (front=$useFrontCamera)")
            return
        }

        // Kamera sensor yonelimini al — frame dondurme icin gerekli
        val sensorOrientation = try {
            cameraManager.getCameraCharacteristics(cameraId)
                .get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        } catch (e: Exception) {
            Log.w(TAG, "Sensor orientation alinamadi: ${e.message}")
            0
        }
        Log.d(TAG, "Kamera sensorOrientation=$sensorOrientation, useFrontCamera=$useFrontCamera")

        imageReader = ImageReader.newInstance(WIDTH, HEIGHT, ImageFormat.JPEG, 2)
        imageReader?.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                // FPS sinirlamasi — cok sik frame gonderimini onle
                val now = System.currentTimeMillis()
                if (now - lastFrameTime < FRAME_INTERVAL_MS) {
                    return@setOnImageAvailableListener
                }
                lastFrameTime = now

                val buffer = image.planes[0].buffer
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)

                // Ham JPEG'i Bitmap'e cevir
                val rawBitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: return@setOnImageAvailableListener

                // Rotasyon ve aynalama matrisi uygula
                val correctedBitmap = applyCameraCorrection(rawBitmap, sensorOrientation, useFrontCamera)

                // Duzeltilmis bitmap'i JPEG olarak encode et
                val outputStream = java.io.ByteArrayOutputStream()
                correctedBitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, outputStream)
                val correctedBytes = outputStream.toByteArray()

                // Frame'i signaling uzerinden gonder
                val encoded = Base64.getEncoder().encodeToString(correctedBytes)
                signalingClient.sendSignal(
                    SignalMessage.VideoData(
                        senderId = localUserId,
                        recipientId = remoteUserId,
                        timestamp = now,
                        data = encoded,
                        width = correctedBitmap.width,
                        height = correctedBitmap.height
                    )
                )

                // Yerel onizleme icin duzeltilmis Bitmap kullan
                _localVideoFrame.value = correctedBitmap

                // Orjinal bitmap'i serbest birak (duzeltilmis farkli ise)
                if (correctedBitmap !== rawBitmap) {
                    rawBitmap.recycle()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Frame isleme hatasi: ${e.message}")
            } finally {
                image.close()
            }
        }, mainHandler)

        // Kamerayi ac
        try {
            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    Log.d(TAG, "Kamera acildi: $cameraId")
                    cameraDevice = camera
                    createCaptureSession()
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Kamera baglantisi kesildi")
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    val errorMsg = "Kamera hatasi: error=$error"
                    Log.e(TAG, errorMsg)
                    camera.close()
                    cameraDevice = null
                    // Critical failure - notify CallManager
                    onMediaFailure?.invoke("Kamera hatasi: $errorMsg")
                }
            }, mainHandler)
        } catch (e: SecurityException) {
            Log.e(TAG, "Kamera izni reddedildi: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Kamera acma hatasi: ${e.message}")
        }
    }

    /**
     * Camera2 capture session olusturur.
     * ImageReader surface'ine repeating request baslatir.
     */
    private fun createCaptureSession() {
        val camera = cameraDevice ?: return
        val reader = imageReader ?: return

        try {
            camera.createCaptureSession(
                listOf(reader.surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        Log.d(TAG, "Capture session yapilandirildi")
                        captureSession = session
                        try {
                            val request = camera.createCaptureRequest(
                                CameraDevice.TEMPLATE_PREVIEW
                            ).apply {
                                addTarget(reader.surface)
                            }
                            // Surekli frame yakalama
                            session.setRepeatingRequest(request.build(), null, mainHandler)
                        } catch (e: Exception) {
                            Log.e(TAG, "Repeating request hatasi: ${e.message}")
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        val errorMsg = "Capture session yapilandirma basarisiz"
                        Log.e(TAG, errorMsg)
                        // Critical failure - notify CallManager
                        onMediaFailure?.invoke("Video kaydi baslatma hatasi: $errorMsg")
                    }
                },
                mainHandler
            )
        } catch (e: Exception) {
            Log.e(TAG, "createCaptureSession hatasi: ${e.message}")
        }
    }

    /**
     * Gelen video frame'lerini dinler ve Bitmap olarak decode eder.
     * Karsi taraftan gelen VideoData mesajlari remoteVideoFrame StateFlow'una yazilir.
     */
    private fun startReceiving() {
        receiveJob = scope.launch {
            signalingClient.incomingSignals.collect { signal ->
                if (signal is SignalMessage.VideoData && signal.senderId == remoteUserId) {
                    try {
                        val decoded = Base64.getDecoder().decode(signal.data)
                        val bitmap = BitmapFactory.decodeByteArray(decoded, 0, decoded.size)
                        _remoteVideoFrame.value = bitmap
                    } catch (e: Exception) {
                        Log.e(TAG, "Video frame decode hatasi: ${e.message}")
                    }
                }
            }
        }
    }

    /**
     * Kamera sensor yonelimine gore bitmap'e rotasyon ve aynalama uygular.
     * On kamera kullanildiginda yatay aynalama (mirror) yapilir,
     * boylece kullanici kendisini aynada gordugu gibi gorur.
     *
     * @param bitmap Ham kamera frame'i
     * @param sensorOrientation Kamera sensor yonelim acisi (derece)
     * @param isFrontCamera On kamera kullaniliyor mu
     * @return Duzeltilmis bitmap
     */
    private fun applyCameraCorrection(
        bitmap: Bitmap,
        sensorOrientation: Int,
        isFrontCamera: Boolean
    ): Bitmap {
        val matrix = Matrix()

        // Sensor yonelimine gore dondur
        if (sensorOrientation != 0) {
            matrix.postRotate(sensorOrientation.toFloat())
        }

        // On kamera icin yatay aynalama (mirror) uygula
        if (isFrontCamera) {
            matrix.postScale(-1f, 1f, bitmap.width / 2f, bitmap.height / 2f)
        }

        return try {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (e: Exception) {
            Log.e(TAG, "Bitmap duzeltme hatasi: ${e.message}")
            bitmap
        }
    }

    /**
     * Istenen kamera yonune (on/arka) gore kamera ID'sini dondurur.
     *
     * @param manager CameraManager
     * @return Kamera ID'si veya bulunamazsa null
     */
    internal fun getCameraId(manager: CameraManager): String? {
        val facing = if (useFrontCamera) CameraCharacteristics.LENS_FACING_FRONT
        else CameraCharacteristics.LENS_FACING_BACK
        return manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING) == facing
        }
    }
}
