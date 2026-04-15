package com.securechat.app.resolver

import com.securechat.contacts.ContactRepository
import com.securechat.storage.resolver.ContactNameResolver
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ContactNameResolver implementasyonu.
 * Contacts modülündeki ContactRepository'yi kullanarak isim çözümlemesi yapar.
 */
@Singleton
class ContactNameResolverImpl @Inject constructor(
    private val contactRepository: ContactRepository
) : ContactNameResolver {

    override suspend fun resolveDisplayName(phoneNumber: String): String {
        return try {
            contactRepository.getDisplayNameForPhoneNumber(phoneNumber)
        } catch (e: Exception) {
            // Hata durumunda telefon numarasını döner
            formatPhoneNumber(phoneNumber)
        }
    }

    private fun formatPhoneNumber(phoneNumber: String): String {
        // Basit formatting: +90 533 123 45 67 formatında göster
        if (phoneNumber.startsWith("+90") && phoneNumber.length == 13) {
            return "+90 ${phoneNumber.substring(3, 6)} ${phoneNumber.substring(6, 9)} ${phoneNumber.substring(9, 11)} ${phoneNumber.substring(11)}"
        }
        return phoneNumber
    }
}