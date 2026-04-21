package com.securechat.signaling

import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

data class RegisteredUser(
    val userId: String,
    val phoneHash: String,
    val encryptedPhone: String? = null,
    val registeredAt: Long = System.currentTimeMillis()
)

class UserRegistry {

    // phoneHash -> RegisteredUser
    private val users = ConcurrentHashMap<String, RegisteredUser>()

    // userId -> RegisteredUser (hizli UUID lookup icin)
    private val usersByUserId = ConcurrentHashMap<String, RegisteredUser>()

    // Demo seed kaldirildi — sunucu temiz baslar

    /**
     * Kullaniciyi phoneHash ile kaydeder.
     * encryptedPhone: istemcide AES-GCM ile sifreli telefon numarasi (sunucu cozemez).
     * Sunucu plaintext telefon numarasini ASLA almaz.
     */
    fun registerUserByHash(userId: String, phoneHash: String, encryptedPhone: String? = null): RegisteredUser {
        val user = RegisteredUser(userId = userId, phoneHash = phoneHash, encryptedPhone = encryptedPhone)
        users[phoneHash] = user
        usersByUserId[userId] = user
        println("[R] Kullanici kaydedildi: ${userId.take(8)}... encPhone=${encryptedPhone != null}")
        return user
    }

    /**
     * UUID ile kullaniciyi bulur. Bilinmeyen kisi numara cozumlemesi icin.
     */
    fun getUserByUserId(userId: String): RegisteredUser? {
        return usersByUserId[userId]
    }

    fun checkRegisteredHashes(hashes: List<String>): List<RegisteredUser> {
        return hashes.mapNotNull { hash -> users[hash] }
    }

    fun getUserCount(): Int = users.size

    private fun seedDemoUsers() {
        // Demo kullanicilar — UUID ve normalize edilmis numaralarin hash'leri
        val demoUsers = listOf(
            Triple(UUID.randomUUID().toString(), "ahmet", "905551234567"),
            Triple(UUID.randomUUID().toString(), "ayse", "905559876543"),
            Triple(UUID.randomUUID().toString(), "mehmet", "905553456789"),
            Triple(UUID.randomUUID().toString(), "fatma", "905557654321"),
        )

        demoUsers.forEach { (uuid, name, phone) ->
            val hash = hashPhone(phone)
            registerUserByHash(uuid, hash)
        }
        println("[S] ${demoUsers.size} demo kullanici yuklendi")
    }

    companion object {
        fun hashPhone(phoneNumber: String): String {
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(phoneNumber.toByteArray(Charsets.UTF_8))
            return hash.joinToString("") { "%02x".format(it) }
        }
    }
}
