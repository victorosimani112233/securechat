package com.securechat.media

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.Segmenter
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import org.webrtc.VideoFrame
import org.webrtc.VideoProcessor
import org.webrtc.VideoSink
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Goruntulu cagrida yerel kamera frame'lerinin arka planini bulaniklastirir.
 *
 * Pipeline:
 *   1. WebRTC capturer → VideoProcessor.onFrameCaptured(I420)
 *   2. I420 → ARGB Bitmap (BT.601 YUV→RGB)
 *   3. ML Kit SelfieSegmentation → maskBitmap (foreground=person)
 *   4. Background blur + mask compositing → final Bitmap
 *   5. ARGB → I420 → VideoFrame → sink (downstream encoder)
 *
 * Performans:
 *   - Async submit + skip-frame: capturer thread'i bloklamadan SingleThreadExecutor'a
 *     atilir. Backlog varsa yeni frame pass-through gider (kullanici cok az gecikme
 *     gorebilir ama akis surekli).
 *   - ML Kit STREAM_MODE — dusuk latans icin optimize, ~30-80ms tipik.
 *   - 720x480'de tum pipeline ~100-200ms hedef; orta seviye cihaz 5-10 FPS.
 *
 * Sinirlar (v1):
 *   - Eski cihazlarda yavas — kullanici manuel kapatabilir.
 *   - Mask cache yok: her frame yeniden segment edilir.
 *   - Texture-based GPU pipeline yerine CPU; ileride RenderEffect (SDK 31+)
 *     veya OpenGL shader composite ile hizlandirilabilir.
 *
 * Lifecycle:
 *   - setSink null gelirse downstream'e gondermeyiz.
 *   - dispose() ML Kit segmenter'i kapatir + executor'i shutdown eder.
 */
class BackgroundBlurProcessor : VideoProcessor {

    @Volatile private var sink: VideoSink? = null
    @Volatile var isEnabled: Boolean = false

    private val processing = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "BgBlurProcessor").apply { isDaemon = true }
    }

    private val segmenter: Segmenter by lazy {
        val options = SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
            .build()
        Segmentation.getClient(options)
    }

    /**
     * Arka plan blur kalitesi — kucuk degerler daha yumusak ama daha pahali.
     * Downscale faktoru: 8 → 720x480 → 90x60 → tekrar 720x480 (bilineer).
     * minSdk 26 destegi icin RenderEffect/RenderScript yerine downscale-upscale.
     * Tipik islem suresi: ~10-20ms 720p.
     */
    private val blurDownscale = 8

    override fun setSink(sink: VideoSink?) {
        this.sink = sink
    }

    override fun onCapturerStarted(success: Boolean) {
        Log.d(TAG, "Capturer started: $success")
    }

    override fun onCapturerStopped() {
        Log.d(TAG, "Capturer stopped")
    }

    override fun onFrameCaptured(frame: VideoFrame) {
        val downstream = sink ?: return

        // Devre disi veya islenen frame varsa: pass-through.
        // Skip-frame stratejisi — capture thread bloklanmaz, akis surekli.
        if (!isEnabled || processing.get()) {
            downstream.onFrame(frame)
            return
        }

        // Frame'i diger thread'de kullanmak icin retain (release executor'da yapilir).
        frame.retain()
        processing.set(true)
        executor.execute {
            try {
                val blurredFrame = processFrame(frame)
                if (blurredFrame != null) {
                    downstream.onFrame(blurredFrame)
                    blurredFrame.release()
                } else {
                    // Islem basarisiz → orijinali gonder, kullanici siyah ekran gormesin
                    downstream.onFrame(frame)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Frame islenirken hata: ${t.message}")
                runCatching { downstream.onFrame(frame) }
            } finally {
                frame.release()
                processing.set(false)
            }
        }
    }

    /**
     * Frame'i isler ve blur uygulanmis yeni VideoFrame dondurur.
     * null donerse caller orijinal frame'i pass-through eder.
     */
    private fun processFrame(frame: VideoFrame): VideoFrame? {
        val i420 = frame.buffer.toI420() ?: return null
        try {
            val width = i420.width
            val height = i420.height

            // 1. I420 → ARGB Bitmap
            val argbBitmap = i420ToArgbBitmap(i420, width, height)

            // 2. ML Kit segmentation (synchronous via Tasks.await)
            val maskInfo = runSegmentation(argbBitmap) ?: run {
                argbBitmap.recycle()
                return null
            }

            // 3. Background blur + mask composite
            val blendedBitmap = applyBlurWithMask(argbBitmap, maskInfo)
            argbBitmap.recycle()

            // 4. ARGB Bitmap → I420 → VideoFrame
            val newBuffer = argbBitmapToI420Buffer(blendedBitmap, width, height)
            blendedBitmap.recycle()

            return VideoFrame(newBuffer, frame.rotation, frame.timestampNs)
        } finally {
            i420.release()
        }
    }

    // ------- ML Kit segmentation (synchronous) -------

    private fun runSegmentation(bitmap: Bitmap): MaskInfo? {
        // SDK 26+ kameralar dik gelir (rotation 0). ML Kit InputImage rotation
        // parametresine direk frame.rotation gecirebiliriz, ancak bitmap zaten
        // dik render edildi (i420→argb sirasinda); rotation 0 ile devam.
        val input = InputImage.fromBitmap(bitmap, 0)
        val task = segmenter.process(input)
        // STREAM_MODE'da Tasks.await senkron blokaj — tipik 30-80ms.
        return try {
            val mask = com.google.android.gms.tasks.Tasks.await(task) ?: return null
            // Mask buffer'i dogrudan kullanmak yerine kopyaliyoruz — re-use bitmap
            // pipeline'inda race olabilir.
            val maskBuffer = mask.buffer
            val maskW = mask.width
            val maskH = mask.height
            val confidences = FloatArray(maskW * maskH)
            maskBuffer.rewind()
            maskBuffer.asFloatBuffer().get(confidences)
            MaskInfo(confidences, maskW, maskH)
        } catch (t: Throwable) {
            Log.w(TAG, "Segmentation fail: ${t.message}")
            null
        }
    }

    private data class MaskInfo(val confidences: FloatArray, val width: Int, val height: Int)

    // ------- Blur + composite -------

    /**
     * Arka plani blur'lar, foreground'i (insan) keskin birakir.
     *
     * Algoritma:
     *   1. Orijinal bitmap'in blur'lu kopyasini olustur (BlurMaskFilter)
     *   2. Foreground mask bitmap olustur (confidence > 0.5)
     *   3. blurredBg + foregroundOriginal composite (mask ile)
     *
     * BlurMaskFilter SDK 26+ destekler ve software rendering uses RenderScript-like
     * native blur. Performance: ~10-30ms 720p.
     */
    private fun applyBlurWithMask(source: Bitmap, maskInfo: MaskInfo): Bitmap {
        val w = source.width
        val h = source.height

        // 1. Blur'lu arka plan — downscale-then-upscale (fast box blur approximation).
        // Pure pixel reduction + bilineer upscale = doğal "bulanik" görüntü.
        val smallW = (w / blurDownscale).coerceAtLeast(1)
        val smallH = (h / blurDownscale).coerceAtLeast(1)
        val small = Bitmap.createScaledBitmap(source, smallW, smallH, true)
        val blurredBg = Bitmap.createScaledBitmap(small, w, h, true)
        small.recycle()

        // 2. Mask'i bitmap'a cevir (foreground=opak, background=seffaf)
        // Mask boyutu source ile farkli olabilir — bitmap'a esle, sonra Matrix ile scale et.
        val maskBitmap = Bitmap.createBitmap(maskInfo.width, maskInfo.height, Bitmap.Config.ARGB_8888)
        val maskPixels = IntArray(maskInfo.width * maskInfo.height)
        for (i in maskPixels.indices) {
            val conf = maskInfo.confidences[i]
            // SelfieSegmenter convention: confidence yuksek = foreground (person)
            val alpha = (conf * 255f).toInt().coerceIn(0, 255)
            maskPixels[i] = (alpha shl 24) or 0x00FFFFFF
        }
        maskBitmap.setPixels(maskPixels, 0, maskInfo.width, 0, 0, maskInfo.width, maskInfo.height)

        // 3. Composite: blurredBg + (source MASKED by maskBitmap)
        val resultBitmap = blurredBg  // re-use, draw foreground over
        val compositeCanvas = Canvas(resultBitmap)

        // Foreground bitmap = source MASKED by maskBitmap (mask alpha)
        // Strategy: yeni bitmap'a source ciz, sonra DST_IN ile mask uygula.
        val foreground = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val fgCanvas = Canvas(foreground)
        fgCanvas.drawBitmap(source, 0f, 0f, null)
        val maskPaint = Paint().apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        }
        // Mask'i source boyutuna scale ederek ciz
        val srcRect = Rect(0, 0, maskInfo.width, maskInfo.height)
        val dstRect = Rect(0, 0, w, h)
        fgCanvas.drawBitmap(maskBitmap, srcRect, dstRect, maskPaint)

        // Foreground'i blurredBg uzerine ciz
        compositeCanvas.drawBitmap(foreground, 0f, 0f, null)

        foreground.recycle()
        maskBitmap.recycle()
        return resultBitmap
    }

    // ------- I420 ↔ ARGB conversion -------

    /**
     * I420 (YUV 4:2:0 planar) → ARGB_8888 Bitmap.
     * BT.601 limited-range donusumu.
     */
    private fun i420ToArgbBitmap(i420: VideoFrame.I420Buffer, width: Int, height: Int): Bitmap {
        val y = i420.dataY
        val u = i420.dataU
        val v = i420.dataV
        val strideY = i420.strideY
        val strideU = i420.strideU
        val strideV = i420.strideV

        val pixels = IntArray(width * height)
        for (row in 0 until height) {
            val yRow = row * strideY
            val uvRow = (row shr 1) * strideU
            val vRow = (row shr 1) * strideV
            for (col in 0 until width) {
                val yi = (y.get(yRow + col).toInt() and 0xFF) - 16
                val ui = (u.get(uvRow + (col shr 1)).toInt() and 0xFF) - 128
                val vi = (v.get(vRow + (col shr 1)).toInt() and 0xFF) - 128

                // BT.601 formulleri (limited range)
                val r = ((1.164f * yi + 1.596f * vi) + 0.5f).toInt().coerceIn(0, 255)
                val g = ((1.164f * yi - 0.392f * ui - 0.813f * vi) + 0.5f).toInt().coerceIn(0, 255)
                val b = ((1.164f * yi + 2.017f * ui) + 0.5f).toInt().coerceIn(0, 255)

                pixels[row * width + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
        return bitmap
    }

    /**
     * ARGB_8888 Bitmap → I420Buffer (JavaI420Buffer).
     * BT.601 limited-range donusumu.
     */
    private fun argbBitmapToI420Buffer(bitmap: Bitmap, width: Int, height: Int): VideoFrame.I420Buffer {
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        val ySize = width * height
        val uvSize = (width / 2) * (height / 2)
        val yBytes = ByteArray(ySize)
        val uBytes = ByteArray(uvSize)
        val vBytes = ByteArray(uvSize)

        for (row in 0 until height) {
            for (col in 0 until width) {
                val px = pixels[row * width + col]
                val r = (px shr 16) and 0xFF
                val g = (px shr 8) and 0xFF
                val b = px and 0xFF

                // BT.601 RGB → YUV
                val yv = (0.257f * r + 0.504f * g + 0.098f * b + 16f).toInt().coerceIn(0, 255)
                yBytes[row * width + col] = yv.toByte()

                // U/V sub-sample (2x2 block top-left only)
                if ((row and 1) == 0 && (col and 1) == 0) {
                    val uv = (-0.148f * r - 0.291f * g + 0.439f * b + 128f).toInt().coerceIn(0, 255)
                    val vv = (0.439f * r - 0.368f * g - 0.071f * b + 128f).toInt().coerceIn(0, 255)
                    val uvIdx = (row shr 1) * (width shr 1) + (col shr 1)
                    uBytes[uvIdx] = uv.toByte()
                    vBytes[uvIdx] = vv.toByte()
                }
            }
        }

        // JavaI420Buffer allocate — yBytes/uBytes/vBytes'i kopyalar (kendi buffer'i acar).
        val buffer = org.webrtc.JavaI420Buffer.allocate(width, height)
        copyToBuffer(buffer.dataY, yBytes, buffer.strideY, width, height)
        copyToBuffer(buffer.dataU, uBytes, buffer.strideU, width / 2, height / 2)
        copyToBuffer(buffer.dataV, vBytes, buffer.strideV, width / 2, height / 2)
        return buffer
    }

    private fun copyToBuffer(dst: ByteBuffer, src: ByteArray, stride: Int, w: Int, h: Int) {
        dst.rewind()
        if (stride == w) {
            dst.put(src, 0, w * h)
        } else {
            for (row in 0 until h) {
                dst.position(row * stride)
                dst.put(src, row * w, w)
            }
        }
    }

    /** Surekli kullanim sirasinda cagrilmaz; CallManager dispose'da bir kez cagirir. */
    fun dispose() {
        runCatching { segmenter.close() }
        runCatching { executor.shutdownNow() }
    }

    companion object {
        private const val TAG = "BgBlurProcessor"
    }
}
