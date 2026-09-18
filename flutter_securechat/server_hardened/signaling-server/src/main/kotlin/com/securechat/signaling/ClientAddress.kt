package com.securechat.signaling

import io.ktor.server.application.ApplicationCall
import io.ktor.server.plugins.origin
import io.ktor.server.request.header
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("ClientAddress")

/**
 * Rate limit kararlarinda kullanilan istemci adresi.
 *
 * Uygulama reverse proxy arkasinda calisir. Soket adresi bu durumda proxy'nin
 * adresidir: butun kullanicilar tek bir kimlik gibi gorunur ve IP basina
 * limitler ya anlamsizlasir ya da tek bir kotuye kullanim herkesin kotasini
 * yakar.
 *
 * Cozum `X-Forwarded-For` okumaktir, fakat bu header'a kosulsuz guvenmek daha
 * kotudur: her istemci basligi uydurup limiti tamamen atlayabilir. Bu yuzden
 * header yalniz **bilinen proxy adreslerinden** gelen baglantilarda kabul
 * edilir. Guvenilen liste bos ise header hic okunmaz.
 *
 * `TRUSTED_PROXIES` virgulle ayrilmis IP veya CIDR listesidir
 * (or. `127.0.0.1,10.0.0.0/8`).
 */
object ClientAddress {

    private val trusted: List<Cidr> by lazy { parseTrusted(System.getenv("TRUSTED_PROXIES")) }

    class Cidr(private val network: ByteArray, private val prefixBits: Int) {
        fun contains(address: ByteArray): Boolean {
            if (address.size != network.size) return false
            var remaining = prefixBits
            for (index in network.indices) {
                if (remaining <= 0) return true
                val bits = if (remaining >= 8) 8 else remaining
                val mask = (0xFF shl (8 - bits)) and 0xFF
                if ((address[index].toInt() and mask) != (network[index].toInt() and mask)) {
                    return false
                }
                remaining -= bits
            }
            return true
        }
    }

    /**
     * @param socketAddress baglantinin gercek uzak adresi
     * @param forwardedFor `X-Forwarded-For` basligi (varsa)
     * @return rate limit ve audit icin kullanilacak istemci kimligi
     */
    fun resolve(
        socketAddress: String,
        forwardedFor: String?,
        trustedProxies: List<Cidr> = trusted,
    ): String {
        if (forwardedFor.isNullOrBlank()) return socketAddress
        if (!isTrustedProxy(socketAddress, trustedProxies)) {
            // Guvenilmeyen bir kaynaktan gelen forwarded header yok sayilir.
            return socketAddress
        }
        // Zincirdeki en sagdaki guvenilmeyen adres gercek istemcidir; soldan
        // baslamak istemcinin uydurdugu girdileri kabul etmek olurdu.
        val chain = forwardedFor.split(',').map { it.trim() }.filter { it.isNotEmpty() }
        for (candidate in chain.asReversed()) {
            val normalized = normalize(candidate) ?: continue
            if (!isTrustedProxy(normalized, trustedProxies)) return normalized
        }
        return socketAddress
    }

    fun isTrustedProxy(address: String, trustedProxies: List<Cidr> = trusted): Boolean {
        if (trustedProxies.isEmpty()) return false
        val bytes = toBytes(address) ?: return false
        return trustedProxies.any { it.contains(bytes) }
    }

    internal fun parseTrusted(value: String?): List<Cidr> {
        if (value.isNullOrBlank()) {
            log.info("[Proxy] TRUSTED_PROXIES bos — forwarded header kabul edilmez")
            return emptyList()
        }
        return value.split(',').mapNotNull { entry ->
            val trimmed = entry.trim()
            if (trimmed.isEmpty()) return@mapNotNull null
            val slash = trimmed.indexOf('/')
            val host = if (slash < 0) trimmed else trimmed.substring(0, slash)
            val bytes = toBytes(host) ?: run {
                log.warn("[Proxy] Gecersiz TRUSTED_PROXIES girdisi yok sayildi")
                return@mapNotNull null
            }
            val prefix = if (slash < 0) {
                bytes.size * 8
            } else {
                trimmed.substring(slash + 1).toIntOrNull() ?: return@mapNotNull null
            }
            if (prefix !in 0..(bytes.size * 8)) return@mapNotNull null
            Cidr(bytes, prefix)
        }
    }

    private fun normalize(value: String): String? {
        // `host:port` ve IPv6 koseli parantez bicimleri temizlenir.
        val withoutBrackets = value.removePrefix("[").substringBefore(']')
        val candidate = if (withoutBrackets.count { it == ':' } == 1) {
            withoutBrackets.substringBefore(':')
        } else {
            withoutBrackets
        }
        return if (toBytes(candidate) != null) candidate else null
    }

    private val IPV4 = Regex("^((25[0-5]|2[0-4]\\d|1\\d{2}|[1-9]?\\d)\\.){3}(25[0-5]|2[0-4]\\d|1\\d{2}|[1-9]?\\d)$")
    private val IPV6 = Regex("^[0-9A-Fa-f:]{2,45}$")

    /**
     * Yalniz literal IP kabul edilir.
     *
     * `InetAddress.getByName` bir hostname verilirse DNS cozumlemesi yapar.
     * Deger saldirgan kontrolundeki bir header'dan geldigi icin bu, istek
     * basina disari cikan bir DNS sorgusu ve bloklayan bir cagri demektir.
     */
    private fun toBytes(address: String): ByteArray? {
        if (!IPV4.matches(address) && !(address.contains(':') && IPV6.matches(address))) {
            return null
        }
        return try {
            java.net.InetAddress.getByName(address).address
        } catch (_: Exception) {
            null
        }
    }
}

/**
 * Rate limit ve audit kararlarinda kullanilacak istemci adresi.
 *
 * Soket adresi proxy arkasinda proxy'nin adresidir; forwarded header ise
 * yalniz guvenilen bir proxy'den geldiginde dikkate alinir.
 */
fun ApplicationCall.clientAddress(): String =
    ClientAddress.resolve(
        socketAddress = request.origin.remoteAddress,
        forwardedFor = request.header("X-Forwarded-For"),
    )
