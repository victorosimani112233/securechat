package com.securechat.app.data

import com.securechat.common.UserIdentityProvider
import javax.inject.Inject
import javax.inject.Singleton

/**
 * UserIdentityProvider'ın app modülü implementasyonu.
 * UserSession'dan kullanıcı ID'sini sağlar.
 */
@Singleton
class UserIdentityProviderImpl @Inject constructor(
    private val userSession: UserSession
) : UserIdentityProvider {

    override val currentUserId: String?
        get() = userSession.userId
}