package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
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
 * null key id. They are converted atomically when the authenticated account
 * refreshes its own directory identity. Address-book discovery never sends
 * raw/reusable phone hashes and never writes a social graph to this registry.
 */
class UserRegistry(
    private val directory: PrivateDirectoryOprf = PrivateDirectory.oprf,
    private val random: SecureRandom = SecureRandom(),
) {
    private val cacheByDirectoryToken = ConcurrentHashMap<String, RegisteredUser>()
    private val cacheByUserId = ConcurrentHashMap<String, RegisteredUser>()

    /**
     * Uyelik degistikce artan sayac.
     *
     * Snapshot her istekte bastan muhurlenmeye gerek duymaz; onbellek bu
     * sayac degismedigi surece gecerlidir. Sayac opaque'tir, disari verilmez.
     */
    private val membershipVersion = AtomicLong(0)

    fun membershipVersion(): Long = membershipVersion.get()

    init {
        loadFromDb()
    }

    fun registerUser(userId: String): RegisteredUser {
        val candidate = prepareRegistration(userId)
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
    fun prepareRegistration(userId: String): RegisteredUser {
        require(runCatching { UUID.fromString(userId).toString() == userId.lowercase() }.getOrDefault(false)) {
            "Invalid registration user id"
        }
        return RegisteredUser(
            userId = userId,
            // Registration proves control of an e-mail address, not a phone
            // number. A random non-discoverable placeholder prevents the
            // registration endpoint from receiving a deterministic phone
            // hash. The authenticated client replaces it with its finalized
            // OPRF token after registration.
            directoryToken = pendingDirectoryToken(),
            directoryKeyId = null,
        )
    }

    /** Commit sonrasi RAM gorunumunu gunceller. */
    fun cacheRegistered(user: RegisteredUser) {
        cache(user)
        log.info("[R] Yeni private-directory kullanicisi kaydedildi")
    }

    fun insertRegistration(connection: java.sql.Connection, user: RegisteredUser): Boolean =
        insertUser(user, connection)

    /** Re-indexes only the authenticated account with a finalized OPRF token. */
    fun updateOwnDirectoryToken(userId: String, directoryToken: String): RegisteredUser {
        val current = cacheByUserId[userId] ?: findByUserId(userId)
            ?: error("Authenticated directory account does not exist")
        val token = directory.validateToken(directoryToken)
        if (current.directoryToken == token && current.directoryKeyId == directory.keyId) {
            return current
        }
        val owner = cacheByDirectoryToken[token] ?: findByDirectoryToken(token)
        if (owner != null && owner.userId != userId) {
            return reclaimFromLegacyAccount(owner, current, token)
        }
        return replaceDirectoryToken(current, token, directory.keyId)
    }

    /**
     * Numara mesaj alamayan bir hesapta kaldiysa onu yeni hesaba devreder.
     *
     * Iki durum: (1) vodozemac gecisinden beri acilmamis, yalniz libsignal
     * kimligi olan hesap; (2) numarayi alip anahtar yuklemeden yarim kalmis
     * kayit. Ikisine de mesaj sifrelenemez, numarayi tutmalari yalniz
     * sahibini kendi numarasindan mahrum birakir. Sahibi yeni hesapla
     * rehberi senkronladiginda ya da yeniden kayit oldugunda numara burada
     * kendiliginden gecer; kullanicidan bir sey istenmez.
     *
     * Kosul SQL'de, ayni satir kilidi altinda yeniden dogrulanir. Olm
     * kimligi olan hesaptan ve kurtarma ortasindaki hesaptan (kurtarma iki
     * kimlik kolonunu bosaltir, `recovery_identity_pin` yazar) numara
     * alinamaz; o durumda eski davranis gecerlidir.
     */
    private fun reclaimFromLegacyAccount(
        owner: RegisteredUser,
        claimant: RegisteredUser,
        token: String,
    ): RegisteredUser {
        val released = owner.copy(directoryToken = pendingDirectoryToken(), directoryKeyId = null)
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                val releasedRows = connection.prepareStatement(
                    """UPDATE users SET directory_token = ?, directory_key_id = NULL
                       WHERE user_id = ?::uuid AND directory_token = ?
                         AND olm_identity_key IS NULL
                         AND (identity_public_key IS NOT NULL
                              OR recovery_identity_pin IS NULL)""",
                ).use { statement ->
                    statement.setString(1, released.directoryToken)
                    statement.setString(2, owner.userId)
                    statement.setString(3, token)
                    statement.executeUpdate()
                }
                require(releasedRows == 1) {
                    "Directory token is already assigned to another account"
                }
                val claimedRows = connection.prepareStatement(
                    """UPDATE users SET directory_token = ?, directory_key_id = ?
                       WHERE user_id = ?::uuid AND directory_token = ?""",
                ).use { statement ->
                    statement.setString(1, token)
                    statement.setString(2, directory.keyId)
                    statement.setString(3, claimant.userId)
                    statement.setString(4, claimant.directoryToken)
                    statement.executeUpdate()
                }
                check(claimedRows == 1) {
                    "Directory token migration lost its compare-and-set race"
                }
                connection.commit()
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }
        cacheByDirectoryToken.remove(owner.directoryToken, owner)
        cache(released)
        val migrated = claimant.copy(directoryToken = token, directoryKeyId = directory.keyId)
        cacheByDirectoryToken.remove(claimant.directoryToken, claimant)
        cache(migrated)
        log.info("[R] Eski (libsignal) hesabin rehber kaydi yeni hesaba devredildi")
        return migrated
    }

    private fun pendingDirectoryToken(): String {
        val value = ByteArray(PENDING_TOKEN_BYTES).also(random::nextBytes)
        return PENDING_TOKEN_PREFIX + Base64.getUrlEncoder().withoutPadding().encodeToString(value)
    }

    fun privateDirectorySnapshot(): List<RegisteredUser> =
        cacheByUserId.values
            .asSequence()
            .filter { it.directoryKeyId == directory.keyId }
            .sortedBy { it.userId }
            .toList()

    /** Hesabin guncel rehber anahtariyla kayitli girdisi; yoksa null. */
    fun directoryEntryOf(userId: String): RegisteredUser? =
        cacheByUserId[userId]?.takeIf { it.directoryKeyId == directory.keyId }

    fun removeUser(userId: String) {
        val removed = cacheByUserId.remove(userId) ?: return
        cacheByDirectoryToken.remove(removed.directoryToken, removed)
        membershipVersion.incrementAndGet()
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

    private companion object {
        const val PENDING_TOKEN_PREFIX = "pending:"
        const val PENDING_TOKEN_BYTES = 24
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
        membershipVersion.incrementAndGet()
    }
}
