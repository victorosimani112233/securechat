package com.securechat.app.resolver

import com.securechat.contacts.ContactRepository
import com.securechat.contacts.PhoneEncryptor
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.resolver.ContactNameResolver
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * ContactNameResolver implementasyonu.
 * Oncelik: contacts DB → rehber → sunucudan sifreli numara → fallback UUID
 */
@Singleton
class ContactNameResolverImpl @Inject constructor(
    private val contactRepository: ContactRepository,
    private val contactDao: ContactDao,
    @Named("apiBaseUrl") private val apiBaseUrl: String
) : ContactNameResolver {

    override suspend fun resolveDisplayName(userId: String): String {
        return try {
            // 1. UUID ile contacts DB'de ara (discovery sonrasi kaydedilmis)
            val contact = contactDao.getById(userId)
            if (contact != null && contact.displayName.isNotBlank()) {
                return contact.displayName
            }

            // 2. Telefon numarasi olabilir — rehberde ara
            val phoneName = contactRepository.getDisplayNameForPhoneNumber(userId)
            if (phoneName != userId && phoneName.isNotBlank()) {
                return phoneName
            }

            // 3. Sunucudan sifreli telefon numarasini cek ve coz
            val phone = fetchAndDecryptPhone(userId)
            if (phone != null) return phone

            userId
        } catch (e: Exception) {
            userId
        }
    }

    override suspend fun resolvePhoneNumber(userId: String): String {
        return try {
            // 1. Contacts DB'de telefon numarasi varsa onu kullan
            val contact = contactDao.getById(userId)
            if (contact != null && contact.phoneNumber.isNotBlank()) {
                return contact.phoneNumber
            }
            // 2. Sunucudan sifreli telefon numarasini cek
            val phone = fetchAndDecryptPhone(userId)
            if (phone != null) return phone
            // 3. Fallback: bos string
            ""
        } catch (_: Exception) { "" }
    }

    private suspend fun fetchAndDecryptPhone(userId: String): String? {
        return kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val url = "$apiBaseUrl/api/v1/users/$userId/phone"
                val request = okhttp3.Request.Builder().url(url).get().build()
                okhttp3.OkHttpClient().newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val body = response.body?.string() ?: return@use null
                        val json = org.json.JSONObject(body)
                        val encrypted = json.optString("encryptedPhone", "")
                        if (encrypted.isNotBlank()) {
                            val decrypted = PhoneEncryptor.decrypt(encrypted)
                            if (decrypted != null) formatPhone(decrypted) else null
                        } else null
                    } else null
                }
            } catch (_: Exception) { null }
        }
    }

    private fun formatPhone(digits: String): String {
        if (digits.length < 7) return "+$digits"
        if (digits.startsWith("90") && digits.length == 12) {
            return "+90 ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}"
        }
        return "+$digits"
    }
}