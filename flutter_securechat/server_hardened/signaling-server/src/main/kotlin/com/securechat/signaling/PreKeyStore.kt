package com.securechat.signaling

import com.securechat.signaling.db.Database
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("PreKeyStore")

/**
 * Signal Protocol PreKey bundle server-side store.
 *
 * Akis:
 *   1. Kayit sirasinda client identity_public_key + registration_id + signed_prekey + 100 one_time_prekey upload eder.
 *   2. Baska bir client `/api/v1/users/{userId}/prekeys` cagirinca:
 *      - identity_public_key (sabit)
 *      - signed_prekey (rotation gerekirse client guncelleyebilir)
     *      - bir tane one_time_prekey (atomik silinip yalniz bir kez verilir)
 *   3. one_time_prekey havuzu azalinca client yenilerini upload eder.
 *
 * Buradaki sema sadece SUNUCU SIDE STORAGE — gercek Signal Protocol algoritmasi client'ta.
 */
object PreKeyStore {

    data class IdentityKey(val publicKey: ByteArray, val registrationId: Int)
    data class SignedPreKey(val keyId: Int, val publicKey: ByteArray, val signature: ByteArray)
    data class OneTimePreKey(val keyId: Int, val publicKey: ByteArray)
    data class PreKeyBundle(
        val identityKey: IdentityKey,
        val signedPreKey: SignedPreKey,
        val oneTimePreKey: OneTimePreKey?
    )

    /**
     * Identity key ve registration_id kaydeder/gunceller.
     *
     * KRITIK: Identity degisirse (client reinstall sonrasi yeni keypair uretti),
     * mevcut signed_prekeys ve one_time_prekeys eski identity'ye ait private key'lerle
     * eslesir — yeni identity ile X3DH yapilirsa mismatch olur ve "No valid sessions"
     * hatasi alinir. Bu yuzden identity degisikligini tespit edip eski prekey'leri
     * atomik olarak silmek zorundayiz. Sonraki client upload'u taze prekey'ler ile
     * dolduracak.
     *
     * Identity ayni kaliyorsa (no-op update) prekey'lere dokunmayiz — replenish'i bozmamak icin.
     */
    fun setIdentityKey(userId: String, publicKey: ByteArray, registrationId: Int) {
        try {
            Database.getConnection().use { conn ->
                conn.autoCommit = false
                try {
                    // Mevcut identity'yi oku — gercekten degisip degismedigini kontrol et
                    val oldKey: ByteArray? = conn.prepareStatement(
                        "SELECT identity_public_key FROM users WHERE user_id = ?::uuid"
                    ).use { stmt ->
                        stmt.setString(1, userId)
                        stmt.executeQuery().use { rs ->
                            if (rs.next()) rs.getBytes("identity_public_key") else null
                        }
                    }

                    conn.prepareStatement(
                        "UPDATE users SET identity_public_key = ?, registration_id = ? WHERE user_id = ?::uuid"
                    ).use { stmt ->
                        stmt.setBytes(1, publicKey)
                        stmt.setInt(2, registrationId)
                        stmt.setString(3, userId)
                        stmt.executeUpdate()
                    }

                    val identityChanged = oldKey != null && !oldKey.contentEquals(publicKey)
                    if (identityChanged) {
                        // Eski identity'ye ait prekey'leri tamamen sil — yeni upload taze setle dolduracak.
                        val otpkDeleted = conn.prepareStatement(
                            "DELETE FROM one_time_prekeys WHERE user_id = ?::uuid"
                        ).use { stmt ->
                            stmt.setString(1, userId)
                            stmt.executeUpdate()
                        }
                        val spkDeleted = conn.prepareStatement(
                            "DELETE FROM signed_prekeys WHERE user_id = ?::uuid"
                        ).use { stmt ->
                            stmt.setString(1, userId)
                            stmt.executeUpdate()
                        }
                        log.warn(
                            "[PreKey] Identity degisti; eski OTPK={} SPK={} silindi — taze upload bekleniyor",
                            otpkDeleted, spkDeleted
                        )
                    }
                    conn.commit()
                } catch (e: Exception) {
                    conn.rollback(); throw e
                } finally {
                    conn.autoCommit = true
                }
            }
        } catch (e: Exception) {
            log.error("[PreKey] Identity key kaydedilemedi: {}", e.javaClass.simpleName)
            throw e
        }
    }

    fun setSignedPreKey(userId: String, key: SignedPreKey) {
        try {
            Database.getConnection().use { conn ->
                conn.autoCommit = false
                try {
                    // Eski signed prekey'leri sil (sadece bir tane aktif)
                    conn.prepareStatement("DELETE FROM signed_prekeys WHERE user_id = ?::uuid").use { stmt ->
                        stmt.setString(1, userId)
                        stmt.executeUpdate()
                    }
                    conn.prepareStatement(
                        "INSERT INTO signed_prekeys (user_id, key_id, public_key, signature) VALUES (?::uuid, ?, ?, ?)"
                    ).use { stmt ->
                        stmt.setString(1, userId)
                        stmt.setInt(2, key.keyId)
                        stmt.setBytes(3, key.publicKey)
                        stmt.setBytes(4, key.signature)
                        stmt.executeUpdate()
                    }
                    conn.commit()
                } catch (e: Exception) {
                    conn.rollback(); throw e
                } finally {
                    conn.autoCommit = true
                }
            }
        } catch (e: Exception) {
            log.error("[PreKey] Signed prekey kaydedilemedi: {}", e.javaClass.simpleName)
            throw e
        }
    }

    /**
     * Identity, signed prekey ve one-time prekey'leri **tek transaction**
     * icinde yazar.
     *
     * Onceki akista uc ayri transaction vardi: aradaki bir hata karisik bir
     * bundle birakabiliyordu (or. yeni identity key ile eski signed prekey).
     * Onu ceken bir peer hicbir zaman cozemeyecegi bir oturum kurardi.
     *
     * Hesap satiri `FOR UPDATE` ile kilitlenir; ayni hesap icin es zamanli
     * iki upload birbirinin yarisini gormez.
     */
    fun uploadBundle(
        userId: String,
        identityPublicKey: ByteArray,
        registrationId: Int,
        signedPreKey: SignedPreKey,
        oneTimePreKeys: List<OneTimePreKey>,
    ) {
        try {
            Database.getConnection().use { conn ->
                conn.autoCommit = false
                try {
                    val locked = conn.prepareStatement(
                        "SELECT identity_public_key FROM users WHERE user_id = ?::uuid FOR UPDATE",
                    ).use { stmt ->
                        stmt.setString(1, userId)
                        stmt.executeQuery().use { rows ->
                            if (!rows.next()) null else rows.getBytes("identity_public_key")
                        }
                    }

                    conn.prepareStatement(
                        "UPDATE users SET identity_public_key = ?, registration_id = ? " +
                            "WHERE user_id = ?::uuid",
                    ).use { stmt ->
                        stmt.setBytes(1, identityPublicKey)
                        stmt.setInt(2, registrationId)
                        stmt.setString(3, userId)
                        check(stmt.executeUpdate() == 1) { "Unknown account cannot upload prekeys" }
                    }

                    val identityChanged = locked != null && !locked.contentEquals(identityPublicKey)
                    if (identityChanged) {
                        // Eski identity'ye ait materyal ayni transaction icinde
                        // silinir; yarim kalmis bir gecis olusamaz.
                        conn.prepareStatement(
                            "DELETE FROM one_time_prekeys WHERE user_id = ?::uuid",
                        ).use { stmt ->
                            stmt.setString(1, userId)
                            stmt.executeUpdate()
                        }
                    }

                    conn.prepareStatement(
                        "DELETE FROM signed_prekeys WHERE user_id = ?::uuid",
                    ).use { stmt ->
                        stmt.setString(1, userId)
                        stmt.executeUpdate()
                    }
                    conn.prepareStatement(
                        "INSERT INTO signed_prekeys (user_id, key_id, public_key, signature) " +
                            "VALUES (?::uuid, ?, ?, ?)",
                    ).use { stmt ->
                        stmt.setString(1, userId)
                        stmt.setInt(2, signedPreKey.keyId)
                        stmt.setBytes(3, signedPreKey.publicKey)
                        stmt.setBytes(4, signedPreKey.signature)
                        stmt.executeUpdate()
                    }

                    if (oneTimePreKeys.isNotEmpty()) {
                        conn.prepareStatement(
                            "INSERT INTO one_time_prekeys (user_id, key_id, public_key) " +
                                "VALUES (?::uuid, ?, ?) ON CONFLICT (user_id, key_id) DO NOTHING",
                        ).use { stmt ->
                            for (key in oneTimePreKeys) {
                                stmt.setString(1, userId)
                                stmt.setInt(2, key.keyId)
                                stmt.setBytes(3, key.publicKey)
                                stmt.addBatch()
                            }
                            stmt.executeBatch()
                        }
                    }
                    conn.commit()
                    log.info(
                        "[PreKey] Bundle tek transaction'da yazildi; oneTime={}",
                        oneTimePreKeys.size,
                    )
                } catch (e: Exception) {
                    conn.rollback()
                    throw e
                } finally {
                    conn.autoCommit = true
                }
            }
        } catch (e: Exception) {
            log.error("[PreKey] Bundle upload hatasi: {}", e.javaClass.simpleName)
            throw e
        }
    }

    fun addOneTimePreKeys(userId: String, keys: List<OneTimePreKey>) {
        if (keys.isEmpty()) return
        try {
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "INSERT INTO one_time_prekeys (user_id, key_id, public_key) VALUES (?::uuid, ?, ?) ON CONFLICT (user_id, key_id) DO NOTHING"
                ).use { stmt ->
                    for (k in keys) {
                        stmt.setString(1, userId)
                        stmt.setInt(2, k.keyId)
                        stmt.setBytes(3, k.publicKey)
                        stmt.addBatch()
                    }
                    stmt.executeBatch()
                }
            }
            log.info("[PreKey] {} adet one-time prekey eklendi", keys.size)
        } catch (e: Exception) {
            log.error("[PreKey] One-time prekey eklenemedi: {}", e.javaClass.simpleName)
            throw e
        }
    }

    /**
     * Diger bir client baska bir kullanicinin bundle'ini ister.
     * One-time prekey atomik olarak consume edilir (CTE ile race-condition guvenli).
     */
    fun fetchBundle(userId: String): PreKeyBundle? {
        try {
            Database.getConnection().use { conn ->
                // Identity key
                val (idKey, regId) = conn.prepareStatement(
                    "SELECT identity_public_key, registration_id FROM users WHERE user_id = ?::uuid"
                ).use { stmt ->
                    stmt.setString(1, userId)
                    val rs = stmt.executeQuery()
                    if (!rs.next()) return null
                    val key = rs.getBytes("identity_public_key") ?: return null
                    val rid = rs.getInt("registration_id")
                    if (rs.wasNull()) return null
                    Pair(key, rid)
                }

                // Signed prekey
                val signedKey = conn.prepareStatement(
                    "SELECT key_id, public_key, signature FROM signed_prekeys WHERE user_id = ?::uuid LIMIT 1"
                ).use { stmt ->
                    stmt.setString(1, userId)
                    val rs = stmt.executeQuery()
                    if (!rs.next()) return null
                    SignedPreKey(rs.getInt("key_id"), rs.getBytes("public_key"), rs.getBytes("signature"))
                }

                // One-time prekey — atomic consume-and-erase. A consumed row
                // and its access timestamp must not form a communication
                // timeline in PostgreSQL.
                val otpk = conn.prepareStatement(
                    """WITH next_key AS (
                           SELECT id FROM one_time_prekeys
                           WHERE user_id = ?::uuid
                           ORDER BY id LIMIT 1
                           FOR UPDATE SKIP LOCKED
                       )
                       DELETE FROM one_time_prekeys
                       USING next_key
                       WHERE one_time_prekeys.id = next_key.id
                       RETURNING one_time_prekeys.key_id, one_time_prekeys.public_key"""
                ).use { stmt ->
                    stmt.setString(1, userId)
                    val rs = stmt.executeQuery()
                    if (rs.next()) {
                        OneTimePreKey(rs.getInt("key_id"), rs.getBytes("public_key"))
                    } else null
                }

                return PreKeyBundle(IdentityKey(idKey, regId), signedKey, otpk)
            }
        } catch (e: Exception) {
            log.error("[PreKey] Bundle fetch hatasi: {}", e.javaClass.simpleName)
            return null
        }
    }

    /** Kalan tuketilmemis one-time prekey sayisi — client'a gosterilir, az kalmissa yenisini upload eder. */
    fun unconsumedCount(userId: String): Int {
        return try {
            Database.getConnection().use { conn ->
                conn.prepareStatement(
                    "SELECT COUNT(*) FROM one_time_prekeys WHERE user_id = ?::uuid"
                ).use { stmt ->
                    stmt.setString(1, userId)
                    val rs = stmt.executeQuery()
                    if (rs.next()) rs.getInt(1) else 0
                }
            }
        } catch (_: Exception) { 0 }
    }
}
