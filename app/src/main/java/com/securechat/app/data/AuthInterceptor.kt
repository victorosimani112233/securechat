package com.securechat.app.data

import android.util.Log
import com.securechat.app.BuildConfig
import dagger.Lazy
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.util.concurrent.locks.ReentrantLock
import javax.inject.Inject
import javax.inject.Singleton

/**
 * OkHttp interceptor — tum HTTP isteklerine Authorization header ekler ve
 * 401 alindiginda otomatik token refresh + retry yapar.
 *
 * Akis:
 *  1. Istek gonderilirken: header'a Authorization: Bearer <accessToken> eklenir.
 *  2. 401 donerse: refreshToken ile /auth/refresh cagirilir.
 *  3. Yeni token alinirsa: orijinal istek YENI access token ile retry edilir.
 *  4. Refresh fail ederse: kullanici tekrar oturum acmali (token'lar silinir).
 *
 * Thread safety:
 *  - Refresh thread-safe — birden fazla 401 ayni anda gelirse sadece bir tane refresh yapilir.
 *  - Diger threadler refresh'in tamamlanmasini bekler.
 */
@Singleton
class AuthInterceptor @Inject constructor(
    // Lazy: UserSession kendi OkHttpClient inject ettigi icin cycle olusur.
    // Interceptor ilk istek geldiginde UserSession'i resolve eder.
    private val userSessionLazy: Lazy<UserSession>
) : Interceptor {

    private val userSession: UserSession get() = userSessionLazy.get()

    private val refreshLock = ReentrantLock()
    @Volatile
    private var lastRefreshTimeMs = 0L
    private val MIN_REFRESH_INTERVAL_MS = 5_000L // Ayni token icin 5sn'de bir refresh

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()

        // Auth gerektirmeyen endpoint'ler — header eklemeden gec
        val path = original.url.encodedPath
        if (isPublicEndpoint(path)) {
            return chain.proceed(original)
        }

        // Mevcut token ile dene
        val accessToken = userSession.accessToken
        val authedRequest = if (!accessToken.isNullOrBlank()) {
            original.newBuilder().header("Authorization", "Bearer $accessToken").build()
        } else {
            original
        }

        var response = chain.proceed(authedRequest)

        // 401 → refresh + retry (sadece refresh endpoint'i degilse)
        if (response.code == 401 && path != "/api/v1/auth/refresh" && !accessToken.isNullOrBlank()) {
            response.close()
            val newToken = tryRefreshToken(accessToken)
            if (newToken != null) {
                Log.d("AuthInterceptor", "Token refreshed, retrying ${original.method} $path")
                val retryRequest = original.newBuilder()
                    .header("Authorization", "Bearer $newToken")
                    .build()
                response = chain.proceed(retryRequest)
            } else {
                Log.w("AuthInterceptor", "Token refresh basarisiz — kullanici yeniden giris yapmali")
                userSession.clearTokens()
                // Original 401 response'u dondur — caller handle eder
                val newRequest = original.newBuilder()
                    .header("Authorization", "Bearer $accessToken")
                    .build()
                response = chain.proceed(newRequest)
            }
        }

        return response
    }

    /**
     * Public wrapper — WebSocket 1008 (token rejected) durumunda SignalingClient
     * tarafindan cagrilir. HTTP 401 akisi disinda manuel refresh tetikler.
     *
     * @return yeni access token veya null (refresh fail → kullanici tekrar login)
     */
    fun refreshNow(): String? {
        val stale = userSession.accessToken ?: return null
        return tryRefreshToken(stale)
    }

    /**
     * Refresh token ile yeni access+refresh ciftti al. Thread-safe — birden fazla concurrent
     * 401 ayni anda refresh tetiklemez; ilki refresh yapar, digerleri yeni token'i kullanir.
     */
    private fun tryRefreshToken(staleAccessToken: String): String? {
        val refreshToken = userSession.refreshToken ?: return null

        refreshLock.lock()
        try {
            // Son refresh kisa sure once yapildiysa sonucu kullan (concurrent 401 fix)
            val current = userSession.accessToken
            if (current != null && current != staleAccessToken &&
                System.currentTimeMillis() - lastRefreshTimeMs < MIN_REFRESH_INTERVAL_MS) {
                return current
            }

            val client = OkHttpClient() // Interceptor'siz client — recursion onlemi
            val body = JSONObject().put("refreshToken", refreshToken).toString()
                .toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url("${BuildConfig.API_BASE_URL}/api/v1/auth/refresh")
                .post(body)
                .build()

            return try {
                client.newCall(request).execute().use { resp ->
                    if (!resp.isSuccessful) {
                        Log.w("AuthInterceptor", "Refresh HTTP ${resp.code}")
                        return null
                    }
                    val json = JSONObject(resp.body?.string() ?: return null)
                    val newAccess = json.optString("accessToken")
                    val newRefresh = json.optString("refreshToken")
                    if (newAccess.isBlank() || newRefresh.isBlank()) return null
                    userSession.saveTokens(newAccess, newRefresh)
                    lastRefreshTimeMs = System.currentTimeMillis()
                    newAccess
                }
            } catch (e: Exception) {
                Log.e("AuthInterceptor", "Refresh hatasi: ${e.message}")
                null
            }
        } finally {
            refreshLock.unlock()
        }
    }

    /** Auth gerektirmeyen public endpoint'ler. */
    private fun isPublicEndpoint(path: String): Boolean {
        return path == "/health" ||
               path == "/" ||
               path == "/api/v1/users/register" ||
               path == "/api/v1/auth/refresh" ||
               path == "/api/v1/otp/request" ||
               path == "/api/v1/otp/verify"
    }
}
