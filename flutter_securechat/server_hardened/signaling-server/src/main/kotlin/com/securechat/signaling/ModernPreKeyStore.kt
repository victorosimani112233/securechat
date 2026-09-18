package com.securechat.signaling

import com.securechat.signaling.db.Database

/** Public PQXDH bundle storage. Private keys and ciphertext never enter it. */
object ModernPreKeyStore {
    data class IdentityKey(val publicKey: ByteArray, val registrationId: Int)
    data class SignedPreKey(val keyId: Int, val publicKey: ByteArray, val signature: ByteArray)
    data class OneTimePreKeyPair(
        val keyId: Int,
        val ecPublicKey: ByteArray,
        val kyberPublicKey: ByteArray,
        val kyberSignature: ByteArray,
    )
    data class KyberPreKey(
        val keyId: Int,
        val publicKey: ByteArray,
        val signature: ByteArray,
        val lastResort: Boolean,
    )
    data class Bundle(
        val identityKey: IdentityKey,
        val signedPreKey: SignedPreKey,
        val oneTimePreKey: OneTimePreKeyPair?,
        val kyberPreKey: KyberPreKey,
    )

    fun uploadBundle(
        userId: String,
        identityPublicKey: ByteArray,
        registrationId: Int,
        signedPreKey: SignedPreKey,
        oneTimePreKeys: List<OneTimePreKeyPair>,
        lastResortKyberPreKey: KyberPreKey,
    ) {
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                connection.prepareStatement(
                    "SELECT user_id FROM users WHERE user_id = ?::uuid FOR UPDATE",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        check(rows.next()) { "Unknown account cannot upload modern prekeys" }
                    }
                }
                val oldIdentity = connection.prepareStatement(
                    "SELECT identity_public_key FROM modern_prekey_bundles WHERE user_id = ?::uuid",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        if (rows.next()) rows.getBytes(1) else null
                    }
                }
                if (oldIdentity != null && !oldIdentity.contentEquals(identityPublicKey)) {
                    connection.prepareStatement(
                        "DELETE FROM modern_one_time_prekeys WHERE user_id = ?::uuid",
                    ).use { statement ->
                        statement.setString(1, userId)
                        statement.executeUpdate()
                    }
                }
                connection.prepareStatement(
                    """INSERT INTO modern_prekey_bundles (
                           user_id, identity_public_key, registration_id,
                           signed_prekey_id, signed_prekey_public, signed_prekey_signature
                       ) VALUES (?::uuid, ?, ?, ?, ?, ?)
                       ON CONFLICT (user_id) DO UPDATE SET
                           identity_public_key = EXCLUDED.identity_public_key,
                           registration_id = EXCLUDED.registration_id,
                           signed_prekey_id = EXCLUDED.signed_prekey_id,
                           signed_prekey_public = EXCLUDED.signed_prekey_public,
                           signed_prekey_signature = EXCLUDED.signed_prekey_signature""",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.setBytes(2, identityPublicKey)
                    statement.setInt(3, registrationId)
                    statement.setInt(4, signedPreKey.keyId)
                    statement.setBytes(5, signedPreKey.publicKey)
                    statement.setBytes(6, signedPreKey.signature)
                    statement.executeUpdate()
                }
                connection.prepareStatement(
                    """INSERT INTO modern_last_resort_kyber_prekeys
                           (user_id, key_id, public_key, signature)
                       VALUES (?::uuid, ?, ?, ?)
                       ON CONFLICT (user_id) DO UPDATE SET
                           key_id = EXCLUDED.key_id,
                           public_key = EXCLUDED.public_key,
                           signature = EXCLUDED.signature""",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.setInt(2, lastResortKyberPreKey.keyId)
                    statement.setBytes(3, lastResortKyberPreKey.publicKey)
                    statement.setBytes(4, lastResortKyberPreKey.signature)
                    statement.executeUpdate()
                }
                val newKeyCount = validateAndCountNewKeys(connection, userId, oneTimePreKeys)
                requirePoolCapacity(connection, userId, newKeyCount)
                insertOneTimePreKeys(connection, userId, oneTimePreKeys)
                connection.commit()
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }
    }

    fun addOneTimePreKeys(userId: String, keys: List<OneTimePreKeyPair>) {
        if (keys.isEmpty()) return
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                connection.prepareStatement(
                    "SELECT user_id FROM modern_prekey_bundles WHERE user_id = ?::uuid FOR UPDATE",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        check(rows.next()) { "Modern bundle is not initialized" }
                    }
                }
                val newKeyCount = validateAndCountNewKeys(connection, userId, keys)
                requirePoolCapacity(connection, userId, newKeyCount)
                insertOneTimePreKeys(connection, userId, keys)
                connection.commit()
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }
    }

    fun fetchBundle(userId: String): Bundle? =
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                    // Hesap varligi kilitsiz dogrulanir. `FOR UPDATE`, hedef
                    // hesabin satirini butun bundle fetch'i boyunca tutuyordu:
                    // ayni kisiye es zamanli gelen istekler sirayla bekliyor ve
                    // one-time prekey secimindeki `SKIP LOCKED` anlamsizlasiyordu.
                    // Tek kullanimlik anahtarin tekilligini zaten DELETE ... RETURNING
                    // saglar; hesap arada silinirse FK cascade prekey'leri de siler
                    // ve sorgu dogal olarak bos doner.
                    connection.prepareStatement(
                        "SELECT 1 FROM users WHERE user_id = ?::uuid",
                    ).use { statement ->
                        statement.setString(1, userId)
                        statement.executeQuery().use { rows -> if (!rows.next()) return null }
                    }
                    val base = connection.prepareStatement(
                        """SELECT identity_public_key, registration_id, signed_prekey_id,
                                  signed_prekey_public, signed_prekey_signature
                           FROM modern_prekey_bundles WHERE user_id = ?::uuid""",
                    ).use { statement ->
                        statement.setString(1, userId)
                        statement.executeQuery().use { rows ->
                            if (!rows.next()) return null
                            Pair(
                                IdentityKey(rows.getBytes(1), rows.getInt(2)),
                                SignedPreKey(rows.getInt(3), rows.getBytes(4), rows.getBytes(5)),
                            )
                        }
                    }
                    val oneTime = connection.prepareStatement(
                        """WITH next_key AS (
                               SELECT user_id, key_id FROM modern_one_time_prekeys
                               WHERE user_id = ?::uuid ORDER BY key_id LIMIT 1
                               FOR UPDATE SKIP LOCKED
                           )
                           DELETE FROM modern_one_time_prekeys AS keys
                           USING next_key
                           WHERE keys.user_id = next_key.user_id AND keys.key_id = next_key.key_id
                           RETURNING keys.key_id, keys.ec_public_key,
                                     keys.kyber_public_key, keys.kyber_signature""",
                    ).use { statement ->
                        statement.setString(1, userId)
                        statement.executeQuery().use { rows ->
                            if (rows.next()) {
                                OneTimePreKeyPair(
                                    rows.getInt(1), rows.getBytes(2),
                                    rows.getBytes(3), rows.getBytes(4),
                                )
                            } else null
                        }
                    }
                    val kyber = oneTime?.let {
                        KyberPreKey(it.keyId, it.kyberPublicKey, it.kyberSignature, false)
                    } ?: connection.prepareStatement(
                        """SELECT key_id, public_key, signature
                           FROM modern_last_resort_kyber_prekeys WHERE user_id = ?::uuid""",
                    ).use { statement ->
                        statement.setString(1, userId)
                        statement.executeQuery().use { rows ->
                            if (!rows.next()) return null
                            KyberPreKey(rows.getInt(1), rows.getBytes(2), rows.getBytes(3), true)
                        }
                    }
                    connection.commit()
                    Bundle(base.first, base.second, oneTime, kyber)
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }

    fun unconsumedCount(userId: String): Int =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT COUNT(*) FROM modern_one_time_prekeys WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows -> if (rows.next()) rows.getInt(1) else 0 }
            }
        }

    fun hasBundle(userId: String): Boolean =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT EXISTS (
                       SELECT 1 FROM modern_prekey_bundles AS bundle
                       JOIN modern_last_resort_kyber_prekeys AS kyber USING (user_id)
                       WHERE bundle.user_id = ?::uuid
                   )""",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows -> rows.next() && rows.getBoolean(1) }
            }
        }

    /** Reads only the public identity; unlike fetchBundle it consumes no OTPK. */
    fun identityFor(userId: String): IdentityKey? =
        Database.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT identity_public_key, registration_id
                   FROM modern_prekey_bundles WHERE user_id = ?::uuid""",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows ->
                    if (rows.next()) IdentityKey(rows.getBytes(1), rows.getInt(2)) else null
                }
            }
        }

    private fun insertOneTimePreKeys(
        connection: java.sql.Connection,
        userId: String,
        keys: List<OneTimePreKeyPair>,
    ) {
        if (keys.isEmpty()) return
        connection.prepareStatement(
            """INSERT INTO modern_one_time_prekeys
                   (user_id, key_id, ec_public_key, kyber_public_key, kyber_signature)
               VALUES (?::uuid, ?, ?, ?, ?)
               ON CONFLICT (user_id, key_id) DO NOTHING""",
        ).use { statement ->
            keys.forEach { key ->
                statement.setString(1, userId)
                statement.setInt(2, key.keyId)
                statement.setBytes(3, key.ecPublicKey)
                statement.setBytes(4, key.kyberPublicKey)
                statement.setBytes(5, key.kyberSignature)
                statement.addBatch()
            }
            statement.executeBatch()
        }
    }

    private fun validateAndCountNewKeys(
        connection: java.sql.Connection,
        userId: String,
        keys: List<OneTimePreKeyPair>,
    ): Int {
        check(keys.map { it.keyId }.toSet().size == keys.size) {
            "Modern pre-key batch contains duplicate IDs"
        }
        if (keys.isEmpty()) return 0
        val placeholders = List(keys.size) { "?" }.joinToString(",")
        val existing = connection.prepareStatement(
            """SELECT key_id, ec_public_key, kyber_public_key, kyber_signature
               FROM modern_one_time_prekeys
               WHERE user_id = ?::uuid AND key_id IN ($placeholders)""",
        ).use { statement ->
            statement.setString(1, userId)
            keys.forEachIndexed { index, key -> statement.setInt(index + 2, key.keyId) }
            statement.executeQuery().use { rows ->
                buildMap {
                    while (rows.next()) {
                        put(
                            rows.getInt(1),
                            OneTimePreKeyPair(
                                rows.getInt(1),
                                rows.getBytes(2),
                                rows.getBytes(3),
                                rows.getBytes(4),
                            ),
                        )
                    }
                }
            }
        }
        keys.forEach { incoming ->
            val stored = existing[incoming.keyId] ?: return@forEach
            check(
                stored.ecPublicKey.contentEquals(incoming.ecPublicKey) &&
                    stored.kyberPublicKey.contentEquals(incoming.kyberPublicKey) &&
                    stored.kyberSignature.contentEquals(incoming.kyberSignature),
            ) { "Modern pre-key ID already exists with different material" }
        }
        return keys.count { it.keyId !in existing }
    }

    private fun requirePoolCapacity(
        connection: java.sql.Connection,
        userId: String,
        incoming: Int,
    ) {
        val current = connection.prepareStatement(
            "SELECT COUNT(*) FROM modern_one_time_prekeys WHERE user_id = ?::uuid",
        ).use { statement ->
            statement.setString(1, userId)
            statement.executeQuery().use { rows -> if (rows.next()) rows.getInt(1) else 0 }
        }
        check(current + incoming <= MAX_STORED_ONE_TIME_PREKEYS) {
            "Modern pre-key pool capacity exceeded"
        }
    }
}
