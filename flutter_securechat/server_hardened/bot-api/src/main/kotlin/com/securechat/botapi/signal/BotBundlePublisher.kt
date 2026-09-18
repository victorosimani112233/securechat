package com.securechat.botapi.signal

import com.securechat.botapi.BotApiConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.slf4j.LoggerFactory
import java.time.Duration
import java.util.Base64

/**
 * Bot'un public Signal materyalini signaling-server'a yayinlayan sinir.
 *
 * Bootstrap'in DB adimlari ile remote yayin adimi ayri dogrulanabilsin diye
 * network siniri enjekte edilebilir tutulur. Yayin basarisiz olursa bot hazir
 * sayilmaz ve bir sonraki acilis yalniz eksik adimi tamamlar.
 */
interface BotBundlePublisher {
    fun publish(bundle: PublishedBundle)
}

class PublishedPreKey(val keyId: Int, val publicKey: ByteArray)

class PublishedBundle(
    val botUserId: String,
    val identityPublicKey: ByteArray,
    val registrationId: Int,
    val signedPreKeyId: Int,
    val signedPreKey: ByteArray,
    val signedPreKeySignature: ByteArray,
    val oneTimePreKeys: List<PublishedPreKey>,
)

/**
 * Gercek yayin yolu: authenticated `POST /api/v1/prekeys/upload`.
 *
 * Bot public materyalini signaling'in kendi yetkilendirme route'undan
 * gecirir; DB'ye dogrudan prekey yazmaz.
 */
object HttpBundlePublisher : BotBundlePublisher {

    private val log = LoggerFactory.getLogger("BotBundlePublisher")
    private val encoder: Base64.Encoder = Base64.getEncoder()
    private val json = Json { ignoreUnknownKeys = true }
    private val httpClient = OkHttpClient.Builder()
        .callTimeout(Duration.ofSeconds(15))
        .build()

    override fun publish(bundle: PublishedBundle) {
        val body = PreKeyUploadRequest(
            identityPublicKey = encoder.encodeToString(bundle.identityPublicKey),
            registrationId = bundle.registrationId,
            signedPreKeyId = bundle.signedPreKeyId,
            signedPreKey = encoder.encodeToString(bundle.signedPreKey),
            signedPreKeySignature = encoder.encodeToString(bundle.signedPreKeySignature),
            oneTimePreKeys = bundle.oneTimePreKeys.map {
                PreKeyEntry(it.keyId, encoder.encodeToString(it.publicKey))
            },
        )
        val token = BotServiceTokenMinter.issue(
            bundle.botUserId,
            BotServiceTokenMinter.Scope.PREKEY_UPLOAD,
        )
        val request = Request.Builder()
            .url("${BotApiConfig.signalingInternalUrl}/api/v1/prekeys/upload")
            .post(json.encodeToString(body).toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $token")
            .build()
        httpClient.newCall(request).execute().use { response ->
            check(response.isSuccessful) {
                "PreKey upload basarisiz: HTTP ${response.code}"
            }
            log.info(
                "[Bootstrap] Bundle yayinlandi; signedPreKey=1 oneTime={}",
                bundle.oneTimePreKeys.size,
            )
        }
    }

    // signaling-server HttpRoutes.kt kontratiyla ayni alan adlari.

    @Serializable
    private data class PreKeyUploadRequest(
        @SerialName("identityPublicKey") val identityPublicKey: String,
        @SerialName("registrationId") val registrationId: Int,
        @SerialName("signedPreKeyId") val signedPreKeyId: Int,
        @SerialName("signedPreKey") val signedPreKey: String,
        @SerialName("signedPreKeySignature") val signedPreKeySignature: String,
        @SerialName("oneTimePreKeys") val oneTimePreKeys: List<PreKeyEntry>,
    )

    @Serializable
    private data class PreKeyEntry(val keyId: Int, val publicKey: String)
}
