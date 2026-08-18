package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.util.concurrent.ConcurrentHashMap
import java.util.UUID
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("UserRegistry")

data class RegisteredUser(
    val userId: String,
    val directoryToken: String,
    val directoryKeyId: String?,
)

class DirectoryIdentityAlreadyRegisteredException : IllegalStateException(
    "Private directory identity is already registered",
)

/**
 * Account registry backed by private-directory OPRF tokens.
 *
 * Legacy rows contain a server-HMAC blind index in `directory_token` and a
 * null key id. They are converted atomically when that account next registers
 * or refreshes its own directory identity. Address-book discovery never sends
 * raw/reusable phone hashes and never writes a social graph to this registry.
 */
class UserRegistry(
    private val directory: PrivateDirectoryOprf = PrivateDirectory.oprf,
    private val legacyIndex: (String) -> String = {
        ServerPrivacy.blindIndex("phone-discovery", it)
    },
) {
    private val cacheByDirectoryToken = ConcurrentHashMap<String, RegisteredUser>()
    private val cacheByUserId = ConcurrentHashMap<String, RegisteredUser>()

    init {
        loadFromDb()
    }

    fun registerUserByHash(userId: String, phoneHash: String): RegisteredUser {
        val candidate = prepareRegistration(userId, phoneHash)
        if (!insertUser(candidate, transaction = null)) {
            throw DirectoryIdentityAlreadyRegisteredException()
        }
        cacheRegistered(candidate)
        return candidate
    }

    /**
     * Kayit adayini dogrular ve cakisma kontrollerini yapar; hicbir sey
     * yazmaz. Yazma adimi cagirana birakildigi icin kayit, registration
     * grant'in tuketilmesiyle ayni transaction icinde yapilabilir.
     */
    fun prepareRegistration(userId: String, phoneHash: String): RegisteredUser {
        require(runCatching { UUID.fromString(userId).toString() == userId.lowercase() }.getOrDefault(false)) {
            "Invalid registration user id"
        }
        val token = directory.tokenForPhoneHash(phoneHash)
        val current = cacheByDirectoryToken[token]
        if (current != null && current.directoryKeyId == directory.keyId) {
            // A verified e-mail is not proof of control over this phone
            // identity. Returning the existing UUID/JWT here would turn
            // registration into an account-takeover endpoint.
            throw DirectoryIdentityAlreadyRegisteredException()
        }

        val oldIndex = legacyIndex(phoneHash)
        val legacy = cacheByDirectoryToken[oldIndex]
        if (legacy != null && legacy.directoryKeyId == null) {
            // Legacy identities may be migrated only by an already
            // authenticated account through updateOwnDirectoryToken().
            throw DirectoryIdentityAlreadyRegisteredException()
        }

        return RegisteredUser(
            userId = userId,
            directoryToken = token,
            directoryKeyId = directory.keyId,
        )
    }

    /** Commit sonrasi RAM gorunumunu gunceller. */
    fun cacheRegistered(user: RegisteredUser) {
        cache(user)
        log.info("[R] Yeni private-directory kullanicisi kaydedildi")
    }

    fun insertRegistration(connection: java.sql.Connection, user: RegisteredUser): Boolean =
        insertUser(user, connection)

    /** Re-indexes only the authenticated account's own declared phone hash. */
    fun updateOwnDirectoryToken(userId: String, phoneHash: String): RegisteredUser {
        val current = cacheByUserId[userId] ?: findByUserId(userId)
            ?: error("Authenticated directory account does not exist")
        val token = directory.tokenForPhoneHash(phoneHash)
        if (current.directoryToken == token && current.directoryKeyId == directory.keyId) {
            return current
        }
        val owner = cacheByDirectoryToken[token] ?: findByDirectoryToken(token)
        require(owner == null || owner.userId == userId) {
            "Directory token is already assigned to another account"
        }
        return replaceDirectoryToken(current, token, directory.keyId)
    }

    fun privateDirectorySnapshot(): List<RegisteredUser> =
        cacheByUserId.values
            .asSequence()
            .filter { it.directoryKeyId == directory.keyId }
            .sortedBy { it.userId }
            .toList()

    fun removeUser(userId: String) {
        val removed = cacheByUserId.remove(userId) ?: return
        cacheByDirectoryToken.remove(removed.directoryToken, removed)
    }

    fun getUserCount(): Int = cacheByUserId.size

    /**
     * Hesabin var olup olmadigi. Registry startup'ta PostgreSQL'den yuklenir
     * ve hesap silmede guncellenir; bu kontrol RAM'den yapilir.
     */
    fun exists(userId: String): Boolean = cacheByUserId.containsKey(userId)

    private fun insertUser(user: RegisteredUser, transaction: java.sql.Connection?): Boolean {
        val insert = { connection: java.sql.Connection ->
            connection.prepareStatement(
                """INSERT INTO users (user_id, directory_token, directory_key_id)
                   VALUES (?::uuid, ?, ?) ON CONFLICT DO NOTHING""",
            ).use { statement ->
                statement.setString(1, user.userId)
                statement.setString(2, user.directoryToken)
                statement.setString(3, user.directoryKeyId)
                statement.executeUpdate() == 1
            }
        }
        return if (transaction != null) {
            insert(transaction)
        } else {
            Database.getConnection().use(insert)
        }
    }

    private fun replaceDirectoryToken(
        user: RegisteredUser,
        token: String,
        keyId: String,
    ): RegisteredUser {
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """UPDATE users
                   SET directory_token = ?, directory_key_id = ?
                   WHERE user_id = ?::uuid AND directory_token = ?""",
            ).use { statement ->
                statement.setString(1, directory.validateToken(token))
                statement.setString(2, keyId)
                statement.setString(3, user.userId)
                statement.setString(4, user.directoryToken)
                check(statement.executeUpdate() == 1) {
                    "Directory token migration lost its compare-and-set race"
                }
            }
        }
        val migrated = user.copy(directoryToken = token, directoryKeyId = keyId)
        cacheByDirectoryToken.remove(user.directoryToken, user)
        cache(migrated)
        return migrated
    }

    private fun findByDirectoryToken(token: String): RegisteredUser? =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT user_id, directory_token, directory_key_id
                   FROM users WHERE directory_token = ?""",
            ).use { statement ->
                statement.setString(1, token)
                statement.executeQuery().use(::readOne)
            }
        }

    private fun findByUserId(userId: String): RegisteredUser? =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT user_id, directory_token, directory_key_id
                   FROM users WHERE user_id = ?::uuid""",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use(::readOne)
            }
        }

    private fun readOne(rows: java.sql.ResultSet): RegisteredUser? =
        if (!rows.next()) null else RegisteredUser(
            userId = rows.getString("user_id"),
            directoryToken = rows.getString("directory_token"),
            directoryKeyId = rows.getString("directory_key_id"),
        )

    private fun loadFromDb() {
        Database.getConnection().use { connection ->
            connection.createStatement().use { statement ->
                statement.executeQuery(
                    "SELECT user_id, directory_token, directory_key_id FROM users",
                ).use { rows ->
                    var count = 0
                    while (rows.next()) {
                        cache(
                            RegisteredUser(
                                userId = rows.getString("user_id"),
                                directoryToken = rows.getString("directory_token"),
                                directoryKeyId = rows.getString("directory_key_id"),
                            ),
                        )
                        count++
                    }
                    log.info("[R] Private directory registry hazir; count={}", count)
                }
            }
        }
    }

    private fun cache(user: RegisteredUser) {
        cacheByDirectoryToken[user.directoryToken] = user
        cacheByUserId[user.userId] = user
    }
}
