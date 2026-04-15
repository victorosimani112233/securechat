package com.securechat.contacts.model

/**
 * SecureChat'e kayitli olan kisi modeli.
 * Sunucudan gelen userId ile cihaz rehberindeki bilgiler eslestirilir.
 */
data class RegisteredContact(
    val userId: String,
    val displayName: String,
    val phoneNumber: String,
    val phoneHash: String,
    val avatarUri: String?
)
