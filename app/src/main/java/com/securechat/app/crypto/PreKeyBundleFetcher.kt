package com.securechat.app.crypto

import android.util.Log
import com.securechat.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.ecc.Curve
import org.whispersystems.libsignal.state.PreKeyBundle
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Recipient'in PreKeyBundle'ini signaling-server'dan ceker.
 * GET /api/v1/users/{userId}/prekeys
 *
 * NOT: Bundle CACHE'LENMEZ — her yeni session establishment'ta fresh fetch.
 * Recipient'in one-time prekey havuzu sirayla tuketildigi icin cache stale
 * olur ve "Bad message" hatasina yol acabilir. SessionEnsurer per-recipient
 * Mutex ile concurrent fetch'leri tek calisma altinda merge eder.
 */
@Singleton
class PreKeyBundleFetcher @Inject constructor(
    private val okHttpClient: OkHttpClient
) {
    private val baseUrl = BuildConfig.API_BASE_URL

    /**
     * @param recipientUserId UUID string
     * @return PreKeyBundle veya null (recipient bulunamadi / prekey'i yok)
     */
    suspend fun fetch(recipientUserId: String): PreKeyBundle? = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url("$baseUrl/api/v1/users/$recipientUserId/prekeys")
            .get()
            .build()
        try {
            okHttpClient.newCall(req).execute().use { resp ->
                if (resp.code == 404) {
                    Log.w("PreKeyBundleFetcher", "Recipient $recipientUserId icin prekey bulunamadi (404)")
                    return@use null
                }
                if (!resp.isSuccessful) {
                    Log.w("PreKeyBundleFetcher", "PreKey fetch basarisiz: HTTP ${resp.code}")
                    return@use null
                }
                val bodyStr = resp.body?.string() ?: return@use null
                parseBundle(bodyStr)
            }
        } catch (e: Exception) {
            Log.e("PreKeyBundleFetcher", "PreKey fetch exception: ${e.message}")
            null
        }
    }

    private fun parseBundle(bodyStr: String): PreKeyBundle {
        val json = JSONObject(bodyStr)
        val decoder = Base64.getDecoder()

        val identityKey = IdentityKey(Curve.decodePoint(decoder.decode(json.getString("identityPublicKey")), 0))
        val registrationId = json.getInt("registrationId")
        val signedPreKeyId = json.getInt("signedPreKeyId")
        val signedPubKey = Curve.decodePoint(decoder.decode(json.getString("signedPreKey")), 0)
        val signedSig = decoder.decode(json.getString("signedPreKeySignature"))

        val oneTime = if (json.has("oneTimePreKey") && !json.isNull("oneTimePreKey")) {
            val otpkJson = json.getJSONObject("oneTimePreKey")
            Pair(
                Curve.decodePoint(decoder.decode(otpkJson.getString("publicKey")), 0),
                otpkJson.getInt("keyId")
            )
        } else null

        return PreKeyBundle(
            registrationId,
            DEFAULT_DEVICE_ID,
            oneTime?.second ?: -1,
            oneTime?.first,
            signedPreKeyId,
            signedPubKey,
            signedSig,
            identityKey
        )
    }

    companion object {
        const val DEFAULT_DEVICE_ID = 1
    }
}
