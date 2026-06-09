package com.securechat.app.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.securechat.app.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class UserSession @Inject constructor(
    @ApplicationContext context: Context,
    private val okHttpClient: OkHttpClient
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("user_session", Context.MODE_PRIVATE)

    private val apiBaseUrl = BuildConfig.API_BASE_URL

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

    /**
     * Sunucudan alinan JWT access token (1 saat TTL).
     * 401 alinca AuthInterceptor refreshToken ile yenisini alir.
     */
    var accessToken: String?
        get() = prefs.getString("access_token", null)
        set(value) = prefs.edit().putString("access_token", value).apply()

    /**
     * Refresh token (60 gun TTL). Sadece /auth/refresh icin kullanilir.
     * Token rotation: her refresh'te yeni refresh token gelir, eskisi blacklist'lenir.
     */
    var refreshToken: String?
        get() = prefs.getString("refresh_token", null)
        set(value) = prefs.edit().putString("refresh_token", value).apply()

    /** Tek atomic islemde access+refresh token guncelle. */
    fun saveTokens(access: String, refresh: String) {
        prefs.edit()
            .putString("access_token", access)
            .putString("refresh_token", refresh)
            .apply()
    }

    /** Token'lari temizle — logout veya refresh fail durumunda. */
    fun clearTokens() {
        prefs.edit().remove("access_token").remove("refresh_token").apply()
    }

    // accessToken kontrolu zorunlu: register basarisiz olup token alamadigimiz
    // durumda kullanicinin "logged in" zannedilip ConversationsScreen'e gonderilmesini
    // engeller. WebSocket connect token olmadan zaten 1008 reddedilir; UI'in da gercegi
    // yansitmasi icin isLoggedIn token gelmeden true donmemeli.
    val isLoggedIn: Boolean get() = userId != null && !accessToken.isNullOrBlank()

    fun login(name: String, phone: String) {
        // userId = rastgele UUID — telefon numarasiyla hicbir iliskisi yok
        // Sunucu sadece UUID gorur, gercek numara cihazda kalir
        userId = UUID.randomUUID().toString()
        displayName = name
        phoneNumber = phone
    }

    /**
     * Register basarisiz oldugunda cagrilir: login() ile yazilan kismi state'i temizler.
     * accessToken zaten yok — userId/name/phone'u silince isLoggedIn=false olur ve bir
     * sonraki acilis kullaniciyi auth ekranina geri gonderir. saveTokens(...) cagrildiysa
     * bu method cagrilmamalidir (basari yolu).
     */
    fun clearLoginState() {
        prefs.edit()
            .remove("user_id")
            .remove("display_name")
            .remove("phone_number")
            .remove("access_token")
            .remove("refresh_token")
            .apply()
    }

    /**
     * Oturumu kapatir. Sunucuya logout istegi gonderip JWT token'ini gecersiz kilar,
     * ardindan tum yerel oturum verilerini temizler.
     */
    suspend fun logout() {
        // Sunucuya logout istegi gonder — JWT token invalidasyonu
        val currentUserId = userId
        val token = accessToken
        if (currentUserId != null && !token.isNullOrBlank()) {
            try {
                val json = JSONObject().apply {
                    put("userId", currentUserId)
                }
                val body = json.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder()
                    .url("$apiBaseUrl/api/v1/auth/logout")
                    .addHeader("Authorization", "Bearer $token")
                    .post(body)
                    .build()

                withContext(Dispatchers.IO) {
                    okHttpClient.newCall(request).execute().use { response ->
                        Log.d("UserSession", "Logout API yaniti: ${response.code}")
                    }
                }
            } catch (e: Exception) {
                Log.e("UserSession", "Sunucu logout istegi basarisiz: ${e.message}")
            }
        }

        // Tum yerel oturum verilerini temizle (access token dahil)
        prefs.edit().clear().apply()
    }

    /**
     * Sunucuya hesap silme istegi gonderir.
     * @param userId Silinecek hesabin kullanici ID'si
     */
    suspend fun sendDeleteAccountRequest(userId: String) {
        val token = accessToken
        if (token.isNullOrBlank()) {
            Log.w("UserSession", "Access token yok — hesap silme atlandi")
            return
        }
        try {
            val json = JSONObject().apply {
                put("userId", userId)
            }
            val body = json.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$apiBaseUrl/api/v1/account/delete")
                .addHeader("Authorization", "Bearer $token")
                .post(body)
                .build()

            withContext(Dispatchers.IO) {
                okHttpClient.newCall(request).execute().use { response ->
                    Log.d("UserSession", "Hesap silme API yaniti: ${response.code}")
                }
            }
        } catch (e: Exception) {
            Log.e("UserSession", "Hesap silme istegi basarisiz: ${e.message}")
        }
    }
}
