package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.sql.Connection
import java.security.MessageDigest
import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable internal data class RecoveryRequest(val email: String)
@Serializable internal data class RecoveryVerify(val challengeId: String, val otp: String, val signature: String = "")
@Serializable internal data class RecoveryChallenge(val challengeId: String, val expiresIn: Int)
@Serializable internal data class RecoveryEnrollmentChallenge(
    val challengeId: String, val nonce: String, val credentialEpoch: String,
    val identityProtocol: String, val expiresIn: Int,
)
@Serializable internal data class RecoveryGrant(
    val recoveryToken: String, val userId: String, val identityProtocol: String,
    val identityPublicKey: String, val registrationId: Int, val expiresIn: Int,
)
@Serializable internal data class RecoveryComplete(
    val recoveryToken: String, val completionId: String, val mode: String, val identityProtocol: String,
    val identityPublicKey: String, val registrationId: Int, val signature: String,
)
@Serializable internal data class RecoveryCredentials(
    val userId: String, val token: String, val refreshToken: String, val identityReplaced: Boolean,
)

/** All durable transitions serialize on the account before consuming a challenge. */
internal class RecoveryAuthService(
    private val cipher: RecoveryRecordCipher,
    private val send: (String, String, String) -> Unit,
) {
    @Serializable
    internal data class Context(
        val userId: String = "", val email: String, val epoch: String = "",
        val nonce: String = "", val protocol: String = "", val identity: String = "",
        val registrationId: Int = 0, val version: String = "",
    )
    private data class Challenge(val context: Context, val accountIndex: String?, val emailIndex: String)
    private data class Account(val epoch: String, val protocol: String, val key: ByteArray, val registrationId: Int)
    @Serializable private data class Receipt(val epoch: String, val response: RecoveryCredentials)

    fun enrolled(userId: String, epoch: String): Boolean = transaction { connection ->
        val account = lockAccount(connection, userId)
        check(account != null && account.epoch == epoch)
        binding(connection, "account_index", cipher.index("account", userId)) != null
    }

    fun requestEnrollment(userId: String, epoch: String, rawEmail: String): RecoveryEnrollmentChallenge? {
        val email = RecoveryRecordCipher.normalizeEmail(rawEmail)
        val id = RecoveryRecordCipher.opaque()
        val nonce = RecoveryRecordCipher.opaque()
        val otp = RecoveryRecordCipher.otp()
        val result = transaction { connection ->
            val account = lockAccount(connection, userId) ?: return@transaction null
            if (account.epoch != epoch || account.key.size != 33) return@transaction null
            val ai = cipher.index("account", userId)
            val ei = cipher.index("email", email)
            if (!quota(connection, "enroll-account", ai, 5) || !quota(connection, "enroll-email", ei, 5)) return@transaction null
            if (binding(connection, "account_index", ai) != null) return@transaction null
            val context = Context(userId, email, epoch, nonce, account.protocol, b64(account.key), account.registrationId)
            store(connection, id, "enroll", context, otp, 600)
            RecoveryEnrollmentChallenge(id, nonce, epoch, account.protocol, 600)
        }
        if (result != null) send(email, otp, "enroll")
        return result
    }

    fun verifyEnrollment(userId: String, epoch: String, request: RecoveryVerify): Boolean = transaction { connection ->
        val account = lockAccount(connection, userId) ?: return@transaction false
        if (account.epoch != epoch) return@transaction false
        val challenge = consume(connection, request.challengeId, "enroll", request.otp) ?: return@transaction false
        val context = challenge.context
        if (context.userId != userId || context.epoch != epoch || context.protocol != account.protocol ||
            context.identity != b64(account.key) || !RecoveryRecordCipher.verify(
                account.key, enrollmentPreimage(request.challengeId, context), request.signature,
            )) return@transaction false
        val ai = cipher.index("account", userId)
        val ei = cipher.index("email", context.email)
        val version = RecoveryRecordCipher.opaque()
        connection.prepareStatement(
            """INSERT INTO account_recovery_bindings(account_index, email_index, binding_version, sealed_context)
               VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING""",
        ).use { statement ->
            statement.setString(1, ai)
            statement.setString(2, ei)
            statement.setString(3, version)
            statement.setBytes(4, cipher.seal(bindingAad(ai, ei, version), Json.encodeToString(Context(userId = userId, email = context.email, version = version))))
            statement.executeUpdate() == 1
        }
    }

    fun requestLogin(rawEmail: String): RecoveryChallenge {
        val email = RecoveryRecordCipher.normalizeEmail(rawEmail)
        val id = RecoveryRecordCipher.opaque()
        val otp = RecoveryRecordCipher.otp()
        val deliver = try { transaction { connection ->
            // Bound requests cannot wait on account activity beyond the public response floor.
            connection.createStatement().use { it.execute("SET LOCAL lock_timeout = '150ms'") }
            val ei = cipher.index("email", email)
            if (!quota(connection, "login-email", ei, 5)) return@transaction false
            val bound = binding(connection, "email_index", ei)
            val account = bound?.let { lockAccount(connection, it.userId) }
            val context = if (account != null && account.key.size == 33) {
                bound.copy(epoch = account.epoch, protocol = account.protocol, identity = b64(account.key), registrationId = account.registrationId)
            } else Context(email = email)
            // Unknown addresses receive indistinguishable random challenges but can never verify.
            store(connection, id, "login", context, otp, 600)
            context.userId.isNotEmpty()
        } } catch (error: java.sql.SQLException) {
            if (error.sqlState == "55P03") false else throw error
        }
        if (deliver) send(email, otp, "login")
        return RecoveryChallenge(id, 600)
    }

    fun verifyLogin(request: RecoveryVerify): RecoveryGrant? = transaction { connection ->
        val preview = read(connection, request.challengeId, "login") ?: return@transaction null
        val account = preview.context.userId.takeIf { it.isNotEmpty() }?.let { lockAccount(connection, it) }
        val challenge = consume(connection, request.challengeId, "login", request.otp) ?: return@transaction null
        val context = challenge.context
        if (account == null || !currentBinding(connection, context, account)) return@transaction null
        val token = RecoveryRecordCipher.opaque()
        store(connection, token, "complete", context, token, 300)
        RecoveryGrant(token, context.userId, context.protocol, context.identity, context.registrationId, 300)
    }

    fun complete(request: RecoveryComplete): RecoveryCredentials? {
        if (!request.completionId.matches(Regex("[A-Za-z0-9_-]{43}"))) return null
        val result = transaction { connection ->
            val preview = read(connection, request.recoveryToken, "complete")
            if (preview == null) return@transaction receipt(connection, request)
            val account = lockAccount(connection, preview.context.userId) ?: return@transaction null
            val challenge = consume(connection, request.recoveryToken, "complete", request.recoveryToken)
                ?: return@transaction receipt(connection, request)
            val context = challenge.context
            if (!currentBinding(connection, context, account)) return@transaction null
            if (request.mode !in setOf("preserve", "replace") || request.identityProtocol !in setOf("v1", "v2") ||
                request.registrationId !in 1..16383) return@transaction null
            val key = runCatching { Base64.getDecoder().decode(request.identityPublicKey) }.getOrNull() ?: return@transaction null
            if (key.size != 33 || b64(key) != request.identityPublicKey || !RecoveryRecordCipher.verify(
                    key, completionPreimage(context.userId, request), request.signature,
                )) return@transaction null
            if (request.mode == "preserve" && (request.identityProtocol != account.protocol ||
                    !key.contentEquals(account.key) || request.registrationId != account.registrationId)) return@transaction null
            if (request.mode == "replace") {
                for (table in listOf("one_time_prekeys", "signed_prekeys", "modern_one_time_prekeys", "modern_last_resort_kyber_prekeys", "modern_prekey_bundles")) {
                    connection.prepareStatement("DELETE FROM $table WHERE user_id = ?::uuid").use {
                        it.setString(1, context.userId); it.executeUpdate()
                    }
                }
                // Pin survives the empty-bundle interval and fences both upload namespaces.
                connection.prepareStatement("UPDATE users SET identity_public_key = ?, registration_id = ?, recovery_identity_pin = ?, recovery_identity_protocol = ? WHERE user_id = ?::uuid").use {
                    it.setBytes(1, key); it.setInt(2, request.registrationId); it.setBytes(3, key)
                    it.setString(4, request.identityProtocol); it.setString(5, context.userId); it.executeUpdate()
                }
            }
            val epoch = RecoveryRecordCipher.opaque()
            val generation = RecoveryRecordCipher.opaque()
            connection.prepareStatement("UPDATE users SET credential_epoch = ?, refresh_generation = ? WHERE user_id = ?::uuid").use {
                it.setString(1, epoch); it.setString(2, generation); it.setString(3, context.userId); it.executeUpdate()
            }
            deleteChallenges(connection, cipher.index("account", context.userId))
            // Signing failures roll back consumption, pin installation, and credential rotation.
            val response = RecoveryCredentials(context.userId, AuthService.issueToken(context.userId, epoch),
                AuthService.issueRefreshToken(context.userId, epoch, generation), request.mode == "replace")
            val ci = cipher.index("challenge-complete", request.recoveryToken)
            val ai = cipher.index("account", context.userId)
            val hash = requestHash(request)
            connection.prepareStatement("INSERT INTO account_recovery_receipts(challenge_index, account_index, request_hash, sealed_response, expires_at) VALUES (?, ?, ?, ?, clock_timestamp() + INTERVAL '5 minutes')").use {
                it.setString(1, ci); it.setString(2, ai); it.setString(3, hash)
                it.setBytes(4, cipher.seal("recovery-receipt/v1\u0000$ci\u0000$ai\u0000$hash", Json.encodeToString(Receipt(epoch, response))))
                it.executeUpdate()
            }
            response
        }
        result?.let { CredentialState.invalidateEverywhere(it.userId) }
        return result
    }

    private fun requestHash(request: RecoveryComplete) = cipher.index("completion-request", Json.encodeToString(request))

    private fun receipt(connection: Connection, request: RecoveryComplete): RecoveryCredentials? {
        val ci = cipher.index("challenge-complete", request.recoveryToken)
        val hash = requestHash(request)
        val saved = connection.prepareStatement("SELECT account_index, request_hash, sealed_response FROM account_recovery_receipts WHERE challenge_index = ? AND expires_at > clock_timestamp()").use {
            it.setString(1, ci)
            it.executeQuery().use { rows ->
                if (!rows.next() || !MessageDigest.isEqual(hash.toByteArray(), rows.getString(2).toByteArray())) return null
                val ai = rows.getString(1)
                Json.decodeFromString<Receipt>(cipher.open("recovery-receipt/v1\u0000$ci\u0000$ai\u0000$hash", rows.getBytes(3)))
            }
        }
        val account = lockAccount(connection, saved.response.userId) ?: return null
        val unexpired = connection.prepareStatement("SELECT EXISTS(SELECT 1 FROM account_recovery_receipts WHERE challenge_index = ? AND expires_at > clock_timestamp())").use {
            it.setString(1, ci); it.executeQuery().use { rows -> rows.next() && rows.getBoolean(1) }
        }
        return saved.response.takeIf { unexpired && saved.epoch == account.epoch }
    }

    private fun currentBinding(connection: Connection, context: Context, account: Account): Boolean {
        val bound = binding(connection, "account_index", cipher.index("account", context.userId))
        return bound != null && bound.version == context.version && bound.email == context.email &&
            account.epoch == context.epoch && account.protocol == context.protocol && b64(account.key) == context.identity
    }

    private fun lockAccount(connection: Connection, userId: String): Account? {
        val legacy = connection.prepareStatement("SELECT credential_epoch, identity_public_key, registration_id, recovery_identity_protocol FROM users WHERE user_id = ?::uuid FOR UPDATE").use {
            it.setString(1, userId)
            it.executeQuery().use { rows ->
                if (!rows.next()) return null
                Account(rows.getString(1), rows.getString(4) ?: "v1", rows.getBytes(2) ?: ByteArray(0), rows.getInt(3))
            }
        }
        return connection.prepareStatement("SELECT identity_public_key, registration_id FROM modern_prekey_bundles WHERE user_id = ?::uuid").use {
            it.setString(1, userId)
            it.executeQuery().use { rows -> if (rows.next()) Account(legacy.epoch, "v2", rows.getBytes(1), rows.getInt(2)) else legacy }
        }
    }

    private fun binding(connection: Connection, column: String, index: String): Context? = connection.prepareStatement(
        "SELECT account_index, email_index, binding_version, sealed_context FROM account_recovery_bindings WHERE $column = ?",
    ).use {
        it.setString(1, index)
        it.executeQuery().use { rows ->
            if (!rows.next()) null else Json.decodeFromString<Context>(cipher.open(
                bindingAad(rows.getString(1), rows.getString(2), rows.getString(3)), rows.getBytes(4),
            )).also { context ->
                check(cipher.index("account", context.userId) == rows.getString(1) &&
                    cipher.index("email", context.email) == rows.getString(2) && context.version == rows.getString(3))
            }
        }
    }

    private fun store(connection: Connection, id: String, purpose: String, context: Context, proof: String, ttl: Int) {
        val ci = cipher.index("challenge-$purpose", id)
        val ai = context.userId.takeIf { it.isNotEmpty() }?.let { cipher.index("account", it) }
        val ei = cipher.index("email", context.email)
        connection.prepareStatement("""INSERT INTO account_recovery_challenges
            (challenge_index, purpose, account_index, email_index, sealed_context, proof_hash, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, clock_timestamp() + (? * INTERVAL '1 second'))""").use {
            it.setString(1, ci); it.setString(2, purpose); it.setString(3, ai); it.setString(4, ei)
            it.setBytes(5, cipher.seal(challengeAad(ci, purpose, ai, ei), Json.encodeToString(context)))
            it.setString(6, cipher.index("proof-$purpose", "$id\u0000$proof")); it.setInt(7, ttl); it.executeUpdate()
        }
    }

    private fun read(connection: Connection, id: String, purpose: String): Challenge? {
        if (!id.matches(Regex("[A-Za-z0-9_-]{43}"))) return null
        val ci = cipher.index("challenge-$purpose", id)
        return connection.prepareStatement("SELECT account_index, email_index, sealed_context FROM account_recovery_challenges WHERE challenge_index = ? AND purpose = ? AND expires_at > clock_timestamp() AND attempts < 5").use {
            it.setString(1, ci); it.setString(2, purpose)
            it.executeQuery().use { rows ->
                if (!rows.next()) null else {
                    val ai = rows.getString(1)
                    val ei = rows.getString(2)
                    Challenge(Json.decodeFromString(cipher.open(challengeAad(ci, purpose, ai, ei), rows.getBytes(3))), ai, ei)
                }
            }
        }
    }

    private fun consume(connection: Connection, id: String, purpose: String, proof: String): Challenge? {
        val ci = cipher.index("challenge-$purpose", id)
        // UPDATE takes the row lock and counts malformed guesses too. Failure commits the counter.
        val hash = connection.prepareStatement("UPDATE account_recovery_challenges SET attempts = attempts + 1 WHERE challenge_index = ? AND purpose = ? AND expires_at > clock_timestamp() AND attempts < 5 RETURNING proof_hash").use {
            it.setString(1, ci); it.setString(2, purpose)
            it.executeQuery().use { rows -> if (rows.next()) rows.getString(1) else null }
        } ?: return null
        if (!MessageDigest.isEqual(hash.toByteArray(), cipher.index("proof-$purpose", "$id\u0000$proof").toByteArray())) return null
        // Read after increment, including a successful fifth attempt.
        val challenge = connection.prepareStatement("SELECT account_index, email_index, sealed_context FROM account_recovery_challenges WHERE challenge_index = ?").use {
            it.setString(1, ci)
            it.executeQuery().use { rows ->
                check(rows.next())
                val ai = rows.getString(1); val ei = rows.getString(2)
                Challenge(Json.decodeFromString<Context>(cipher.open(challengeAad(ci, purpose, ai, ei), rows.getBytes(3))), ai, ei)
            }
        }
        connection.prepareStatement("DELETE FROM account_recovery_challenges WHERE challenge_index = ?").use {
            it.setString(1, ci); it.executeUpdate()
        }
        return challenge
    }

    private fun quota(connection: Connection, purpose: String, value: String, limit: Int): Boolean {
        val hour = System.currentTimeMillis() / 3_600_000
        val qi = cipher.index("quota-$purpose", "$hour\u0000$value")
        return connection.prepareStatement("""INSERT INTO account_recovery_quotas(quota_index, used, expires_at)
            VALUES (?, 1, NOW() + INTERVAL '2 hours') ON CONFLICT (quota_index)
            DO UPDATE SET used = account_recovery_quotas.used + 1 WHERE account_recovery_quotas.used < ? RETURNING used""").use {
            it.setString(1, qi); it.setInt(2, limit); it.executeQuery().use { rows -> rows.next() }
        }
    }

    fun deleteAccount(connection: Connection, userId: String) {
        val ai = cipher.index("account", userId)
        deleteChallenges(connection, ai)
        connection.prepareStatement("DELETE FROM account_recovery_receipts WHERE account_index = ?").use {
            it.setString(1, ai); it.executeUpdate()
        }
        connection.prepareStatement("DELETE FROM account_recovery_bindings WHERE account_index = ?").use {
            it.setString(1, ai); it.executeUpdate()
        }
    }

    private fun deleteChallenges(connection: Connection, ai: String) {
        connection.prepareStatement("DELETE FROM account_recovery_challenges WHERE account_index = ?").use {
            it.setString(1, ai); it.executeUpdate()
        }
    }

    private fun <T> transaction(action: (Connection) -> T): T = Database.getConnection().use { connection ->
        connection.autoCommit = false
        try { action(connection).also { connection.commit() } }
        catch (error: Exception) { connection.rollback(); throw error }
        finally { connection.autoCommit = true }
    }

    companion object {
        fun enrollmentPreimage(id: String, context: Context): String = listOf("securechat/recovery-enroll/v1", id, context.nonce,
            context.userId, context.epoch, context.email, context.protocol).joinToString("\n")
        fun completionPreimage(userId: String, request: RecoveryComplete): String = listOf("securechat/recovery-complete/v1",
            request.recoveryToken, request.completionId, userId, request.mode, request.identityProtocol, request.identityPublicKey,
            request.registrationId.toString()).joinToString("\n")
        private fun b64(bytes: ByteArray) = Base64.getEncoder().encodeToString(bytes)
        private fun bindingAad(ai: String, ei: String, version: String) = "recovery-binding/v1\u0000$ai\u0000$ei\u0000$version"
        private fun challengeAad(ci: String, purpose: String, ai: String?, ei: String) = "recovery-challenge/v1\u0000$ci\u0000$purpose\u0000${ai.orEmpty()}\u0000$ei"
    }
}
