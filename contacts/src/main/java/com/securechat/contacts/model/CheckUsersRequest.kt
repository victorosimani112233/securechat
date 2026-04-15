package com.securechat.contacts.model

/**
 * Kullanici kesfi icin sunucuya gonderilen istek.
 * Yalnizca telefon numaralarinin SHA-256 hash'lerini icerir,
 * plaintext numara ASLA gonderilmez.
 */
data class CheckUsersRequest(
    val hashes: List<String>
)
