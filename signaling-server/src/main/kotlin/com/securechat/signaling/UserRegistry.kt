package com.securechat.signaling

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

data class RegisteredUser(
    val userId: String,
    val phoneHash: String,
    val encryptedPhone: String? = null,
    val registeredAt: Long = System.currentTimeMillis()
)

@Serializable
private data class PersistedUser(
    val userId: String,
    val phoneHash: String,
    val encryptedPhone: String? = null,
    val registeredAt: Long = 0
)

class UserRegistry {

    // phoneHash -> RegisteredUser
    private val users = ConcurrentHashMap<String, RegisteredUser>()

    // userId -> RegisteredUser (hizli UUID lookup icin)
    private val usersByUserId = ConcurrentHashMap<String, RegisteredUser>()

    private val json = Json { ignoreUnknownKeys = true; prettyPrint = false }
    private val persistFile = File("user_registry.json")

    init {
        loadFromDisk()
    }

    /**
     * Kullaniciyi phoneHash ile kaydeder.
     * encryptedPhone: istemcide AES-GCM ile sifreli telefon numarasi (sunucu cozemez).
     * Sunucu plaintext telefon numarasini ASLA almaz.
     */
    /**
     * Mevcut phoneHash icin kayit varsa, mevcut kullaniciyi dondurur (yeni UUID olusturmaz).
     * Yoksa yeni kayit olusturur. isNew flag'i ile ayirt edilir.
     */
    fun registerUserByHash(userId: String, phoneHash: String, encryptedPhone: String? = null): Pair<RegisteredUser, Boolean> {
        // Ayni phoneHash ile kayitli kullanici varsa mevcut kaydi dondur
        val existing = users[phoneHash]
        if (existing != null) {
            println("[R] Mevcut kullanici bulundu: ${existing.userId.take(8)}... (yeni UUID: ${userId.take(8)}... KULLANILMADI)")
            // encryptedPhone guncellemesi yapilabilir (cihaz degisimi durumunda)
            if (encryptedPhone != null && existing.encryptedPhone != encryptedPhone) {
                val updated = existing.copy(encryptedPhone = encryptedPhone)
                users[phoneHash] = updated
                usersByUserId[existing.userId] = updated
                saveToDisk()
                return Pair(updated, false)
            }
            return Pair(existing, false)
        }

        // Yeni kayit
        val user = RegisteredUser(userId = userId, phoneHash = phoneHash, encryptedPhone = encryptedPhone)
        users[phoneHash] = user
        usersByUserId[userId] = user
        println("[R] Yeni kullanici kaydedildi: ${userId.take(8)}... encPhone=${encryptedPhone != null}")
        saveToDisk()
        return Pair(user, true)
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

    /**
     * Kayitli kullanicilari diske JSON olarak yazar.
     * Sunucu yeniden basladiginda veriler korunur.
     */
    private fun saveToDisk() {
        try {
            val list = users.values.map { u ->
                PersistedUser(u.userId, u.phoneHash, u.encryptedPhone, u.registeredAt)
            }
            persistFile.writeText(json.encodeToString(list))
        } catch (e: Exception) {
            println("[!] UserRegistry diske yazılamadı: ${e.message}")
        }
    }

    /**
     * Diskten kayitli kullanicilari yukler (sunucu restart sonrasi).
     */
    private fun loadFromDisk() {
        if (!persistFile.exists()) return
        try {
            val text = persistFile.readText()
            val list = json.decodeFromString<List<PersistedUser>>(text)
            list.forEach { p ->
                val user = RegisteredUser(p.userId, p.phoneHash, p.encryptedPhone, p.registeredAt)
                users[p.phoneHash] = user
                usersByUserId[p.userId] = user
            }
            println("[R] Diskten ${list.size} kullanici yuklendi")
        } catch (e: Exception) {
            println("[!] UserRegistry diskten okunamadı: ${e.message}")
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
