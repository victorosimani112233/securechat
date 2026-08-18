package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory
import java.security.SecureRandom

private val log = LoggerFactory.getLogger("OtpService")

/**
 * E-posta tabanli OTP (One-Time Password) servisi.
 *
 * Akis:
 *   1. Client `/otp/request` ile e-posta gonderir.
 *   2. Sunucu rastgele 6 haneli OTP uretir, e-postaya gonderir, hash'ini Redis'te 10 dk saklar.
 *   3. Client `/otp/verify` ile e-posta + OTP gonderir.
 *   4. Sunucu eslesmeyi dogrularsa kisa omurlu (15 dk) "registration token" doner.
 *   5. Client bu token'i `/users/register` cagrisinda gonderir.
 *
 * Guvenlik:
 *   - OTP plaintext saklanmaz — SHA-256 hash + email salt.
 *   - Brute force korumasi: 5 yanlis deneme sonrasi OTP iptal.
 *   - Rate limit: dakikada 1 OTP/email.
 */
object OtpService {

    private val random = SecureRandom()
    private const val OTP_TTL_SECONDS = 600L // 10 dk
    private const val MAX_ATTEMPTS = 5

    /** Cooldown penceresi — ayni e-postaya art arda OTP uretilmesini engeller. */
    const val COOLDOWN_MILLIS = 60_000L

    /**
     * OTP olusturma: cooldown kontrolu ve yazma tek atomik adimda.
     *
     * Onceki akista cooldown ayri bir okumayla kontrol ediliyor, ardindan
     * ayri komutlarla yaziliyordu. Iki paralel istek ayni "cooldown gecti"
     * okumasini paylasip iki OTP uretebiliyordu; ayrica `DEL`/`HSET`/`EXPIRE`
     * arasinda hata olursa TTL'siz bir kayit kalabiliyordu.
     *
     * ARGV: hash, createdAt, ttlSeconds, cooldownMillis
     * Donus: 1 = olusturuldu, aksi halde kalan bekleme suresi (ms, negatif).
     */
    private val CREATE_OTP_SCRIPT = """
        local createdAt = redis.call('HGET', KEYS[1], 'created_at')
        if createdAt then
          local elapsed = tonumber(ARGV[2]) - tonumber(createdAt)
          if elapsed < tonumber(ARGV[4]) then
            return -(tonumber(ARGV[4]) - elapsed)
          end
        end
        redis.call('DEL', KEYS[1])
        redis.call('HSET', KEYS[1], 'hash', ARGV[1], 'attempts', '0', 'created_at', ARGV[2])
        redis.call('EXPIRE', KEYS[1], ARGV[3])
        return 1
    """.trimIndent()

    /** Cooldown nedeniyle uretilemedi; kalan sure milisaniye. */
    class OtpCooldownException(val remainingMillis: Long) : RuntimeException("OTP cooldown")

    /** OTP request — generates code, stores hash, returns code (caller will send via email). */
    fun generateOtp(email: String): String {
        val otp = String.format("%06d", random.nextInt(1_000_000))
        val key = otpKey(email)
        val hash = hashOtp(otp, email)
        val created = try {
            RedisManager.use { jedis ->
                jedis.eval(
                    CREATE_OTP_SCRIPT,
                    listOf(key),
                    listOf(
                        hash,
                        System.currentTimeMillis().toString(),
                        OTP_TTL_SECONDS.toString(),
                        COOLDOWN_MILLIS.toString(),
                    ),
                ) as? Long ?: 0L
            }
        } catch (e: Exception) {
            log.error("[OTP] Redis hatasi: {}", e.javaClass.simpleName)
            throw RuntimeException("OTP olusturulamadi")
        }
        if (created < 0) throw OtpCooldownException(-created)
        log.info("[OTP] Olusturuldu (TTL=${OTP_TTL_SECONDS}sn)")
        return otp
    }

    /**
     * OTP dogrular. Basarili ise iptal eder ve true doner.
     * 5 yanlis deneme sonrasi OTP silinir.
     */
    /**
     * Deneme hakkini atomik olarak tuketir ve saklanan hash'i doner.
     *
     * ARGV: maxAttempts. Donus: {"1", hash} veya {"-1", ""}.
     */
    private val CLAIM_ATTEMPT_SCRIPT = """
        local stored = redis.call('HGET', KEYS[1], 'hash')
        if not stored then
          return {'-1', ''}
        end
        local attempts = tonumber(redis.call('HGET', KEYS[1], 'attempts') or '0')
        if attempts >= tonumber(ARGV[1]) then
          redis.call('DEL', KEYS[1])
          return {'-1', ''}
        end
        redis.call('HINCRBY', KEYS[1], 'attempts', 1)
        return {'1', stored}
    """.trimIndent()

    /**
     * Yalniz beklenen hash halen duruyorsa OTP'yi tuketir.
     *
     * Ayni OTP ile paralel iki dogru deneme gelirse ikisi de hash'i okur,
     * fakat yalniz biri bu adimda silmeyi kazanir; digeri 0 alir. Boylece tek
     * OTP'den iki grant uretilemez.
     */
    private val CONSUME_OTP_SCRIPT = """
        local stored = redis.call('HGET', KEYS[1], 'hash')
        if stored and stored == ARGV[1] then
          redis.call('DEL', KEYS[1])
          return 1
        end
        return 0
    """.trimIndent()

    /**
     * OTP dogrular. Basarili ise iptal eder ve true doner.
     *
     * Onceki akis `HGETALL -> karsilastir -> DEL/HINCRBY` seklinde atomik
     * degildi: paralel iki dogru deneme ikisi de basarili sayilip iki grant
     * uretebiliyor, paralel yanlis denemeler ise deneme tavanini asabiliyordu.
     * Karsilastirma yine sabit zamanli olarak uygulama tarafinda yapilir;
     * durum gecisleri Redis'te atomiktir.
     */
    fun verifyOtp(email: String, providedOtp: String): Boolean {
        if (!providedOtp.matches(Regex("[0-9]{6}"))) return false
        val key = otpKey(email)
        return try {
            RedisManager.use { jedis ->
                @Suppress("UNCHECKED_CAST")
                val claim = jedis.eval(
                    CLAIM_ATTEMPT_SCRIPT,
                    listOf(key),
                    listOf(MAX_ATTEMPTS.toString()),
                ) as? List<Any?> ?: return@use false
                val status = claim.getOrNull(0)?.toString()
                if (status != "1") {
                    log.warn("[OTP] Deneme reddedildi — kayit yok veya tavan asildi")
                    return@use false
                }
                val storedHash = claim.getOrNull(1)?.toString().orEmpty()
                if (storedHash.isEmpty()) return@use false

                val providedHash = hashOtp(providedOtp, email)
                if (!constantTimeEquals(storedHash, providedHash)) {
                    log.warn("[OTP] Yanlis kod")
                    return@use false
                }
                val consumed = jedis.eval(
                    CONSUME_OTP_SCRIPT,
                    listOf(key),
                    listOf(storedHash),
                ) as? Long
                if (consumed == 1L) {
                    log.info("[OTP] Dogrulandi")
                    true
                } else {
                    // Paralel bir istek ayni OTP'yi zaten tuketti.
                    log.warn("[OTP] Tuketilmis OTP yeniden sunuldu")
                    false
                }
            }
        } catch (e: Exception) {
            log.error("[OTP] Verify hatasi: {}", e.javaClass.simpleName)
            false
        }
    }

    /** Bir e-postaya son ne zaman OTP gonderildi — rate-limit icin. */
    fun lastOtpAt(email: String): Long {
        return try {
            RedisManager.use { jedis ->
                val ts = jedis.hget(otpKey(email), "created_at")
                ts?.toLongOrNull() ?: 0L
            }
        } catch (_: Exception) { 0L }
    }

    private fun hashOtp(otp: String, email: String): String {
        return ServerPrivacy.blindIndex("otp-value", "${email.lowercase()}\u0000$otp")
    }

    private fun otpKey(email: String): String =
        "otp_v2:${ServerPrivacy.blindIndex("otp-address", email.trim().lowercase())}"

    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var result = 0
        for (i in a.indices) result = result or (a[i].code xor b[i].code)
        return result == 0
    }
}
