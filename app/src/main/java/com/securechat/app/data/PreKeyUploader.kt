package com.securechat.app.data

import android.util.Log
import com.securechat.app.BuildConfig
import com.securechat.crypto.PreKeyManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Signal Protocol PreKey bundle'i sunucuya yukler.
 * AuthInterceptor uzerinden token ile cagrilir (injected OkHttpClient).
 */
@Singleton
class PreKeyUploader @Inject constructor(
    private val preKeyManager: PreKeyManager,
    private val okHttpClient: OkHttpClient
) {
    private val baseUrl = BuildConfig.API_BASE_URL
    private val jsonType = "application/json".toMediaType()
    private val encoder = Base64.getEncoder()

    /** Initial bundle yukle — kayit sonrasi tek seferlik. */
    suspend fun uploadInitialBundle(): Boolean = withContext(Dispatchers.IO) {
        try {
            val bundle = preKeyManager.generateAndSerializeInitialBundle()
            val body = JSONObject().apply {
                put("identityPublicKey", encoder.encodeToString(bundle.identityPublicKey))
                put("registrationId", bundle.registrationId)
                put("signedPreKeyId", bundle.signedPreKeyId)
                put("signedPreKey", encoder.encodeToString(bundle.signedPreKey))
                put("signedPreKeySignature", encoder.encodeToString(bundle.signedPreKeySignature))
                put("oneTimePreKeys", JSONArray().apply {
                    bundle.oneTimePreKeys.forEach { otpk ->
                        put(JSONObject().apply {
                            put("keyId", otpk.keyId)
                            put("publicKey", encoder.encodeToString(otpk.publicKey))
                        })
                    }
                })
            }.toString().toRequestBody(jsonType)

            val req = Request.Builder()
                .url("$baseUrl/api/v1/prekeys/upload")
                .post(body)
                .build()
            okHttpClient.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) {
                    Log.d("PreKeyUploader", "Initial bundle yuklendi (${bundle.oneTimePreKeys.size} OTPK)")
                    true
                } else {
                    Log.w("PreKeyUploader", "Upload basarisiz: ${resp.code}")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e("PreKeyUploader", "Upload hatasi: ${e.message}")
            false
        }
    }

    /** OTPK havuzu azalmissa yeni batch uretip yukle. */
    suspend fun replenishOneTimePreKeysIfNeeded(): Boolean = withContext(Dispatchers.IO) {
        try {
            val newBatch = preKeyManager.buildSerializedReplenishBatch() ?: return@withContext true
            val arr = JSONArray().apply {
                newBatch.forEach { otpk ->
                    put(JSONObject().apply {
                        put("keyId", otpk.keyId)
                        put("publicKey", encoder.encodeToString(otpk.publicKey))
                    })
                }
            }
            val req = Request.Builder()
                .url("$baseUrl/api/v1/prekeys/refresh")
                .post(arr.toString().toRequestBody(jsonType))
                .build()
            okHttpClient.newCall(req).execute().use { resp ->
                if (resp.isSuccessful) {
                    Log.d("PreKeyUploader", "${newBatch.size} OTPK refresh edildi")
                    true
                } else {
                    Log.w("PreKeyUploader", "Refresh basarisiz: ${resp.code}")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e("PreKeyUploader", "Refresh hatasi: ${e.message}")
            false
        }
    }
}
