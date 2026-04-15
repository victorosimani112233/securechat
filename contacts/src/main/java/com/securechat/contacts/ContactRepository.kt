package com.securechat.contacts

import com.securechat.contacts.model.DeviceContact
import com.securechat.contacts.model.RegisteredContact
import kotlinx.coroutines.flow.Flow

/**
 * Kişi işlemleri için repository interface'i.
 * Storage modülü ile doğrudan bağımlılık kurmadan kişi bilgilerine erişim sağlar.
 */
interface ContactRepository {

    /**
     * Tüm cihaz rehber kişilerini döner.
     */
    suspend fun getAllDeviceContacts(): List<DeviceContact>

    /**
     * Kayıtlı (SecureChat kullanan) kişileri döner.
     */
    fun getRegisteredContacts(): Flow<List<RegisteredContact>>

    /**
     * Verilen telefon numarasına göre kişi arar.
     * @param phoneNumber E.164 formatında telefon numarası
     * @return Bulunursa kişi bilgisi, bulunamazsa null
     */
    suspend fun findContactByPhoneNumber(phoneNumber: String): DeviceContact?

    /**
     * Telefon numarasından görüntüleme adını döner.
     * Önce rehberde arar, bulamazsa formatted numarayı döner.
     */
    suspend fun getDisplayNameForPhoneNumber(phoneNumber: String): String
}