package com.securechat.contacts

import com.securechat.contacts.model.CheckUsersRequest
import com.securechat.contacts.model.RegisteredContact
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.entity.ContactEntity
import java.security.MessageDigest
import javax.inject.Inject
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
    private val apiService: DiscoveryApiService
) {
    /**
     * Cihaz rehberindeki numaralari hash'leyerek sunucuda kayitli kullanicilari bulur.
     * Eslesen kisiler ContactDao uzerinden yerel veritabanina kaydedilir.
     */
    suspend fun discoverRegisteredUsers(): List<RegisteredContact> {
        val deviceContacts = contactsProvider.getAllContacts()

        // Telefon numaralarini hash'le, hash -> DeviceContact eslesmesi olustur
        val hashMap = deviceContacts.associate { contact ->
            hashPhoneNumber(contact.phoneNumber) to contact
        }

        // Yalnizca hash'leri sunucuya gonder — plaintext numara GONDERILMEZ
        val response = apiService.checkRegisteredUsers(
            CheckUsersRequest(hashes = hashMap.keys.toList())
        )

        // Sunucudan donen hash'lerle eslesen cihaz kisilerini bul
        val registered = response.users.mapNotNull { serverUser ->
            val deviceContact = hashMap[serverUser.phoneHash] ?: return@mapNotNull null
            RegisteredContact(
                userId = serverUser.userId,
                displayName = deviceContact.displayName,
                phoneNumber = deviceContact.phoneNumber,
                phoneHash = serverUser.phoneHash,
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

        return registered
    }

    companion object {
        /**
         * Telefon numarasini SHA-256 ile hash'ler.
         * Sonuc 64 karakterlik hex string olarak doner.
         */
        fun hashPhoneNumber(phoneNumber: String): String {
            val digest = MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(phoneNumber.toByteArray(Charsets.UTF_8))
            return hash.joinToString("") { "%02x".format(it) }
        }
    }
}
