package com.securechat.app.diagnostics

import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Yakalanan exception'i deterministik, paylasilabilir bir metin formatina cevirir.
 *
 * Pure utility — dosya sistemi, Android API'si veya Thread'e dokunmaz.
 * Bu sayede unit test edilebilir ve format degisiklikleri TestForensik tablo
 * testleri ile dogrulanabilir.
 *
 * Cikti yapisi (her crash icin tek dosya):
 *
 *   === ELÇİM CRASH REPORT ===
 *   timestamp: 2026-06-08T18:30:42Z
 *   versionName: 1.0.77-2cd3ce9
 *   versionCode: 77
 *   android: 14 (SDK 34)
 *   device: Pixel 7
 *   manufacturer: Google
 *   thread: main
 *
 *   --- STACK ---
 *   java.lang.RuntimeException: ...
 *       at ...
 *
 *   --- CAUSE: ... (tekrarlanir, en altta root) ---
 *
 * GUVENLIK NOTU: stack trace plaintext mesaj icermez (Signal Protocol cipher
 * bytes loglara yansimaz cunku encrypt/decrypt fonksiyonlari plaintext'i
 * exception mesajinda barindirmaz). Ama defansif olarak FILTERED kelimesini
 * iceren satirlari atla (gelecekte plaintext sizmasini onler).
 */
object CrashLogFormatter {

    private const val SECURITY_FILTER_TOKEN = "PLAINTEXT_FILTERED"

    /** ISO-8601 UTC zaman damgasi (test'lerde deterministik olabilmesi icin format isolated). */
    private val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    /**
     * @param throwable yakalanan exception
     * @param metadata cihaz/app/thread bilgisi
     * @param nowMs UTC milisaniye zaman damgasi (test'ten enjekte edilebilir)
     */
    fun format(
        throwable: Throwable,
        metadata: CrashMetadata,
        nowMs: Long = System.currentTimeMillis()
    ): String = buildString {
        appendLine("=== ELÇİM CRASH REPORT ===")
        appendLine("timestamp: ${isoFormat.format(Date(nowMs))}")
        appendLine("versionName: ${metadata.versionName}")
        appendLine("versionCode: ${metadata.versionCode}")
        appendLine("android: ${metadata.androidRelease} (SDK ${metadata.androidSdkInt})")
        appendLine("device: ${metadata.deviceModel}")
        appendLine("manufacturer: ${metadata.deviceManufacturer}")
        appendLine("thread: ${metadata.threadName}")
        appendLine()
        appendLine("--- STACK ---")
        appendLine(throwable.stackTraceFiltered())
    }

    /**
     * Crash dosyalarinin sirasi icin kullanilan epoch-ms tabanli filename.
     * Format: `crash_<epochMs>.txt`. Kronolojik sira icin alfasayisal sort ile dogal artar.
     */
    fun fileName(nowMs: Long = System.currentTimeMillis()): String = "crash_${nowMs}.txt"

    private fun Throwable.stackTraceFiltered(): String {
        val sw = StringWriter()
        printStackTrace(PrintWriter(sw))
        val raw = sw.toString()
        // Defansif: gelecekte plaintext'in exception mesajinda gozukmesi durumuna karsi.
        return raw.lineSequence()
            .filterNot { it.contains(SECURITY_FILTER_TOKEN) }
            .joinToString(System.lineSeparator())
    }
}

/** Cihaz + app + thread metadata. Application/runtime'dan derlenip CrashLogFormatter'a verilir. */
data class CrashMetadata(
    val versionName: String,
    val versionCode: Int,
    val androidRelease: String,
    val androidSdkInt: Int,
    val deviceModel: String,
    val deviceManufacturer: String,
    val threadName: String
)
