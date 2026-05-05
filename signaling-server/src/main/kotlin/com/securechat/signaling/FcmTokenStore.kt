package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.util.concurrent.ConcurrentHashMap
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("FcmTokenStore")

/**
 * FCM token yonetimi — PostgreSQL persistent + in-memory cache.
 * Sunucu restart sonrasi token'lar korunur.
 */
class FcmTokenStore {

    // In-memory cache — hizli lookup
    private val tokens = ConcurrentHashMap<String, String>()

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

    // --- DB islemleri ---

    private fun upsertToDb(userId: String, token: String) {
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "INSERT INTO fcm_tokens (user_id, token, updated_at) VALUES (?::uuid, ?, NOW()) ON CONFLICT (user_id) DO UPDATE SET token = EXCLUDED.token, updated_at = NOW()"
                ).use { stmt ->
                    stmt.setString(1, userId)
                    stmt.setString(2, token)
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
                    while (rs.next()) {
                        tokens[rs.getString("user_id")] = rs.getString("token")
                        count++
                    }
                    log.info("[FCM] DB'den $count token yuklendi")
                }
            }
        } catch (e: Exception) {
            log.warn("[!] FcmTokenStore DB'den yuklenemedi: ${e.message}")
        }
    }
}
