package com.securechat.contacts.model

/**
 * Kullanici kaydi icin sunucuya gonderilen istek.
 * userId: rastgele UUID
 * phoneHash: telefon numarasinin SHA-256 hash'i (plaintext numara GONDERILMEZ)
 */
data class RegisterUserRequest(
    val userId: String,
    val phoneHash: String
)

data class RegisterUserResponse(
    val userId: String,
    val phoneHash: String
)
