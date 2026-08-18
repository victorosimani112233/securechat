package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.security.PublicKey
import java.util.concurrent.atomic.AtomicReference
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("ServiceAccounts")

/**
 * Servis hesabi kimlik dogrulamasinin tek giris noktasi.
 *
 * `BOT_SERVICE_PUBLIC_KEY` verilmemisse servis kimligi tamamen kapalidir:
 * hicbir assertion kabul edilmez. Bu, kullanici trafigini etkilemez; yalniz
 * bot fail-closed calisamaz duruma gelir.
 *
 * Assertion'in `sub` degeri ayrica gercekten saglanmis servis hesabina
 * (`bot_identity.bot_user_id`) esit olmalidir. Boylece gecerli imzali bir
 * assertion baska bir UUID adina kullanilamaz.
 */
object ServiceAccounts {

    private const val CACHE_TTL_MS = 60_000L

    private val publicKeyRef = AtomicReference<PublicKey?>()
    private val publicKeyLoaded = AtomicReference(false)
    private val cachedSubject = AtomicReference<CachedSubject?>()

    private class CachedSubject(val userId: String?, val loadedAtMs: Long)

    val isEnabled: Boolean get() = publicKey() != null

    private fun publicKey(): PublicKey? {
        if (publicKeyLoaded.get()) return publicKeyRef.get()
        synchronized(this) {
            if (publicKeyLoaded.get()) return publicKeyRef.get()
            val configured = SecretSource.optional("BOT_SERVICE_PUBLIC_KEY")?.trim()
            val parsed = if (configured.isNullOrEmpty()) {
                null
            } else {
                try {
                    ServiceAssertion.parsePublicKey(configured)
                } catch (_: Exception) {
                    // Yanlis bicimli anahtar sessizce "servis kapali"ya
                    // donusmemeli; operator hatasi gorunur olmali.
                    throw IllegalStateException("BOT_SERVICE_PUBLIC_KEY gecersiz Ed25519 X.509 anahtari")
                }
            }
            publicKeyRef.set(parsed)
            publicKeyLoaded.set(true)
            log.info("[Service] Servis hesabi kimligi {}", if (parsed == null) "kapali" else "acik")
            return parsed
        }
    }

    /**
     * Assertion'i dogrular ve servis hesabinin user id'sini doner.
     * Gecersiz, kapsam disi veya saglanmamis servis hesabi icin null.
     */
    fun authenticate(assertion: String, scope: ServiceAssertion.Scope): String? {
        val key = publicKey() ?: return null
        val result = ServiceAssertion.verify(assertion, key, scope)
        if (result !is ServiceAssertion.Result.Accepted) return null
        val provisioned = provisionedSubject() ?: return null
        if (!provisioned.equals(result.subject, ignoreCase = true)) return null
        return provisioned
    }

    /** Test/rotation icin cache'i bosaltir. */
    internal fun reset() {
        publicKeyRef.set(null)
        publicKeyLoaded.set(false)
        cachedSubject.set(null)
    }

    private fun provisionedSubject(): String? {
        val cached = cachedSubject.get()
        val now = System.currentTimeMillis()
        if (cached != null && now - cached.loadedAtMs < CACHE_TTL_MS) return cached.userId
        val loaded = try {
            Database.getConnection().use { connection ->
                connection.prepareStatement(
                    "SELECT bot_user_id FROM bot_identity WHERE id = 1",
                ).use { statement ->
                    statement.executeQuery().use { rows ->
                        if (rows.next()) rows.getString("bot_user_id") else null
                    }
                }
            }
        } catch (_: Exception) {
            // Depolama hatasinda servis kimligi fail-closed olur.
            log.error("[Service] Servis hesabi okunamadi (fail-closed)")
            return null
        }
        cachedSubject.set(CachedSubject(loaded, now))
        return loaded
    }
}
