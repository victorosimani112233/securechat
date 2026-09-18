package com.securechat.signaling

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.security.SecureRandom
import java.util.Base64

/**
 * TURN sunucusu icin dinamik HMAC-SHA1 credential uretir. SHA-1 secimi genel
 * amacli bir imza tercihi degil, coturn `use-auth-secret` REST credential
 * wire formatiyla uyumluluk gerekliligidir.
 *
 * username = "{expiry}:{keyed-pseudonym}"
 * password = base64(hmac_sha1(TURN_SECRET, username))
 *
 * Iki gizlilik kisiti burada zorlanir:
 *
 *  1. **Relay TLS.** Duz `turn:` uzerinde STUN/TURN mesajlari sifresizdir;
 *     yol uzerindeki bir gozlemci username'i, relay adresini ve cagri
 *     zamanlamasini gorur. Medya zaten SRTP ile sifreli olsa da bu metadata
 *     kimin ne zaman aradigini ele verir. Production'da `turns:` zorunludur.
 *  2. **Sir rotasyonu.** Secret onceden `by lazy` ile surece sabitleniyordu;
 *     operator secret dosyasini degistirse bile sunucu yeniden baslatilana
 *     kadar eski siri kullaniyordu — pratikte rotasyon hic yapilmiyordu.
 *     Deger artik kisa araliklarla yeniden okunur, restart gerekmez.
 */
object TurnCredentialService {

    /** Rotasyon sonrasi yeni sirrin devreye girmesi icin ust sinir. */
    internal const val SECRET_REFRESH_MILLIS = 60_000L
    internal const val SECRET_STALE_GRACE_MILLIS = 300_000L

    private const val DEFAULT_TLS_PORT = 5349

    private val secretLock = Any()

    @Volatile
    private var cachedSecret: String? = null

    @Volatile
    private var cachedAtNanos: Long = 0

    private val random = SecureRandom()

    data class IceConfig(
        val iceServers: List<IceServer>,
        val ttl: Long
    )

    data class IceServer(
        val urls: String,
        val username: String? = null,
        val credential: String? = null
    )

    @Suppress("UNUSED_PARAMETER")
    fun generateConfig(userId: String): IceConfig {
        val ttlSeconds = ServerPrivacy.config.turnCredentialTtlSeconds
        val expiry = (System.currentTimeMillis() / 1000) + ttlSeconds
        // Her credential tek kullanimlik, rastgele bir etiket tasir. Kalici
        // keyed pseudonym TURN loglarinda ayni kullanicinin cagrilarini
        // birbirine baglanabilir hale getiriyordu.
        val opaqueUser = newOpaqueUserTag()
        val username = "$expiry:$opaqueUser"
        val credential = hmacSha1(secret(), username)

        return IceConfig(
            iceServers = iceServers(username, credential),
            ttl = ttlSeconds
        )
    }

    /**
     * URL listesini uretir.
     *
     * `turns:` her zaman once gelir; istemci ilk calisan adayi tercih eder.
     * Duz `turn:` yalniz production disinda ve acikca izin verilmisse eklenir.
     */
    internal fun iceServers(
        username: String,
        credential: String,
        environment: Map<String, String> = System.getenv(),
    ): List<IceServer> {
        val host = requireHost(environment)
        val stunPort = port(environment["TURN_PORT"], 3478, "TURN_PORT")
        val tlsHost = environment["TURN_TLS_HOST"]?.trim()?.takeIf { it.isNotBlank() } ?: host
        val tlsPort = port(environment["TURN_TLS_PORT"], DEFAULT_TLS_PORT, "TURN_TLS_PORT")
        val production = isProduction(environment)
        val plaintextAllowed = !production &&
            environment["TURN_ALLOW_PLAINTEXT"]?.equals("true", ignoreCase = true) == true

        val servers = mutableListOf<IceServer>()
        servers += IceServer(urls = "stun:$host:$stunPort")
        // TLS relay: TCP ve UDP (DTLS) ayri adaylar olarak sunulur.
        servers += IceServer(
            urls = "turns:$tlsHost:$tlsPort?transport=tcp",
            username = username,
            credential = credential,
        )
        servers += IceServer(
            urls = "turns:$tlsHost:$tlsPort?transport=udp",
            username = username,
            credential = credential,
        )
        if (plaintextAllowed) {
            servers += IceServer(
                urls = "turn:$host:$stunPort",
                username = username,
                credential = credential,
            )
        }
        return servers
    }

    private fun requireHost(environment: Map<String, String>): String {
        val host = environment["TURN_HOST"]?.trim().orEmpty()
        // Kaynak koda gomulu bir IP fallback'i, yanlis yapilandirilmis bir
        // dagitimda sessizce baska bir operatorun relay'ine yonlendirirdi.
        require(host.isNotBlank()) { "TURN_HOST is required" }
        require(host.none { it.isWhitespace() } && '/' !in host && '@' !in host) {
            "TURN_HOST is malformed"
        }
        return host
    }

    private fun port(raw: String?, fallback: Int, name: String): Int {
        val value = raw?.trim()?.takeIf { it.isNotBlank() } ?: return fallback
        val parsed = value.toIntOrNull()
        require(parsed != null && parsed in 1..65_535) { "$name is out of range" }
        return parsed
    }

    private fun isProduction(environment: Map<String, String>): Boolean =
        environment["PRIVACY_PRODUCTION_MODE"]?.equals("true", ignoreCase = true) == true

    internal fun newOpaqueUserTag(): String = ByteArray(16).also(random::nextBytes).let {
        Base64.getUrlEncoder().withoutPadding().encodeToString(it)
    }

    /**
     * Rotasyonu goren secret okuyucu.
     *
     * Okuma hatasi sonrasi eski deger korunur: secret dosyasi bir an icin
     * yeniden yazilirken (kismi write) TURN'un tamamen bozulmasi, sirri
     * rotasyonsuz birakmaktan daha kotu bir sonuc olurdu.
     */
    private fun secret(nowNanos: Long = System.nanoTime()): String {
        val current = cachedSecret
        val refreshNanos = SECRET_REFRESH_MILLIS * 1_000_000
        val graceNanos = SECRET_STALE_GRACE_MILLIS * 1_000_000
        if (current != null && nowNanos - cachedAtNanos < refreshNanos) return current
        synchronized(secretLock) {
            val existing = cachedSecret
            if (existing != null && nowNanos - cachedAtNanos < refreshNanos) return existing
            val fresh = try {
                PurposeSeparatedSecrets.validatedValue("TURN_SECRET")
            } catch (error: Exception) {
                if (existing != null && nowNanos - cachedAtNanos <= graceNanos) {
                    return existing
                }
                throw error
            }
            cachedSecret = fresh
            cachedAtNanos = nowNanos
            return fresh
        }
    }

    internal fun hmacSha1(secret: String, data: String): String {
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA1"))
        val hash = mac.doFinal(data.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(hash)
    }
}
