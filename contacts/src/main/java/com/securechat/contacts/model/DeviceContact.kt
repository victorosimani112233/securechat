package com.securechat.contacts.model

/**
 * Cihaz rehberinden okunan kisi modeli.
 * Telefon numarasi E.164 formatinda normalize edilmis olarak saklanir.
 */
data class DeviceContact(
    val id: String,
    val displayName: String,
    val phoneNumber: String, // E.164 format
    val avatarUri: String?
)
