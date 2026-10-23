package com.securechat.signaling

import java.security.MessageDigest
import java.sql.Connection
import java.sql.Timestamp
import java.time.Duration
import java.time.Instant
import java.util.Base64

/**
 * Istege bagli kayit kilidi PIN'i.
 *
 * Istemci PIN'den Argon2id ile 32 baytlik bir kanit turetir; sunucu
 * yalniz bu kanitin [RecoveryRecordCipher.index] HMAC'ini saklar. Veritabani
 * tek basina ele gecse PIN denemek icin sunucu anahtari da gerekir.
 *
 * Kilit acikken kimlik degistiren kurtarma kanit ister. Yanlis kanitlar
 * sayilir; [MAX_FAILURES] sonra hesap [LOCKOUT] boyunca kurtarilamaz.
 * Cagiran `users` satirini kilitlemis olmalidir.
 */
internal object RegistrationLock {
    const val MAX_FAILURES = 10
    val LOCKOUT: Duration = Duration.ofHours(24)
    private const val PROOF_BYTES = 32

    sealed interface Check {
        data object NotRequired : Check
        data object Passed : Check
        data class Failed(val remaining: Int) : Check
        data class Locked(val retryAfterSeconds: Long) : Check
    }

    fun validProof(proof: String?): ByteArray? {
        if (proof == null) return null
        val bytes = runCatching { Base64.getDecoder().decode(proof) }.getOrNull() ?: return null
        return bytes.takeIf { it.size == PROOF_BYTES && Base64.getEncoder().encodeToString(it) == proof }
    }

    private fun verifier(cipher: RecoveryRecordCipher, userId: String, proof: String) =
        cipher.index("registration-lock:$userId", proof)

    fun enabled(connection: Connection, userId: String): Boolean =
        connection.prepareStatement(
            "SELECT registration_lock_verifier IS NOT NULL FROM users WHERE user_id = ?::uuid",
        ).use {
            it.setString(1, userId)
            it.executeQuery().use { rows -> rows.next() && rows.getBoolean(1) }
        }

    fun set(connection: Connection, cipher: RecoveryRecordCipher, userId: String, proof: String?): Boolean {
        val value = proof?.takeIf { validProof(it) != null } ?: return false
        return connection.prepareStatement(
            "UPDATE users SET registration_lock_verifier = ?, registration_lock_failures = 0, " +
                "registration_lock_until = NULL WHERE user_id = ?::uuid",
        ).use {
            it.setString(1, verifier(cipher, userId, value)); it.setString(2, userId)
            it.executeUpdate() == 1
        }
    }

    fun clear(connection: Connection, userId: String): Boolean = connection.prepareStatement(
        "UPDATE users SET registration_lock_verifier = NULL, registration_lock_failures = 0, " +
            "registration_lock_until = NULL WHERE user_id = ?::uuid",
    ).use {
        it.setString(1, userId)
        it.executeUpdate() == 1
    }

    /** Yanlis kanit da sayaci artirir; sonuc commit edilmelidir. */
    fun check(connection: Connection, cipher: RecoveryRecordCipher, userId: String, proof: String?): Check {
        val (stored, failures, until) = connection.prepareStatement(
            "SELECT registration_lock_verifier, registration_lock_failures, registration_lock_until " +
                "FROM users WHERE user_id = ?::uuid",
        ).use {
            it.setString(1, userId)
            it.executeQuery().use { rows ->
                if (!rows.next()) return Check.NotRequired
                Triple(rows.getString(1), rows.getInt(2), rows.getTimestamp(3)?.toInstant())
            }
        }
        stored ?: return Check.NotRequired
        val now = Instant.now()
        if (until != null && until.isAfter(now)) {
            return Check.Locked(Duration.between(now, until).seconds.coerceAtLeast(1))
        }
        val candidate = proof?.takeIf { validProof(it) != null }?.let { verifier(cipher, userId, it) }
        if (candidate != null && MessageDigest.isEqual(candidate.toByteArray(), stored.toByteArray())) {
            if (failures != 0 || until != null) reset(connection, userId)
            return Check.Passed
        }
        val next = failures + 1
        return if (next >= MAX_FAILURES) {
            val lockedUntil = now.plus(LOCKOUT)
            update(connection, userId, 0, lockedUntil)
            Check.Locked(LOCKOUT.seconds)
        } else {
            update(connection, userId, next, null)
            Check.Failed(MAX_FAILURES - next)
        }
    }

    private fun reset(connection: Connection, userId: String) = update(connection, userId, 0, null)

    private fun update(connection: Connection, userId: String, failures: Int, until: Instant?) {
        connection.prepareStatement(
            "UPDATE users SET registration_lock_failures = ?, registration_lock_until = ? WHERE user_id = ?::uuid",
        ).use {
            it.setInt(1, failures)
            it.setTimestamp(2, until?.let(Timestamp::from))
            it.setString(3, userId)
            it.executeUpdate()
        }
    }
}

/** Kurtarma kayit kilidi yuzunden reddedildi; route ozel yanit doner. */
internal class RegistrationLockException(val check: RegistrationLock.Check) : RuntimeException("registration lock")
