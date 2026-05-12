package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("FcmTokenStore")

/**
 * FCM token yonetimi — PostgreSQL persistent + in-memory cache.
 * Sunucu restart sonrasi token'lar korunur.
 *
 * GUVENLIK (H7 fix): Token'lar AES-256-GCM ile sifrelenmis halde DB'ye yazilir.
 * DB breach durumunda token'lar plaintext olarak ele gecmez (push spoofing onlenir).
 * Encryption key env'den (FCM_TOKEN_ENCRYPTION_KEY) — 32 byte base64 zorunlu.
 *
 * Migration: Eski plaintext token'lar okumada decrypt fail eder. Bu durumda token
 * plaintext olarak DB'de saklanmis demektir; bir sonraki FCM token rotation'da
 * client re-register edilince sifrelenmis yazilir. Loglanir.
 */
class FcmTokenStore {

    // In-memory cache — hizli lookup (plaintext)
    private val tokens = ConcurrentHashMap<String, String>()

    private val encryptionKey: SecretKeySpec by lazy {
        val raw = System.getenv("FCM_TOKEN_ENCRYPTION_KEY")
            ?: error(
                "FCM_TOKEN_ENCRYPTION_KEY env tanimlanmamis. " +
                "Production'da 32 byte base64-encoded random key zorunlu (openssl rand -base64 32). " +
                "Plaintext FCM token saklamak DB breach durumunda push spoofing'e izin verir."
            )
        val keyBytes = Base64.getDecoder().decode(raw)
        check(keyBytes.size == 32) {
            "FCM_TOKEN_ENCRYPTION_KEY 32 byte (256 bit) olmali — su anki: ${keyBytes.size}"
        }
        SecretKeySpec(keyBytes, "AES")
    }

    init {
        loadFromDb()
    }

    fun registerToken(userId: String, token: String) {
        tokens[userId] = token
        upsertToDb(userId, token)
        log.info("[FCM] Token kaydedildi: $userId")
    }

    fun removeToken(userId: String) {
        tokens.remove(userId)
        deleteFromDb(userId)
        log.info("[FCM] Token silindi: $userId")
    }

    fun getToken(userId: String): String? = tokens[userId]

    fun getTokenCount(): Int = tokens.size

    // --- AES-256-GCM sifreleme ---

    /** Plaintext token → "v2:" + base64(IV + ciphertext + GCM tag). */
    private fun encrypt(plaintext: String): String {
        val iv = ByteArray(12)
        SecureRandom().nextBytes(iv)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey, GCMParameterSpec(128, iv))
        val ct = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val packed = ByteArray(iv.size + ct.size)
        System.arraycopy(iv, 0, packed, 0, iv.size)
        System.arraycopy(ct, 0, packed, iv.size, ct.size)
        return "v2:" + Base64.getEncoder().encodeToString(packed)
    }

    /** "v2:" prefix'li sifreli string → plaintext token. Eski plaintext format icin null doner. */
    private fun decrypt(stored: String): String? {
        if (!stored.startsWith("v2:")) return null  // legacy plaintext
        return try {
            val packed = Base64.getDecoder().decode(stored.removePrefix("v2:"))
            val iv = packed.copyOfRange(0, 12)
            val ct = packed.copyOfRange(12, packed.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, encryptionKey, GCMParameterSpec(128, iv))
            String(cipher.doFinal(ct), Charsets.UTF_8)
        } catch (e: Exception) {
            log.warn("[!] FCM token decrypt hatasi (corrupted veya yanlis key): ${e.message}")
            null
        }
    }

    // --- DB islemleri ---

    private fun upsertToDb(userId: String, token: String) {
        try {
            val encrypted = encrypt(token)
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "INSERT INTO fcm_tokens (user_id, token, updated_at) VALUES (?::uuid, ?, NOW()) ON CONFLICT (user_id) DO UPDATE SET token = EXCLUDED.token, updated_at = NOW()"
                ).use { stmt ->
                    stmt.setString(1, userId)
                    stmt.setString(2, encrypted)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            log.warn("[!] FcmTokenStore DB upsert hatasi: ${e.message}")
        }
    }

    private fun deleteFromDb(userId: String) {
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement("DELETE FROM fcm_tokens WHERE user_id = ?::uuid").use { stmt ->
                    stmt.setString(1, userId)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            log.warn("[!] FcmTokenStore DB delete hatasi: ${e.message}")
        }
    }

    private fun loadFromDb() {
        try {
            Database.getConnection().use { conn ->
                conn.createStatement().use { stmt ->
                    val rs = stmt.executeQuery("SELECT user_id, token FROM fcm_tokens")
                    var count = 0
                    var legacyCount = 0
                    while (rs.next()) {
                        val uid = rs.getString("user_id")
                        val stored = rs.getString("token") ?: continue
                        val plaintext = decrypt(stored)
                        if (plaintext != null) {
                            tokens[uid] = plaintext
                            count++
                        } else if (!stored.startsWith("v2:")) {
                            // Legacy plaintext token — kullaniyoruz ama re-encrypt edip yaziyoruz
                            tokens[uid] = stored
                            upsertToDb(uid, stored)
                            legacyCount++
                            count++
                        }
                    }
                    log.info("[FCM] DB'den $count token yuklendi (legacy migrated: $legacyCount)")
                }
            }
        } catch (e: Exception) {
            log.warn("[!] FcmTokenStore DB'den yuklenemedi: ${e.message}")
        }
    }
}
