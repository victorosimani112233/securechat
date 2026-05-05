package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("UserRegistry")

data class RegisteredUser(
    val userId: String,
    val phoneHash: String,
    val encryptedPhone: String? = null,
    val registeredAt: Long = System.currentTimeMillis()
)

/**
 * Kullanici kayit ve sorgulama — PostgreSQL persistent.
 * In-memory cache ile hizli lookup saglar, DB ile senkron tutulur.
 */
class UserRegistry {

    // In-memory cache (hizli lookup icin — DB ile senkron)
    private val cacheByPhone = ConcurrentHashMap<String, RegisteredUser>()
    private val cacheByUserId = ConcurrentHashMap<String, RegisteredUser>()

    init {
        loadFromDb()
    }

    fun registerUserByHash(userId: String, phoneHash: String, encryptedPhone: String? = null): Pair<RegisteredUser, Boolean> {
        // Cache'den kontrol
        val existing = cacheByPhone[phoneHash]
        if (existing != null) {
            log.info("[R] Mevcut kullanici bulundu: ${existing.userId.take(8)}... (yeni UUID: ${userId.take(8)}... KULLANILMADI)")
            if (encryptedPhone != null && existing.encryptedPhone != encryptedPhone) {
                val updated = existing.copy(encryptedPhone = encryptedPhone)
                updateEncryptedPhone(existing.userId, encryptedPhone)
                cacheByPhone[phoneHash] = updated
                cacheByUserId[existing.userId] = updated
                return Pair(updated, false)
            }
            return Pair(existing, false)
        }

        // Yeni kayit — DB'ye yaz
        val user = RegisteredUser(userId = userId, phoneHash = phoneHash, encryptedPhone = encryptedPhone)
        insertUser(user)
        cacheByPhone[phoneHash] = user
        cacheByUserId[userId] = user
        log.info("[R] Yeni kullanici kaydedildi: ${userId.take(8)}... encPhone=${encryptedPhone != null}")
        return Pair(user, true)
    }

    fun getUserByUserId(userId: String): RegisteredUser? = cacheByUserId[userId]

    fun checkRegisteredHashes(hashes: List<String>): List<RegisteredUser> {
        return hashes.mapNotNull { hash -> cacheByPhone[hash] }
    }

    fun getUserCount(): Int = cacheByPhone.size

    // --- DB islemleri ---

    private fun insertUser(user: RegisteredUser) {
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "INSERT INTO users (user_id, phone_hash, encrypted_phone, registered_at) VALUES (?::uuid, ?, ?, ?) ON CONFLICT (phone_hash) DO NOTHING"
                ).use { stmt ->
                    stmt.setString(1, user.userId)
                    stmt.setString(2, user.phoneHash)
                    stmt.setString(3, user.encryptedPhone)
                    stmt.setLong(4, user.registeredAt)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            log.warn("[!] UserRegistry DB insert hatasi: ${e.message}")
        }
    }

    private fun updateEncryptedPhone(userId: String, encryptedPhone: String) {
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "UPDATE users SET encrypted_phone = ? WHERE user_id = ?::uuid"
                ).use { stmt ->
                    stmt.setString(1, encryptedPhone)
                    stmt.setString(2, userId)
                    stmt.executeUpdate()
                }
            }
        } catch (e: Exception) {
            log.warn("[!] UserRegistry DB update hatasi: ${e.message}")
        }
    }

    private fun loadFromDb() {
        try {
            Database.getConnection().use { conn ->
                conn.createStatement().use { stmt ->
                    val rs = stmt.executeQuery("SELECT user_id, phone_hash, encrypted_phone, registered_at FROM users")
                    var count = 0
                    while (rs.next()) {
                        val user = RegisteredUser(
                            userId = rs.getString("user_id"),
                            phoneHash = rs.getString("phone_hash"),
                            encryptedPhone = rs.getString("encrypted_phone"),
                            registeredAt = rs.getLong("registered_at")
                        )
                        cacheByPhone[user.phoneHash] = user
                        cacheByUserId[user.userId] = user
                        count++
                    }
                    log.info("[R] DB'den $count kullanici yuklendi")
                }
            }
        } catch (e: Exception) {
            log.warn("[!] UserRegistry DB'den yuklenemedi: ${e.message}")
        }
    }

    companion object {
        fun hashPhone(phoneNumber: String): String {
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(phoneNumber.toByteArray(Charsets.UTF_8))
            return hash.joinToString("") { "%02x".format(it) }
        }
    }
}
