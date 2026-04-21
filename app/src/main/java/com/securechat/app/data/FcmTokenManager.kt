package com.securechat.app.data

import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import com.securechat.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import javax.inject.Inject
import javax.inject.Singleton

/**
 * FCM token yonetimi.
 * Token'i Firebase'den alir, sunucuya kaydeder ve yerel olarak saklar.
 * Her app acilisinda ve token yenilendiginde cagirilir.
 */
@Singleton
class FcmTokenManager @Inject constructor(
    private val userSession: UserSession,
    private val okHttpClient: OkHttpClient
) {
    private val apiBaseUrl = BuildConfig.API_BASE_URL

    /**
     * Mevcut FCM token'i alip sunucuya kaydeder.
     * App her acildiginda ve login sonrasi cagirilmali.
     */
    suspend fun registerTokenOnServer() {
        val userId = userSession.userId ?: return
        try {
            val token = FirebaseMessaging.getInstance().token.await()
            userSession.fcmToken = token
            sendTokenToServer(userId, token)
            Log.d("FcmTokenManager", "FCM token sunucuya kaydedildi")
        } catch (e: Exception) {
            Log.e("FcmTokenManager", "FCM token kaydi basarisiz: ${e.message}")
        }
    }

    /**
     * Yeni token geldiginde (onNewToken) sunucuya gonderir.
     */
    suspend fun onTokenRefreshed(newToken: String) {
        userSession.fcmToken = newToken
        val userId = userSession.userId ?: return
        try {
            sendTokenToServer(userId, newToken)
            Log.d("FcmTokenManager", "Yenilenen FCM token sunucuya kaydedildi")
        } catch (e: Exception) {
            Log.e("FcmTokenManager", "Yenilenen token kaydi basarisiz: ${e.message}")
        }
    }

    /**
     * Logout durumunda sunucudan token'i siler.
     */
    suspend fun unregisterTokenOnServer() {
        val userId = userSession.userId ?: return
        try {
            val json = JSONObject().apply {
                put("userId", userId)
            }
            val body = json.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("$apiBaseUrl/api/v1/fcm/unregister")
                .post(body)
                .build()

            withContext(Dispatchers.IO) {
                okHttpClient.newCall(request).execute().use { response ->
                    Log.d("FcmTokenManager", "Token unregister: ${response.code}")
                }
            }
            userSession.fcmToken = null
        } catch (e: Exception) {
            Log.e("FcmTokenManager", "Token silme basarisiz: ${e.message}")
        }
    }

    private suspend fun sendTokenToServer(userId: String, token: String) {
        val json = JSONObject().apply {
            put("userId", userId)
            put("fcmToken", token)
        }
        val body = json.toString().toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url("$apiBaseUrl/api/v1/fcm/register")
            .post(body)
            .build()

        withContext(Dispatchers.IO) {
            okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w("FcmTokenManager", "Token kaydi HTTP hatasi: ${response.code}")
                }
            }
        }
    }
}
