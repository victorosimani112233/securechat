package com.securechat.contacts

import com.securechat.contacts.model.RegisteredContact
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.entity.ContactEntity
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Kayitli kisiler uzerinde arama ve filtreleme islemleri.
 * ContactDao uzerinden reactive Flow ile sonuc doner.
 */
@Singleton
class ContactSearchManager @Inject constructor(
    private val contactDao: ContactDao
) {
    /**
     * Verilen sorgu metnine gore kayitli kisilerde arama yapar.
     * Isim veya telefon numarasinda eslesme arar.
     */
    fun searchContacts(query: String): Flow<List<RegisteredContact>> {
        return contactDao.search(query).map { entities ->
            entities.filter { it.isRegistered }.map { it.toRegisteredContact() }
        }
    }

    /**
     * Tum kayitli (SecureChat kullanan) kisileri doner.
     */
    fun getRegisteredContacts(): Flow<List<RegisteredContact>> {
        return contactDao.getRegistered().map { entities ->
            entities.map { it.toRegisteredContact() }
        }
    }
}

/**
 * ContactEntity'yi RegisteredContact modeline donusturur.
 */
fun ContactEntity.toRegisteredContact(): RegisteredContact {
    return RegisteredContact(
        userId = id,
        displayName = displayName,
        phoneNumber = phoneNumber,
        phoneHash = phoneHash,
        avatarUri = avatarUri
    )
}
