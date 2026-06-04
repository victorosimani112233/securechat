package com.securechat.botapi.signal

import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotDatabase
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.slf4j.LoggerFactory
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.util.KeyHelper
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID

private val log = LoggerFactory.getLogger("BotIdentityBootstrap")

/**
 * Bot ilk acilisinda Signal identity'sini olusturur + signaling-server'a
 * prekey bundle yukler. Idempotent: bot_identity satiri varsa hicbir sey
 * yapmaz, sadece BotIdentity holder'ini doldurur.
 *
 * Akis (first-run):
 *  1. KeyHelper ile identity keypair + 100 one-time + 1 signed prekey gen
 *  2. users tablosuna direct INSERT (OTP bypass — bot internal kayit;
 *     phone_hash = sha256("bot:" + identityFingerprint), encrypted_phone = NULL)
 *  3. PgSignalProtocolStore'a tum prekey'leri storela (encrypted)
 *  4. bot_identity row'unu olustur (singleton id=1, identity private AES-GCM)
 *  5. signaling-server'a JWT mint et + POST /api/v1/prekeys/upload
 *  6. BotIdentity.set(...) ile runtime holder'i doldur
 */
object BotIdentityBootstrap {

    private const val ONE_TIME_PREKEY_COUNT = 100
    private const val SIGNED_PREKEY_ID = 1

    private val urlSafeB64 = Base64.getEncoder() // standart base64 — signaling-server'in PreKeyUploadRequest formatiyla uyumlu
    private val httpClient = OkHttpClient.Builder()
        .callTimeout(java.time.Duration.ofSeconds(15))
        .build()
    private val json = Json { ignoreUnknownKeys = true }

    fun ensureRegistered() {
        if (loadExisting()) {
            log.info("[Bootstrap] Bot identity zaten kayitli — yukleme tamam")
            return
        }
        log.info("[Bootstrap] First-run — yeni bot identity uretiliyor")
        firstRun()
    }

    /** bot_identity satiri varsa runtime holder'i doldur ve true don. */
    private fun loadExisting(): Boolean {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement("SELECT bot_user_id, registration_id FROM bot_identity WHERE id = 1")
                .use { stmt ->
                    stmt.executeQuery().use { rs ->
                        if (!rs.next()) return false
                        val userId = rs.getObject("bot_user_id", UUID::class.java).toString()
                        val regId = rs.getInt("registration_id")
                        BotIdentity.set(userId, regId)
                        log.info("[Bootstrap] Mevcut identity: userId={}, regId={}", userId, regId)
                        return true
                    }
                }
        }
    }

    private fun firstRun() {
        val identityKeyPair: IdentityKeyPair = KeyHelper.generateIdentityKeyPair()
        val registrationId = KeyHelper.generateRegistrationId(false)
        val oneTimePreKeys = KeyHelper.generatePreKeys(1, ONE_TIME_PREKEY_COUNT)
        val signedPreKey = KeyHelper.generateSignedPreKey(identityKeyPair, SIGNED_PREKEY_ID)

        val botUserId = UUID.randomUUID()
        val identityFp = sha256(identityKeyPair.publicKey.serialize())
        val phoneHash = "bot:" + Base64.getUrlEncoder().withoutPadding()
            .encodeToString(identityFp).take(32)

        // 1) users INSERT — OTP bypass; bot internal kayit
        BotDatabase.getConnection().use { conn ->
            conn.autoCommit = false
            try {
                conn.prepareStatement(
                    """INSERT INTO users(user_id, phone_hash, encrypted_phone, email, email_verified,
                            identity_public_key, registration_id)
                       VALUES (?, ?, NULL, NULL, FALSE, ?, ?)"""
                ).use { stmt ->
                    stmt.setObject(1, botUserId)
                    stmt.setString(2, phoneHash)
                    stmt.setBytes(3, identityKeyPair.publicKey.serialize())
                    stmt.setInt(4, registrationId)
                    stmt.executeUpdate()
                }

                // 2) bot_identity (singleton)
                val privSerialized = identityKeyPair.privateKey.serialize()
                val wrapped = KeyEncryptor.wrap(privSerialized)
                conn.prepareStatement(
                    """INSERT INTO bot_identity(id, bot_user_id, registration_id,
                           identity_public_key, identity_private_key_enc, identity_private_key_nonce)
                       VALUES (1, ?, ?, ?, ?, ?)"""
                ).use { stmt ->
                    stmt.setObject(1, botUserId)
                    stmt.setInt(2, registrationId)
                    stmt.setBytes(3, identityKeyPair.publicKey.serialize())
                    stmt.setBytes(4, wrapped.ciphertext)
                    stmt.setBytes(5, wrapped.nonce)
                    stmt.executeUpdate()
                }
                conn.commit()
            } catch (e: Exception) {
                conn.rollback()
                throw e
            } finally {
                conn.autoCommit = true
            }
        }

        // 3) Tum prekey'leri PgSignalProtocolStore uzerinden persist et
        val store = PgSignalProtocolStore()
        store.storeSignedPreKey(signedPreKey.id, signedPreKey)
        for (preKey in oneTimePreKeys) {
            store.storePreKey(preKey.id, preKey)
        }

        // Runtime holder
        BotIdentity.set(botUserId.toString(), registrationId)

        // 4) signaling-server'a prekey bundle yukle
        val token = BotJwtMinter.issueAccessToken(botUserId.toString())
        uploadPreKeyBundle(
            token = token,
            identityPublicKey = identityKeyPair.publicKey.serialize(),
            registrationId = registrationId,
            signedPreKey = signedPreKey,
            oneTimePreKeys = oneTimePreKeys
        )

        log.info("[Bootstrap] Yeni identity hazirlandi: userId={}, regId={}, " +
                "preKeys={}, phone_hash_prefix={}",
            botUserId, registrationId, oneTimePreKeys.size, phoneHash.take(8))
    }

    private fun uploadPreKeyBundle(
        token: String,
        identityPublicKey: ByteArray,
        registrationId: Int,
        signedPreKey: org.whispersystems.libsignal.state.SignedPreKeyRecord,
        oneTimePreKeys: List<org.whispersystems.libsignal.state.PreKeyRecord>
    ) {
        val body = PreKeyUploadRequest(
            identityPublicKey = urlSafeB64.encodeToString(identityPublicKey),
            registrationId = registrationId,
            signedPreKeyId = signedPreKey.id,
            signedPreKey = urlSafeB64.encodeToString(signedPreKey.keyPair.publicKey.serialize()),
            signedPreKeySignature = urlSafeB64.encodeToString(signedPreKey.signature),
            oneTimePreKeys = oneTimePreKeys.map {
                PreKeyEntry(it.id, urlSafeB64.encodeToString(it.keyPair.publicKey.serialize()))
            }
        )
        val payload = json.encodeToString(body)
        val req = Request.Builder()
            .url("${BotApiConfig.signalingInternalUrl}/api/v1/prekeys/upload")
            .post(payload.toRequestBody("application/json".toMediaType()))
            .header("Authorization", "Bearer $token")
            .build()
        httpClient.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                val errBody = resp.body?.string()?.take(500)
                throw IllegalStateException(
                    "PreKey upload basarisiz: HTTP ${resp.code}, body=$errBody"
                )
            }
            log.info("[Bootstrap] PreKey bundle signaling-server'a yuklendi (HTTP {})", resp.code)
        }
    }

    private fun sha256(input: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(input)

    // --- signaling-server kontratlari (HttpRoutes.kt'tekiyle ayni) ---

    @Serializable
    private data class PreKeyUploadRequest(
        @SerialName("identityPublicKey") val identityPublicKey: String,
        @SerialName("registrationId") val registrationId: Int,
        @SerialName("signedPreKeyId") val signedPreKeyId: Int,
        @SerialName("signedPreKey") val signedPreKey: String,
        @SerialName("signedPreKeySignature") val signedPreKeySignature: String,
        @SerialName("oneTimePreKeys") val oneTimePreKeys: List<PreKeyEntry>
    )

    @Serializable
    private data class PreKeyEntry(val keyId: Int, val publicKey: String)
}
