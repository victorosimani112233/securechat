package com.securechat.common

/**
 * Kullanıcı kimlik bilgisi sağlayıcısı interface'i.
 *
 * Bu interface, farklı modüllerin app modülüne direkt bağımlılık olmasını
 * önleyerek clean architecture prensiplerini korur.
 */
interface UserIdentityProvider {

    /**
     * Mevcut kullanıcının ID'sini döndürür.
     * Kullanıcı giriş yapmamışsa null döner.
     */
    val currentUserId: String?
}