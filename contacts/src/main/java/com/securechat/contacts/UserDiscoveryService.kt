package com.securechat.contacts

import android.util.Log
import com.securechat.contacts.model.RegisteredContact
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.entity.ContactEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Gizlilik oncelikli kullanici kesfi servisi.
 * Telefon numaralarini SHA-256 ile hash'leyerek sunucuya gonderir,
 * plaintext numara ASLA sunucuya iletilmez.
 * Eslesen kullanicilar yerel veritabanina kaydedilir.
 */
@Singleton
class UserDiscoveryService @Inject constructor(
    private val contactsProvider: ContactsProvider,
    private val contactDao: ContactDao,
    @Named("apiBaseUrl") private val apiBaseUrl: String
) {
    private val client = OkHttpClient()
    private val jsonMediaType = "application/json".toMediaType()

    /** Auth token saglayici callback — UserSession'dan bagimsiz, app modulu set eder. */
    @Volatile
    var accessTokenProvider: () -> String? = { null }

    /**
     * Sunucuya hash listesi gonderip eslesen kullanicilari dondurur.
     * Retrofit/Gson yerine OkHttp + JSONObject kullanir — type erasure sorununu onler.
     */
    private suspend fun checkRegisteredUsersHttp(
        hashes: List<String>
    ): List<Pair<String, String>> = withContext(Dispatchers.IO) {
        val token = accessTokenProvider()
        if (token.isNullOrBlank()) {
            Log.w(TAG, "Access token yok — checkUsers atlandi")
            return@withContext emptyList()
        }
        val json = JSONObject().apply {
            put("hashes", JSONArray(hashes))
        }
        val body = json.toString().toRequestBody(jsonMediaType)
        val url = "${apiBaseUrl.trimEnd('/')}/api/v1/users/check"
        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer $token")
            .post(body)
            .build()

        client.newCall(request).execute().use { response ->
            val responseBody = response.body?.string()
            Log.d(TAG, "checkUsers: ${response.code}, body=${responseBody?.take(200)}")
            if (!response.isSuccessful || responseBody == null) {
                Log.e(TAG, "checkUsers basarisiz: ${response.code}")
                return@withContext emptyList()
            }
            val responseJson = JSONObject(responseBody)
            val usersArray = responseJson.optJSONArray("users") ?: return@withContext emptyList()
            (0 until usersArray.length()).map { i ->
                val user = usersArray.getJSONObject(i)
                user.getString("userId") to user.getString("phoneHash")
            }
        }
    }

    /**
     * Cihaz rehberindeki numaralari hash'leyerek sunucuda kayitli kullanicilari bulur.
     * Eslesen kisiler ContactDao uzerinden yerel veritabanina kaydedilir.
     */
    suspend fun discoverRegisteredUsers(): List<RegisteredContact> {
        val deviceContacts = contactsProvider.getAllContacts()
        Log.d(TAG, "Kesif basladi: ${deviceContacts.size} cihaz kisisi")

        // Telefon numaralarini hash'le, hash -> DeviceContact eslesmesi olustur
        val hashMap = deviceContacts.associate { contact ->
            hashPhoneNumber(contact.phoneNumber) to contact
        }
        Log.d(TAG, "Hash sayisi: ${hashMap.size}")

        // Yalnizca hash'leri sunucuya gonder — plaintext numara GONDERILMEZ
        val serverUsers = checkRegisteredUsersHttp(hashMap.keys.toList())
        Log.d(TAG, "Sunucu yaniti: ${serverUsers.size} eslesen kullanici")

        // Sunucudan donen hash'lerle eslesen cihaz kisilerini bul
        val registered = serverUsers.mapNotNull { (userId, phoneHash) ->
            val deviceContact = hashMap[phoneHash]
            if (deviceContact == null) {
                Log.w(TAG, "Sunucu hash eslesmedi: ${phoneHash.take(12)}...")
            }
            deviceContact ?: return@mapNotNull null
            RegisteredContact(
                userId = userId,
                displayName = deviceContact.displayName,
                phoneNumber = deviceContact.phoneNumber,
                phoneHash = phoneHash,
                avatarUri = deviceContact.avatarUri
            )
        }

        // Eslesen kisileri yerel veritabanina kaydet
        registered.forEach { contact ->
            contactDao.insert(
                ContactEntity(
                    id = contact.userId,
                    phoneNumber = contact.phoneNumber,
                    phoneHash = contact.phoneHash,
                    displayName = contact.displayName,
                    isRegistered = true,
                    avatarUri = contact.avatarUri
                )
            )
        }

        // Rehberden silinmis kisileri DB'den kaldir
        val devicePhoneHashes = hashMap.keys
        val existingContacts = contactDao.getAllOnce()
        existingContacts.forEach { existing ->
            if (existing.phoneHash !in devicePhoneHashes) {
                contactDao.delete(existing.id)
            }
        }

        Log.d(TAG, "Kayitli kisi sayisi: ${registered.size}")
        return registered
    }

    /**
     * Tek bir telefon numarasinin hash'ini sunucuda arar.
     * Eslesen kullanici varsa userId dondurur, yoksa null.
     */
    suspend fun resolvePhoneHash(phoneInput: String): String? {
        val digits = PhoneNumberNormalizer.normalizeDigits(phoneInput)
        val hash = hashPhoneNumber(digits)
        Log.d(TAG, "resolvePhone: input=$phoneInput, normalized=$digits, hash=${hash.take(12)}...")
        val results = checkRegisteredUsersHttp(listOf(hash))
        return results.firstOrNull()?.first
    }

    companion object {
        private const val TAG = "UserDiscovery"
        /**
         * Telefon numarasini SHA-256 ile hash'ler.
         * Once normalizeDigits ile standart formata cevirir (orn. "05551234567" -> "905551234567"),
         * boylece kayit, kesif ve arama hep ayni hash'i uretir.
         * Sonuc 64 karakterlik hex string olarak doner.
         */
        fun hashPhoneNumber(phoneNumber: String): String {
            val normalized = PhoneNumberNormalizer.normalizeDigits(phoneNumber)
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(normalized.toByteArray(Charsets.UTF_8))
            return hash.joinToString("") { "%02x".format(it) }
        }
    }
}
