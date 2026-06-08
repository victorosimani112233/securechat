package com.securechat.app.monitoring

/**
 * Crash + non-fatal exception raporlama abstraction.
 *
 * Default impl no-op — production'da Firebase Crashlytics (veya Sentry) ile
 * deg istirilir. Hilt module:
 *
 *   @Binds @Singleton abstract fun bindCrashReporter(impl: NoopCrashReporter): CrashReporter
 *
 * Crashlytics aktif olunca:
 *   class CrashlyticsCrashReporter @Inject constructor() : CrashReporter {
 *     override fun recordException(t: Throwable, ...) {
 *       FirebaseCrashlytics.getInstance().recordException(t)
 *     }
 *     override fun setCustomKey(key: String, value: String) {
 *       FirebaseCrashlytics.getInstance().setCustomKey(key, value)
 *     }
 *     ...
 *   }
 *
 * Kullanim — UseCase / ViewModel'de:
 *   try { ... } catch (e: Exception) {
 *     crashReporter.recordException(e, context = "SendMessage", metadata = mapOf("convId" to id))
 *     _snackbar.emit(ChatError.Unknown(e).userMessage)
 *   }
 *
 * GUVENLIK: Plaintext mesaj icerigi/key/token metadata'ya KOYULMAZ.
 * Sadece userId hash, conversationId, error tipi, ekran adi guvenli sayilir.
 */
interface CrashReporter {
    fun recordException(throwable: Throwable, context: String? = null, metadata: Map<String, String> = emptyMap())
    fun log(message: String)
    fun setCustomKey(key: String, value: String)
    fun setCustomKey(key: String, value: Int)
    fun setCustomKey(key: String, value: Boolean)
    fun setUserId(userId: String?)
}

/**
 * No-op default — Crashlytics yokken silently log'a yazar.
 * Hilt @Binds ile gercek impl'e degistirilir.
 */
class NoopCrashReporter @javax.inject.Inject constructor() : CrashReporter {
    override fun recordException(throwable: Throwable, context: String?, metadata: Map<String, String>) {
        val ctx = if (context != null) " [$context]" else ""
        val meta = if (metadata.isNotEmpty()) " meta=$metadata" else ""
        android.util.Log.w("CrashReporter", "Exception$ctx$meta", throwable)
    }

    override fun log(message: String) {
        android.util.Log.d("CrashReporter", message)
    }

    override fun setCustomKey(key: String, value: String) {
        android.util.Log.d("CrashReporter", "setKey $key=$value")
    }

    override fun setCustomKey(key: String, value: Int) {
        android.util.Log.d("CrashReporter", "setKey $key=$value")
    }

    override fun setCustomKey(key: String, value: Boolean) {
        android.util.Log.d("CrashReporter", "setKey $key=$value")
    }

    override fun setUserId(userId: String?) {
        android.util.Log.d("CrashReporter", "setUserId=${userId?.take(8)}...")
    }
}
