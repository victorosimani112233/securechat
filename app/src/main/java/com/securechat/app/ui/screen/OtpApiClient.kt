package com.securechat.app.ui.screen

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

/**
 * OTP HTTP client — kayit oncesi cagrilir, henuz UserSession'da token yok.
 * Bu yuzden injected OkHttpClient yerine raw client kullanir (interceptor calistirmaz).
 */
internal object OtpApiClient {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(20, java.util.concurrent.TimeUnit.SECONDS)
        .build()
    private val jsonType = "application/json".toMediaType()

    sealed class OtpResult {
        object Sent : OtpResult()
        object SmtpDisabled : OtpResult()
        object RateLimited : OtpResult()
        data class Error(val message: String) : OtpResult()
    }

    suspend fun requestOtp(apiBaseUrl: String, email: String): OtpResult = withContext(Dispatchers.IO) {
        try {
            val body = JSONObject().put("email", email).toString().toRequestBody(jsonType)
            val req = Request.Builder()
                .url("${apiBaseUrl.trimEnd('/')}/api/v1/otp/request")
                .post(body)
                .build()
            client.newCall(req).execute().use { resp ->
                when (resp.code) {
                    200 -> OtpResult.Sent
                    503 -> OtpResult.SmtpDisabled
                    429 -> OtpResult.RateLimited
                    else -> OtpResult.Error("HTTP ${resp.code}")
                }
            }
        } catch (e: Exception) {
            OtpResult.Error(e.message ?: "bilinmeyen hata")
        }
    }

    /** OTP'yi dogrulayip registrationToken doner; null ise hata. */
    suspend fun verifyOtp(apiBaseUrl: String, email: String, otp: String): String? = withContext(Dispatchers.IO) {
        try {
            val body = JSONObject().put("email", email).put("otp", otp).toString().toRequestBody(jsonType)
            val req = Request.Builder()
                .url("${apiBaseUrl.trimEnd('/')}/api/v1/otp/verify")
                .post(body)
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val json = JSONObject(resp.body?.string() ?: return@withContext null)
                if (!json.optBoolean("verified")) return@withContext null
                json.optString("registrationToken").takeIf { it.isNotBlank() }
            }
        } catch (_: Exception) { null }
    }
}
