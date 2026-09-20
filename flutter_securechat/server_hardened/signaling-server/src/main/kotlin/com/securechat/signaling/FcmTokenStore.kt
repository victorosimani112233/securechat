package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.sql.Connection
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("FcmTokenStore")

/**
 * FCM token yonetimi: PostgreSQL'de kisa omurlu AEAD ciphertext, process
 * icinde ise ayni retention sinirina tabi gecici cache.
 *
 * Kalici satirlar ham kullanici UUID'si tasimaz. UUID, ayri privacy key ile
 * uretilmis deterministic bir blind index'e donusturulur; token da bu indekse
 * AAD ile baglidir. V14 sonrasi tablo ham UUID kolonu tasimaz. v4 kayitlar
 * ilk basarili okumada key-id tasiyan v5'e cevrilir; bozuk satirlar silinir.
 */
class FcmTokenStore internal constructor(
    private val cipher: FcmTokenCipher = FcmTokenCipher.fromEnvironment(),
    private val retentionDays: Int = ServerPrivacy.config.pushTokenRetentionDays,
    private val userIndexProvider: (String) -> String = {
        ServerPrivacy.blindIndex("push-user", it)
    },
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private data class DeviceRegistration(
        val token: String,
        val pushHintKey: ByteArray?,
    )

    private data class CachedToken(
        val registration: DeviceRegistration,
        val updatedAtMillis: Long,
    )

    private data class StoredRow(
        val id: Long,
        val userIndex: String,
        val token: String,
        val updatedAtMillis: Long,
    )

    // Map key'i de ham UUID degil blind index'tir. Plaintext token yalnizca
    // calisan process RAM'inde ve bounded retention suresince bulunur.
    private val tokens = ConcurrentHashMap<String, CachedToken>()

    init {
        require(retentionDays in 1..90) { "Push token retention must be 1..90 days" }
        loadPrivateRowsFromDb()
    }

    fun registerToken(userId: String, token: String, pushHintKey: String? = null) {
        requireValidToken(token)
        val decodedHintKey = pushHintKey?.let(::decodePushHintKey)
        val normalizedUserId = normalizeUserId(userId)
        val userIndex = indexFor(normalizedUserId)
        val registration = DeviceRegistration(token, decodedHintKey)
        upsertToDb(userIndex, registration)
        tokens[userIndex] = CachedToken(registration, nowMillis())
        log.info("[FCM] Token kaydedildi")
    }

    fun removeToken(userId: String) {
        val normalizedUserId = normalizeUserId(userId)
        val userIndex = indexFor(normalizedUserId)
        deleteFromDb(userIndex)
        tokens.remove(userIndex)
        log.info("[FCM] Token silindi")
    }

    fun getToken(userId: String): String? {
        val userIndex = indexFor(normalizeUserId(userId))
        val cached = tokens[userIndex] ?: return null
        if (cached.updatedAtMillis < retentionCutoff()) {
            tokens.remove(userIndex, cached)
            return null
        }
        return cached.registration.token
    }

    fun getPushHintKey(userId: String): ByteArray? {
        val userIndex = indexFor(normalizeUserId(userId))
        val cached = tokens[userIndex] ?: return null
        if (cached.updatedAtMillis < retentionCutoff()) {
            tokens.remove(userIndex, cached)
            return null
        }
        return cached.registration.pushHintKey?.clone()
    }

    fun getTokenCount(): Int {
        purgeExpiredMemory(retentionCutoff())
        return tokens.size
    }

    fun purgeExpiredMemory(cutoffMillis: Long) {
        tokens.entries.removeIf { (_, token) -> token.updatedAtMillis < cutoffMillis }
    }

    private fun upsertToDb(userIndex: String, registration: DeviceRegistration) {
        try {
            val encrypted = cipher.seal(userIndex, encodeRegistration(registration))
            Database.getConnection().use { connection ->
                connection.prepareStatement(
                    """INSERT INTO fcm_tokens (user_index, token, registered_on)
                       VALUES (?, ?, CURRENT_DATE)
                       ON CONFLICT (user_index)
                       DO UPDATE SET token = EXCLUDED.token,
                                     registered_on = CURRENT_DATE""",
                ).use { statement ->
                    statement.setString(1, userIndex)
                    statement.setString(2, encrypted)
                    statement.executeUpdate()
                }
            }
        } catch (error: Exception) {
            log.warn("[!] FcmTokenStore DB upsert hatasi: {}", error.javaClass.simpleName)
            throw IllegalStateException("FCM token persistence failed", error)
        }
    }

    private fun deleteFromDb(userIndex: String) {
        try {
            Database.getConnection().use { connection ->
                connection.prepareStatement(
                    "DELETE FROM fcm_tokens WHERE user_index = ?",
                ).use { statement ->
                    statement.setString(1, userIndex)
                    statement.executeUpdate()
                }
            }
        } catch (error: Exception) {
            log.warn("[!] FcmTokenStore DB delete hatasi: {}", error.javaClass.simpleName)
            throw IllegalStateException("FCM token deletion failed", error)
        }
    }

    private fun loadPrivateRowsFromDb() {
        val loaded = mutableMapOf<String, CachedToken>()
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                val rows = readLockedRows(connection)
                var erased = 0
                val cutoff = retentionCutoff()

                for (row in rows) {
                    if (row.updatedAtMillis < cutoff) {
                        deleteRow(connection, row.id)
                        erased++
                        continue
                    }

                    if (!isValidBlindIndex(row.userIndex)) {
                        deleteRow(connection, row.id)
                        erased++
                        continue
                    }

                    val plaintext = if (row.token.length <= MAX_STORED_TOKEN_CHARS) {
                        cipher.open(row.userIndex, row.token)
                    } else {
                        null
                    }
                    val registration = plaintext?.let(::decodeRegistration)
                    if (registration == null) {
                        deleteRow(connection, row.id)
                        erased++
                        continue
                    }
                    if (cipher.needsMigration(row.token)) {
                        migrateEnvelope(connection, row, cipher.seal(row.userIndex, plaintext))
                    }
                    loaded[row.userIndex] = CachedToken(registration, row.updatedAtMillis)
                }

                connection.commit()
                tokens.putAll(loaded)
                log.info(
                    "[FCM] Private token store hazir; loaded={}, erased={}",
                    loaded.size,
                    erased,
                )
            } catch (error: Exception) {
                connection.rollback()
                throw IllegalStateException("FCM private token verification failed", error)
            } finally {
                connection.autoCommit = true
            }
        }
    }

    private fun readLockedRows(connection: Connection): List<StoredRow> =
        connection.createStatement().use { statement ->
            statement.executeQuery(
                "SELECT id, user_index, token, registered_on FROM fcm_tokens FOR UPDATE",
            ).use { rows ->
                buildList {
                    while (rows.next()) {
                        add(
                            StoredRow(
                                id = rows.getLong("id"),
                                userIndex = rows.getString("user_index") ?: "",
                                token = rows.getString("token") ?: "",
                                // Retention needs only day precision. Exact
                                // registration activity is never persisted.
                                updatedAtMillis = rows.getDate("registered_on").time,
                            ),
                        )
                    }
                }
            }
        }

    private fun deleteRow(connection: Connection, rowId: Long) {
        connection.prepareStatement("DELETE FROM fcm_tokens WHERE id = ?").use { statement ->
            statement.setLong(1, rowId)
            statement.executeUpdate()
        }
    }

    private fun migrateEnvelope(connection: Connection, row: StoredRow, replacement: String) {
        connection.prepareStatement(
            "UPDATE fcm_tokens SET token = ? WHERE id = ? AND token = ?",
        ).use { statement ->
            statement.setString(1, replacement)
            statement.setLong(2, row.id)
            statement.setString(3, row.token)
            statement.executeUpdate()
        }
    }

    private fun indexFor(normalizedUserId: String): String =
        userIndexProvider(normalizedUserId).also {
            require(isValidBlindIndex(it)) { "Invalid push-token blind index" }
        }

    private fun retentionCutoff(): Long = nowMillis() - retentionDays * MILLIS_PER_DAY

    private fun requireValidToken(token: String) {
        require(isValidPushToken(token)) { "Invalid FCM token format" }
    }

    private fun encodeRegistration(registration: DeviceRegistration): String {
        val key = registration.pushHintKey ?: return registration.token
        val encodedToken = Base64.getUrlEncoder().withoutPadding().encodeToString(
            registration.token.toByteArray(StandardCharsets.UTF_8),
        )
        val encodedKey = Base64.getUrlEncoder().withoutPadding().encodeToString(key)
        return "$REGISTRATION_PREFIX$encodedToken:$encodedKey"
    }

    private fun decodeRegistration(value: String): DeviceRegistration? {
        if (!value.startsWith(REGISTRATION_PREFIX)) {
            return value.takeIf(::isValidPushToken)?.let { DeviceRegistration(it, null) }
        }
        val fields = value.removePrefix(REGISTRATION_PREFIX).split(':')
        if (fields.size != 2) return null
        return try {
            val token = String(Base64.getUrlDecoder().decode(fields[0]), StandardCharsets.UTF_8)
            val key = Base64.getUrlDecoder().decode(fields[1])
            if (!isValidPushToken(token) || key.size != PUSH_HINT_KEY_BYTES) null
            else DeviceRegistration(token, key)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun decodePushHintKey(value: String): ByteArray {
        val decoded = try {
            Base64.getUrlDecoder().decode(value)
        } catch (error: IllegalArgumentException) {
            throw IllegalArgumentException("Invalid push hint key", error)
        }
        require(decoded.size == PUSH_HINT_KEY_BYTES) {
            "Push hint key must decode to exactly $PUSH_HINT_KEY_BYTES bytes"
        }
        return decoded
    }

    companion object {
        private const val MAX_STORED_TOKEN_CHARS = 8_192
        private const val MILLIS_PER_DAY = 86_400_000L
        private const val REGISTRATION_PREFIX = "r1:"
        private const val PUSH_HINT_KEY_BYTES = 32

        private fun normalizeUserId(value: String): String = UUID.fromString(value).toString()

        private fun isValidBlindIndex(value: String): Boolean =
            value.length == 43 && value.all {
                it.isLetterOrDigit() || it == '-' || it == '_'
            }

        internal fun isValidPushToken(value: String): Boolean =
            value.length in 20..4_096 && value.all { it.code in 0x21..0x7e }
    }
}
