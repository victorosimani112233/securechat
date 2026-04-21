package com.securechat.app.data

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class UserSession @Inject constructor(
    @ApplicationContext context: Context
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("user_session", Context.MODE_PRIVATE)

    var userId: String?
        get() = prefs.getString("user_id", null)
        set(value) = prefs.edit().putString("user_id", value).apply()

    var displayName: String?
        get() = prefs.getString("display_name", null)
        set(value) = prefs.edit().putString("display_name", value).apply()

    var phoneNumber: String?
        get() = prefs.getString("phone_number", null)
        set(value) = prefs.edit().putString("phone_number", value).apply()

    var profilePhotoUri: String?
        get() = prefs.getString("profile_photo_uri", null)
        set(value) = prefs.edit().putString("profile_photo_uri", value).apply()

    var shareLastSeen: Boolean
        get() = prefs.getBoolean("share_last_seen", true)
        set(value) = prefs.edit().putBoolean("share_last_seen", value).apply()

    var fcmToken: String?
        get() = prefs.getString("fcm_token", null)
        set(value) = prefs.edit().putString("fcm_token", value).apply()

    val isLoggedIn: Boolean get() = userId != null

    fun login(name: String, phone: String) {
        // userId = rastgele UUID — telefon numarasiyla hicbir iliskisi yok
        // Sunucu sadece UUID gorur, gercek numara cihazda kalir
        userId = UUID.randomUUID().toString()
        displayName = name
        phoneNumber = phone
    }

    fun logout() {
        prefs.edit().clear().apply()
    }
}
