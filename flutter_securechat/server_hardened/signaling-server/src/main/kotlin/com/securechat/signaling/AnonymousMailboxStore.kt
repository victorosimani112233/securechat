package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.security.MessageDigest

/** Self-owned, rotating destination capability for unidentified delivery. */
object AnonymousMailboxStore {
    data class Registration(
        val mailboxId: String,
        val writeKey: String,
        val protocolVersion: Int,
        val generation: Int,
    )

    private val capabilityPattern = Regex("^[A-Za-z0-9_-]{43}$")

    /**
     * Emekli bir mailbox indeksinin yeniden kaydedilemeyecegi sure.
     *
     * Bir gonderen rotasyonu ancak alicidan yeni capability'yi ogrendiginde
     * fark eder; bu pencere kapanana kadar eski adres kimseye verilmemelidir.
     * Offline kuyrugun mutlak ust siniri bir saattir, bu yuzden otuz gun
     * fazlasiyla guvenli bir ust sinirdir ve tombstone satiri hesapla
     * iliskilendirilmedigi icin kalici bir gizlilik maliyeti tasimaz.
     */
    private const val RETIREMENT_SECONDS = 30L * 24L * 60L * 60L

    fun register(userId: String, registration: Registration) {
        require(registration.protocolVersion == 1) { "Unsupported mailbox protocol" }
        require(capabilityPattern.matches(registration.mailboxId)) { "Invalid mailbox ID" }
        require(capabilityPattern.matches(registration.writeKey)) { "Invalid mailbox write key" }
        require(registration.generation in 1..Int.MAX_VALUE) { "Invalid mailbox generation" }
        val mailboxIndex = mailboxIndex(registration.mailboxId)
        val writeKeyIndex = writeKeyIndex(registration.mailboxId, registration.writeKey)
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                connection.prepareStatement(
                    "SELECT user_id FROM users WHERE user_id = ?::uuid FOR UPDATE",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        check(rows.next()) { "Unknown account cannot register a mailbox" }
                    }
                }
                // Emekli bir capability yeniden kaydedilemez. Aksi halde
                // rotasyondan sonra eski mailbox'i bilen bir peer onu kendi
                // uzerine alip o adrese gonderilen zarflari toplayabilirdi.
                connection.prepareStatement(
                    """SELECT 1 FROM sealed_sender_retired_mailboxes
                       WHERE mailbox_index = ? AND retired_until > NOW()""",
                ).use { statement ->
                    statement.setString(1, mailboxIndex)
                    statement.executeQuery().use { rows ->
                        require(!rows.next()) { "Retired mailbox capability" }
                    }
                }
                var shouldWrite = true
                var retiredIndex: String? = null
                connection.prepareStatement(
                    """SELECT mailbox_index, write_key_index, generation
                       FROM sealed_sender_mailboxes
                       WHERE user_id = ?::uuid
                       FOR UPDATE""",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        if (rows.next()) {
                            val currentGeneration = rows.getInt("generation")
                            val currentMailboxIndex = rows.getString("mailbox_index")
                            require(registration.generation >= currentGeneration) {
                                "Stale mailbox generation"
                            }
                            if (registration.generation == currentGeneration) {
                                require(
                                    MessageDigest.isEqual(
                                        currentMailboxIndex.toByteArray(Charsets.US_ASCII),
                                        mailboxIndex.toByteArray(Charsets.US_ASCII),
                                    ) && MessageDigest.isEqual(
                                        rows.getString("write_key_index").toByteArray(Charsets.US_ASCII),
                                        writeKeyIndex.toByteArray(Charsets.US_ASCII),
                                    ),
                                ) { "Conflicting mailbox generation" }
                                shouldWrite = false
                            } else if (currentMailboxIndex != mailboxIndex) {
                                retiredIndex = currentMailboxIndex
                            }
                        }
                    }
                }
                if (shouldWrite) {
                    retiredIndex?.let { previous ->
                        connection.prepareStatement(
                            """INSERT INTO sealed_sender_retired_mailboxes
                                   (mailbox_index, retired_until)
                               VALUES (?, NOW() + make_interval(secs => ?))
                               ON CONFLICT (mailbox_index) DO UPDATE SET
                                   retired_until = GREATEST(
                                       sealed_sender_retired_mailboxes.retired_until,
                                       EXCLUDED.retired_until
                                   )""",
                        ).use { statement ->
                            statement.setString(1, previous)
                            statement.setDouble(2, RETIREMENT_SECONDS.toDouble())
                            statement.executeUpdate()
                        }
                    }
                    connection.prepareStatement(
                        """INSERT INTO sealed_sender_mailboxes
                               (user_id, mailbox_index, write_key_index, protocol_version, generation)
                           VALUES (?::uuid, ?, ?, 1, ?)
                           ON CONFLICT (user_id) DO UPDATE SET
                               mailbox_index = EXCLUDED.mailbox_index,
                               write_key_index = EXCLUDED.write_key_index,
                               protocol_version = EXCLUDED.protocol_version,
                               generation = EXCLUDED.generation""",
                    ).use { statement ->
                        statement.setString(1, userId)
                        statement.setString(2, mailboxIndex)
                        statement.setString(3, writeKeyIndex)
                        statement.setInt(4, registration.generation)
                        statement.executeUpdate()
                    }
                }
                connection.commit()
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }
    }

    /**
     * A single indexed query avoids a mailbox-existence branch before access
     * verification. The caller gets no distinction between missing and wrong.
     */
    fun authorize(mailboxId: String, writeKey: String): String? {
        if (!capabilityPattern.matches(mailboxId) || !capabilityPattern.matches(writeKey)) {
            return null
        }
        val expectedMailbox = mailboxIndex(mailboxId)
        val expectedWriteKey = writeKeyIndex(mailboxId, writeKey)
        return Database.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT user_id::text, write_key_index
                   FROM sealed_sender_mailboxes
                   WHERE mailbox_index = ? AND write_key_index = ?""",
            ).use { statement ->
                statement.setString(1, expectedMailbox)
                statement.setString(2, expectedWriteKey)
                statement.executeQuery().use { rows ->
                    if (!rows.next()) null
                    else rows.getString(1).takeIf {
                        MessageDigest.isEqual(
                            rows.getString(2).toByteArray(Charsets.US_ASCII),
                            expectedWriteKey.toByteArray(Charsets.US_ASCII),
                        )
                    }
                }
            }
        }
    }

    fun hasMailbox(userId: String): Boolean = Database.getConnection().use { connection ->
        connection.prepareStatement(
            "SELECT EXISTS (SELECT 1 FROM sealed_sender_mailboxes WHERE user_id = ?::uuid)",
        ).use { statement ->
            statement.setString(1, userId)
            statement.executeQuery().use { rows -> rows.next() && rows.getBoolean(1) }
        }
    }

    /**
     * Suresi dolmus tombstone'lari siler.
     *
     * Kayit sonsuza kadar tutulmaz: emeklilik suresi, gonderenlerin eski
     * capability'yi birakmasi icin gereken sureyi kapsar. Sonrasinda satir
     * gereksiz bir kalici izdir ve temizlenir.
     */
    fun purgeExpiredRetirements(): Int = Database.getConnection().use { connection ->
        connection.prepareStatement(
            "DELETE FROM sealed_sender_retired_mailboxes WHERE retired_until <= NOW()",
        ).use { statement -> statement.executeUpdate() }
    }

    private fun mailboxIndex(mailboxId: String): String =
        ServerPrivacy.blindIndex("sealed-mailbox", mailboxId)

    private fun writeKeyIndex(mailboxId: String, writeKey: String): String =
        ServerPrivacy.blindIndex("sealed-write", "$mailboxId\u0000$writeKey")
}
