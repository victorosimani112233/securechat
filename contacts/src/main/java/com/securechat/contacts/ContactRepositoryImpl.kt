package com.securechat.contacts

import com.securechat.contacts.model.DeviceContact
import com.securechat.contacts.model.RegisteredContact
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.entity.ContactEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ContactRepository implementasyonu.
 * DeviceContact'ları önbelleğe alır ve telefon numarası ile isim eşleştirmesi yapar.
 */
@Singleton
class ContactRepositoryImpl @Inject constructor(
    private val contactsProvider: ContactsProvider,
    private val contactDao: ContactDao
) : ContactRepository {

    // Cihaz kişilerini cache'ler
    private var cachedDeviceContacts: List<DeviceContact>? = null

    override suspend fun getAllDeviceContacts(): List<DeviceContact> {
        if (cachedDeviceContacts == null) {
            cachedDeviceContacts = contactsProvider.getAllContacts()
        }
        return cachedDeviceContacts ?: emptyList()
    }

    override fun getRegisteredContacts(): Flow<List<RegisteredContact>> {
        return contactDao.getRegistered().map { entities ->
            entities.map { it.toRegisteredContact() }
        }
    }

    override suspend fun findContactByPhoneNumber(phoneNumber: String): DeviceContact? {
        val allContacts = getAllDeviceContacts()

        // Önce tam eşleşme ara
        allContacts.find { it.phoneNumber == phoneNumber }?.let { return it }

        // E.164 formatına normalize et ve tekrar dene
        val normalizedQuery = contactsProvider.normalizePhoneNumber(phoneNumber)
        if (normalizedQuery != null) {
            allContacts.find { it.phoneNumber == normalizedQuery }?.let { return it }
        }

        // Son çare: numaranın sonundaki kısmı karşılaştır
        val cleanQuery = phoneNumber.replace("+", "").replace(" ", "").replace("-", "")
        return allContacts.find { contact ->
            val cleanContact = contact.phoneNumber.replace("+", "").replace(" ", "").replace("-", "")
            cleanContact.endsWith(cleanQuery.takeLast(7)) || cleanQuery.endsWith(cleanContact.takeLast(7))
        }
    }

    override suspend fun getDisplayNameForPhoneNumber(phoneNumber: String): String {
        // Önce cihaz rehberinde ara
        findContactByPhoneNumber(phoneNumber)?.let { contact ->
            return contact.displayName
        }

        // Bulunamazsa formatted numarayı döner
        return formatPhoneNumber(phoneNumber)
    }

    private fun formatPhoneNumber(phoneNumber: String): String {
        // Basit formatting: +90 533 123 45 67 formatında göster
        if (phoneNumber.startsWith("+90") && phoneNumber.length == 13) {
            return "+90 ${phoneNumber.substring(3, 6)} ${phoneNumber.substring(6, 9)} ${phoneNumber.substring(9, 11)} ${phoneNumber.substring(11)}"
        }
        return phoneNumber
    }
}

