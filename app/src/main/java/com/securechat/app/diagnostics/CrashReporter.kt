package com.securechat.app.diagnostics

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * Yakalanmamis exception'lari icin diske crash raporu yazar, kullanicinin
 * paylasimasina izin verir. Harici SDK (Sentry, Crashlytics) bagimliligi yok —
 * gizlilik-once mesajlasma uygulamasi icin telemetri minimumu.
 *
 * Akis:
 *   1. install(Context): Application.onCreate'ten cagrilir. Mevcut
 *      UncaughtExceptionHandler'i sarmalar.
 *   2. Crash olunca: metadata + stack trace -> CrashLogFormatter.format ->
 *      <filesDir>/crash_logs/crash_<epochMs>.txt. Sonra ZINCIRDEKI orijinal
 *      handler'a deleg eder (process zaten coker, biz sadece kayit aliriz).
 *   3. listCrashes(Context): saved dosyalar (en yeni once).
 *   4. shareLatestCrash(Context): ACTION_SEND intent + FileProvider URI ile
 *      kullanicinin mail/Drive/Slack ile gonderebilmesini saglar.
 *   5. clearAll(Context): tum loglari siler (kullanici reset secebilir).
 *
 * GUVENLIK: Mesaj icerigi loglanmaz — CrashLogFormatter SECURITY_FILTER_TOKEN
 * filtresi var. Log dosyalari app-private dir'da; FileProvider ile share edilince
 * gecici URI permission verir.
 */
object CrashReporter {

    private const val TAG = "CrashReporter"
    private const val CRASH_DIR = "crash_logs"
    private const val MAX_FILES = 20

    @Volatile
    private var installed = false

    /** Application onCreate'te cagrilir. Tekrarli cagri no-op. */
    @Synchronized
    fun install(context: Context) {
        if (installed) return
        installed = true
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                writeCrashFile(appContext, thread, throwable)
            } catch (t: Throwable) {
                Log.e(TAG, "Crash dosyasi yazimi basarisiz: ${t.message}", t)
            }
            // Zincirle: orijinal handler'a (genelde Android process killer) deleg et.
            previous?.uncaughtException(thread, throwable)
        }
        Log.d(TAG, "CrashReporter yuklendi")
    }

    private fun writeCrashFile(context: Context, thread: Thread, throwable: Throwable) {
        val dir = crashDir(context)
        if (!dir.exists()) dir.mkdirs()

        val nowMs = System.currentTimeMillis()
        val metadata = collectMetadata(context, thread)
        val payload = CrashLogFormatter.format(throwable, metadata, nowMs)
        val file = File(dir, CrashLogFormatter.fileName(nowMs))
        file.writeText(payload)

        // Rotation: en eski dosyalari sil, max MAX_FILES tut.
        trimOldFiles(dir)
    }

    private fun collectMetadata(context: Context, thread: Thread): CrashMetadata {
        val pkgInfo = try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
        @Suppress("DEPRECATION")
        val versionCode = pkgInfo?.versionCode ?: -1
        return CrashMetadata(
            versionName = pkgInfo?.versionName ?: "unknown",
            versionCode = versionCode,
            androidRelease = Build.VERSION.RELEASE ?: "unknown",
            androidSdkInt = Build.VERSION.SDK_INT,
            deviceModel = Build.MODEL ?: "unknown",
            deviceManufacturer = Build.MANUFACTURER ?: "unknown",
            threadName = thread.name ?: "unknown"
        )
    }

    private fun trimOldFiles(dir: File) {
        val files = dir.listFiles { f -> f.name.startsWith("crash_") && f.name.endsWith(".txt") }
            ?: return
        if (files.size <= MAX_FILES) return
        files.sortedBy { it.lastModified() }
            .take(files.size - MAX_FILES)
            .forEach { it.delete() }
    }

    private fun crashDir(context: Context): File = File(context.filesDir, CRASH_DIR)

    /** En yeni once siralanmis crash dosyalari. UI/diagnostics ekrani icin. */
    fun listCrashes(context: Context): List<File> {
        val dir = crashDir(context.applicationContext)
        val files = dir.listFiles { f -> f.name.startsWith("crash_") && f.name.endsWith(".txt") }
            ?: return emptyList()
        return files.sortedByDescending { it.lastModified() }
    }

    /**
     * En son crash log'unu kullaniciya share intent ile sunar. Yoksa false.
     * FileProvider authority: `${packageName}.fileprovider` — manifest'te tanimli.
     */
    fun shareLatestCrash(context: Context): Boolean {
        val latest = listCrashes(context).firstOrNull() ?: return false
        return try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                latest
            )
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_SUBJECT, "ELÇİM crash raporu")
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(Intent.createChooser(send, "Crash raporu paylas").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            true
        } catch (t: Throwable) {
            Log.e(TAG, "Share basarisiz: ${t.message}", t)
            false
        }
    }

    /** Tum kayitli crashleri siler. */
    fun clearAll(context: Context): Int {
        val files = listCrashes(context)
        files.forEach { it.delete() }
        return files.size
    }
}
