package com.securechat.contacts

import com.securechat.contacts.model.CheckUsersRequest
import com.securechat.contacts.model.CheckUsersResponse
import com.securechat.contacts.model.RegisterUserRequest
import com.securechat.contacts.model.RegisterUserResponse
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

    @POST("api/v1/users/register")
    suspend fun registerUser(
        @Body request: RegisterUserRequest
    ): RegisterUserResponse
}
