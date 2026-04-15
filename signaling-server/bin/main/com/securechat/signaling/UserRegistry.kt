package com.securechat.signaling

import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

data class RegisteredUser(
    val userId: String,
    val phoneHash: String,
    val registeredAt: Long = System.currentTimeMillis()
)

class UserRegistry {

    // phoneHash -> RegisteredUser
    private val users = ConcurrentHashMap<String, RegisteredUser>()

    init {
        // Demo kullanicilar (DemoDataSeeder ile eslesir)
        seedDemoUsers()
    }

    fun registerUser(userId: String, phoneNumber: String): RegisteredUser {
        val hash = hashPhone(phoneNumber)
        val user = RegisteredUser(userId = userId, phoneHash = hash)
        users[hash] = user
        println("[R] Kullanici kaydedildi: $userId ($hash)")
        return user
    }

    fun checkRegisteredHashes(hashes: List<String>): List<RegisteredUser> {
        return hashes.mapNotNull { hash -> users[hash] }
    }

    fun getUserCount(): Int = users.size

    private fun seedDemoUsers() {
        // Bu hash'ler gercek telefon numaralarinin SHA-256'sidir
        // Android client'taki DemoDataSeeder'daki numaralarla eslesir
        val demoUsers = listOf(
            "user_ahmet" to "+905551234567",
            "user_ayse" to "+905559876543",
            "user_mehmet" to "+905553456789",
            "user_fatma" to "+905557654321",
        )

        demoUsers.forEach { (userId, phone) ->
            registerUser(userId, phone)
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
