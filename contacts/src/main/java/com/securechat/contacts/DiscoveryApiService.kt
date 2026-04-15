package com.securechat.contacts

import com.securechat.contacts.model.CheckUsersRequest
import com.securechat.contacts.model.CheckUsersResponse
import retrofit2.http.Body
import retrofit2.http.POST

/**
 * Kullanici kesfi API servisi.
 * Sunucuya yalnizca telefon numaralarinin hash'leri gonderilir,
 * plaintext numara ASLA gonderilmez.
 */
interface DiscoveryApiService {
    @POST("api/v1/users/check")
    suspend fun checkRegisteredUsers(
        @Body request: CheckUsersRequest
    ): CheckUsersResponse
}
