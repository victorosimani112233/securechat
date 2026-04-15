package com.securechat.contacts.model

/**
 * Sunucudan donen kayitli kullanici listesi.
 * Her kullanici icin userId ve eslesme saglayan phoneHash doner.
 */
data class CheckUsersResponse(
    val users: List<ServerUser>
)

/**
 * Sunucuda kayitli olan kullanici bilgisi.
 */
data class ServerUser(
    val userId: String,
    val phoneHash: String
)
