package com.securechat.botapi.signal

import com.securechat.botapi.BotApiConfig
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import org.slf4j.LoggerFactory
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.ecc.Curve
import org.whispersystems.libsignal.state.PreKeyBundle
import java.util.Base64

private val log = LoggerFactory.getLogger("PreKeyBundleFetcher")

/**
 * Recipient'in PreKeyBundle'ini signaling-server'dan ceker.
 * GET /api/v1/users/{userId}/prekeys
 *
 * NOT: bundle CACHE'LENMEZ — her yeni session establishment'ta fresh fetch.
 * Recipient'in one-time prekey havuzu sirayla tuketildigi icin cache stale
 * olur ve "Bad message" hatasina yol acabilir.
 */
class PreKeyBundleFetcher(private val tokenProvider: () -> String) {

    private val httpClient = OkHttpClient.Builder()
        .callTimeout(java.time.Duration.ofSeconds(10))
        .build()
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * @param recipientUserId UUID string
     * @return PreKeyBundle veya null (recipient bulunamadi / prekey'i yok)
     */
    fun fetch(recipientUserId: String): PreKeyBundle? {
        val token = tokenProvider()
        val req = Request.Builder()
            .url("${BotApiConfig.signalingInternalUrl}/api/v1/users/$recipientUserId/prekeys")
            .get()
            .header("Authorization", "Bearer $token")
            .build()
        httpClient.newCall(req).execute().use { resp ->
            if (resp.code == 404) {
                log.warn("[Bundle] Recipient icin prekey bulunamadi (404)")
                return null
            }
            if (!resp.isSuccessful) {
                throw IllegalStateException("PreKey fetch basarisiz: HTTP ${resp.code}")
            }
            val bodyStr = resp.body?.string() ?: return null
            val payload = json.decodeFromString<PreKeyBundleResponse>(bodyStr)
            return toPreKeyBundle(payload)
        }
    }

    private fun toPreKeyBundle(p: PreKeyBundleResponse): PreKeyBundle {
        val identityKey = IdentityKey(Curve.decodePoint(b64(p.identityPublicKey), 0))
        val signedPubKey = Curve.decodePoint(b64(p.signedPreKey), 0)
        val signedSig = b64(p.signedPreKeySignature)
        val oneTime = p.oneTimePreKey?.let {
            Curve.decodePoint(b64(it.publicKey), 0) to it.keyId
        }
        return PreKeyBundle(
            p.registrationId,
            DEFAULT_DEVICE_ID,
            oneTime?.second ?: -1,
            oneTime?.first,
            p.signedPreKeyId,
            signedPubKey,
            signedSig,
            identityKey
        )
    }

    private fun b64(s: String): ByteArray = Base64.getDecoder().decode(s)

    companion object {
        const val DEFAULT_DEVICE_ID = 1
    }

    // --- signaling-server response kontratlari (HttpRoutes.kt'tekiyle ayni) ---

    @Serializable
    private data class PreKeyBundleResponse(
        val userId: String,
        val identityPublicKey: String,
        val registrationId: Int,
        val signedPreKeyId: Int,
        val signedPreKey: String,
        val signedPreKeySignature: String,
        val oneTimePreKey: PreKeyEntry? = null
    )

    @Serializable
    private data class PreKeyEntry(val keyId: Int, val publicKey: String)
}
