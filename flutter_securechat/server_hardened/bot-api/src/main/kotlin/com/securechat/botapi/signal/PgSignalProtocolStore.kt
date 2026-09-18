package com.securechat.botapi.signal

import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.delivery.BotQueuePrivacy
import java.sql.Connection
import org.slf4j.LoggerFactory
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.InvalidKeyIdException
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.state.IdentityKeyStore
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.PreKeyStore
import org.whispersystems.libsignal.state.SessionRecord
import org.whispersystems.libsignal.state.SessionStore
import org.whispersystems.libsignal.state.SignalProtocolStore
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyStore

private val log = LoggerFactory.getLogger("PgSignalProtocolStore")

/**
 * libsignal'in 4 store interface'ini (Identity + PreKey + SignedPreKey + Session)
 * Postgres'e baglayan implementasyon.
 *
 * Bot tek bir kullanici oldugundan IdentityKey ve registrationId singleton'dir
 * (bot_identity tablosu, id=1). PreKey/SignedPreKey/Session tablolari recipient
 * basina kayit tutar.
 *
 * Tum private key ve ratchet session kayitlari AES-256-GCM ile BOT_MASTER_KEY
 * altinda sifrelenir. Recipient UUID yerine keyed opaque index tutulur.
 * RAM'de plaintext sadece islem suresi boyunca yasar.
 *
 * Bot once register oldugunda BotIdentityBootstrap bu store'u doldurur.
 */
class PgSignalProtocolStore : SignalProtocolStore {

    private data class PrivateKeyRow(
        val publicKey: ByteArray,
        val ciphertext: ByteArray,
        val nonce: ByteArray,
        val signature: ByteArray? = null,
    )

    private fun recipientIndex(userId: String): String =
        BotQueuePrivacy.blindIndex("signal-peer", userId)

    // =========================================================================
    // IdentityKeyStore
    // =========================================================================

    override fun getIdentityKeyPair(): IdentityKeyPair {
        BotDatabase.getConnection().use { conn ->
            val row = conn.prepareStatement(
                """SELECT identity_public_key, identity_private_key_enc, identity_private_key_nonce
                   FROM bot_identity WHERE id = 1"""
            ).use { stmt ->
                stmt.executeQuery().use { rs ->
                    check(rs.next()) { "bot_identity (id=1) yok — bootstrap calistirilmamis" }
                    PrivateKeyRow(
                        publicKey = rs.getBytes("identity_public_key"),
                        ciphertext = rs.getBytes("identity_private_key_enc"),
                        nonce = rs.getBytes("identity_private_key_nonce"),
                    )
                }
            }
            val privateKeyBytes = openPrivateKey(
                row = row,
                purpose = KeyEncryptor.PURPOSE_IDENTITY_PRIVATE,
                binding = "1",
                migrate = { wrapped -> migrateIdentity(conn, row, wrapped) },
            )
            // IdentityKeyPair(serialized) protobuf bekliyor; biz raw bytes tuttuk.
            // Public + private'i iki-arg constructor ile dogrudan birlesir.
            val identityKey = org.whispersystems.libsignal.IdentityKey(
                org.whispersystems.libsignal.ecc.Curve.decodePoint(row.publicKey, 0)
            )
            val privateKey = org.whispersystems.libsignal.ecc.Curve
                .decodePrivatePoint(privateKeyBytes)
            return IdentityKeyPair(identityKey, privateKey)
        }
    }

    override fun getLocalRegistrationId(): Int {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement("SELECT registration_id FROM bot_identity WHERE id = 1").use { stmt ->
                stmt.executeQuery().use { rs ->
                    check(rs.next()) { "bot_identity yok" }
                    return rs.getInt(1)
                }
            }
        }
    }

    /**
     * Trust-on-first-use pin. Ilk gorulen anahtar kalici olarak pinlenir;
     * var olan bir pin bu yoldan degistirilemez.
     *
     * @return var olan bir pin uzerine yazildiysa true — bu implementasyonda
     *   asla olmaz, cunku rotasyon acik operator onayi ister.
     */
    override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey): Boolean {
        val index = PeerIdentityStore.recipientIndex(address.name)
        val created = PeerIdentityStore.pinIfAbsent(
            index,
            address.deviceId,
            identityKey.serialize(),
        )
        if (created) log.info("[Store] Alici identity ilk kez pinlendi")
        return false
    }

    /**
     * Pin ile eslesmeyen bir identity fail-closed reddedilir.
     *
     * Prekey bundle signaling'den gelir; dogrulanmadan kabul edilseydi
     * signaling/DB/ic ag ihlali sessizce saldirganin anahtarina sifreleme
     * anlamina gelirdi. Yeni bir aliciya ilk gonderimde pin yoktur ve
     * anahtar trust-on-first-use ile kabul edilip pinlenir.
     */
    override fun isTrustedIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
        direction: IdentityKeyStore.Direction
    ): Boolean {
        val index = PeerIdentityStore.recipientIndex(address.name)
        val pinned = try {
            PeerIdentityStore.pinned(index, address.deviceId)
        } catch (e: Exception) {
            // Pin okunamiyorsa guvenilirlik iddia edilemez.
            log.error("[Store] Identity pin okunamadi (fail-closed)")
            return false
        } ?: return true
        val matches = pinned.contentEquals(identityKey.serialize())
        if (!matches) {
            log.error(
                "[Store] Alici identity pin ile eslesmiyor — gonderim reddedildi. " +
                    "Rotasyon operator onayi gerektirir"
            )
        }
        return matches
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? {
        val index = PeerIdentityStore.recipientIndex(address.name)
        val pinned = try {
            PeerIdentityStore.pinned(index, address.deviceId)
        } catch (_: Exception) {
            null
        } ?: return null
        return runCatching { IdentityKey(pinned, 0) }.getOrNull()
    }

    // =========================================================================
    // PreKeyStore (bot'un kendi prekey havuzu — bot register olurken yuklendi)
    // =========================================================================

    override fun loadPreKey(preKeyId: Int): PreKeyRecord {
        BotDatabase.getConnection().use { conn ->
            val row = conn.prepareStatement(
                """SELECT public_key, private_key_enc, private_key_nonce
                   FROM bot_one_time_prekey
                   WHERE key_id = ? AND consumed_at IS NULL"""
            ).use { stmt ->
                stmt.setInt(1, preKeyId)
                stmt.executeQuery().use { rs ->
                    if (!rs.next()) throw InvalidKeyIdException("PreKey bulunamadi: $preKeyId")
                    PrivateKeyRow(
                        publicKey = rs.getBytes("public_key"),
                        ciphertext = rs.getBytes("private_key_enc"),
                        nonce = rs.getBytes("private_key_nonce"),
                    )
                }
            }
            val privateKey = openPrivateKey(
                row = row,
                purpose = KeyEncryptor.PURPOSE_ONE_TIME_PREKEY_PRIVATE,
                binding = preKeyId.toString(),
                migrate = { wrapped -> migrateOneTimePreKey(conn, preKeyId, row, wrapped) },
            )
            return buildPreKeyRecord(preKeyId, row.publicKey, privateKey)
        }
    }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) {
        val pub = record.keyPair.publicKey.serialize()
        val priv = record.keyPair.privateKey.serialize()
        val wrapped = KeyEncryptor.wrapBound(
            priv,
            KeyEncryptor.PURPOSE_ONE_TIME_PREKEY_PRIVATE,
            preKeyId.toString(),
        )
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """INSERT INTO bot_one_time_prekey(key_id, public_key, private_key_enc, private_key_nonce)
                   VALUES (?, ?, ?, ?)
                   ON CONFLICT (key_id) DO UPDATE
                   SET public_key = EXCLUDED.public_key,
                       private_key_enc = EXCLUDED.private_key_enc,
                       private_key_nonce = EXCLUDED.private_key_nonce,
                       consumed_at = NULL"""
            ).use { stmt ->
                stmt.setInt(1, preKeyId)
                stmt.setBytes(2, pub)
                stmt.setBytes(3, wrapped.ciphertext)
                stmt.setBytes(4, wrapped.nonce)
                stmt.executeUpdate()
            }
        }
    }

    override fun containsPreKey(preKeyId: Int): Boolean {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT 1 FROM bot_one_time_prekey WHERE key_id = ? AND consumed_at IS NULL"
            ).use { stmt ->
                stmt.setInt(1, preKeyId)
                stmt.executeQuery().use { rs -> return rs.next() }
            }
        }
    }

    override fun removePreKey(preKeyId: Int) {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "UPDATE bot_one_time_prekey SET consumed_at = NOW() WHERE key_id = ?"
            ).use { stmt ->
                stmt.setInt(1, preKeyId)
                stmt.executeUpdate()
            }
        }
    }

    private fun buildPreKeyRecord(keyId: Int, pub: ByteArray, priv: ByteArray): PreKeyRecord {
        // libsignal PreKeyRecord serialize format'i — kolayligi icin direkt
        // KeyHelper.generatePreKeys ile uretilen formati taklit eder.
        // Kayitli pub/priv'i tekrar ECPublicKey/ECPrivateKey'e cevirip record olustur:
        val publicKey = org.whispersystems.libsignal.ecc.Curve.decodePoint(pub, 0)
        val privateKey = org.whispersystems.libsignal.ecc.Curve.decodePrivatePoint(priv)
        val keyPair = org.whispersystems.libsignal.ecc.ECKeyPair(publicKey, privateKey)
        return PreKeyRecord(keyId, keyPair)
    }

    // =========================================================================
    // SignedPreKeyStore
    // =========================================================================

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord {
        BotDatabase.getConnection().use { conn ->
            val row = conn.prepareStatement(
                """SELECT public_key, private_key_enc, private_key_nonce, signature
                   FROM bot_signed_prekey WHERE key_id = ?"""
            ).use { stmt ->
                stmt.setInt(1, signedPreKeyId)
                stmt.executeQuery().use { rs ->
                    if (!rs.next()) throw InvalidKeyIdException("SignedPreKey bulunamadi: $signedPreKeyId")
                    PrivateKeyRow(
                        publicKey = rs.getBytes("public_key"),
                        ciphertext = rs.getBytes("private_key_enc"),
                        nonce = rs.getBytes("private_key_nonce"),
                        signature = rs.getBytes("signature"),
                    )
                }
            }
            val privateKey = openPrivateKey(
                row = row,
                purpose = KeyEncryptor.PURPOSE_SIGNED_PREKEY_PRIVATE,
                binding = signedPreKeyId.toString(),
                migrate = { wrapped -> migrateSignedPreKey(conn, signedPreKeyId, row, wrapped) },
            )
            return buildSignedPreKeyRecord(
                signedPreKeyId,
                row.publicKey,
                privateKey,
                checkNotNull(row.signature),
            )
        }
    }

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> {
        val rows = mutableListOf<Pair<Int, PrivateKeyRow>>()
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT key_id, public_key, private_key_enc, private_key_nonce, signature FROM bot_signed_prekey"
            ).use { stmt ->
                stmt.executeQuery().use { rs ->
                    while (rs.next()) {
                        val id = rs.getInt("key_id")
                        rows += id to PrivateKeyRow(
                            publicKey = rs.getBytes("public_key"),
                            ciphertext = rs.getBytes("private_key_enc"),
                            nonce = rs.getBytes("private_key_nonce"),
                            signature = rs.getBytes("signature"),
                        )
                    }
                }
            }
            return rows.map { (id, row) ->
                val privateKey = openPrivateKey(
                    row = row,
                    purpose = KeyEncryptor.PURPOSE_SIGNED_PREKEY_PRIVATE,
                    binding = id.toString(),
                    migrate = { wrapped -> migrateSignedPreKey(conn, id, row, wrapped) },
                )
                buildSignedPreKeyRecord(id, row.publicKey, privateKey, checkNotNull(row.signature))
            }
        }
    }

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) {
        val pub = record.keyPair.publicKey.serialize()
        val priv = record.keyPair.privateKey.serialize()
        val wrapped = KeyEncryptor.wrapBound(
            priv,
            KeyEncryptor.PURPOSE_SIGNED_PREKEY_PRIVATE,
            signedPreKeyId.toString(),
        )
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """INSERT INTO bot_signed_prekey(key_id, public_key, private_key_enc, private_key_nonce, signature)
                   VALUES (?, ?, ?, ?, ?)
                   ON CONFLICT (key_id) DO UPDATE
                   SET public_key = EXCLUDED.public_key,
                       private_key_enc = EXCLUDED.private_key_enc,
                       private_key_nonce = EXCLUDED.private_key_nonce,
                       signature = EXCLUDED.signature"""
            ).use { stmt ->
                stmt.setInt(1, signedPreKeyId)
                stmt.setBytes(2, pub)
                stmt.setBytes(3, wrapped.ciphertext)
                stmt.setBytes(4, wrapped.nonce)
                stmt.setBytes(5, record.signature)
                stmt.executeUpdate()
            }
        }
    }

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement("SELECT 1 FROM bot_signed_prekey WHERE key_id = ?").use { stmt ->
                stmt.setInt(1, signedPreKeyId)
                stmt.executeQuery().use { rs -> return rs.next() }
            }
        }
    }

    override fun removeSignedPreKey(signedPreKeyId: Int) {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement("DELETE FROM bot_signed_prekey WHERE key_id = ?").use { stmt ->
                stmt.setInt(1, signedPreKeyId)
                stmt.executeUpdate()
            }
        }
    }

    private fun buildSignedPreKeyRecord(
        keyId: Int, pub: ByteArray, priv: ByteArray, sig: ByteArray
    ): SignedPreKeyRecord {
        val publicKey = org.whispersystems.libsignal.ecc.Curve.decodePoint(pub, 0)
        val privateKey = org.whispersystems.libsignal.ecc.Curve.decodePrivatePoint(priv)
        val keyPair = org.whispersystems.libsignal.ecc.ECKeyPair(publicKey, privateKey)
        // Timestamp 0 — sadece persistance icin kullaniyoruz, rotation ayri yonetilir
        return SignedPreKeyRecord(keyId, 0L, keyPair, sig)
    }

    private fun openPrivateKey(
        row: PrivateKeyRow,
        purpose: String,
        binding: String,
        migrate: (KeyEncryptor.WrappedKey) -> Unit,
    ): ByteArray {
        val opened = KeyEncryptor.unwrapBound(
            row.ciphertext,
            row.nonce,
            purpose,
            binding,
        )
        if (opened.needsMigration) {
            migrate(KeyEncryptor.wrapBound(opened.plaintext, purpose, binding))
            log.info("[Store] Legacy private key envelope AAD-bound formata gecirildi")
        }
        return opened.plaintext
    }

    private fun migrateIdentity(
        conn: Connection,
        old: PrivateKeyRow,
        replacement: KeyEncryptor.WrappedKey,
    ) {
        conn.prepareStatement(
            """UPDATE bot_identity
               SET identity_private_key_enc = ?, identity_private_key_nonce = ?
               WHERE id = 1
                 AND identity_private_key_enc = ?
                 AND identity_private_key_nonce = ?""",
        ).use { statement ->
            statement.setBytes(1, replacement.ciphertext)
            statement.setBytes(2, replacement.nonce)
            statement.setBytes(3, old.ciphertext)
            statement.setBytes(4, old.nonce)
            statement.executeUpdate()
        }
    }

    private fun migrateOneTimePreKey(
        conn: Connection,
        keyId: Int,
        old: PrivateKeyRow,
        replacement: KeyEncryptor.WrappedKey,
    ) {
        conn.prepareStatement(
            """UPDATE bot_one_time_prekey
               SET private_key_enc = ?, private_key_nonce = ?
               WHERE key_id = ? AND consumed_at IS NULL
                 AND private_key_enc = ? AND private_key_nonce = ?""",
        ).use { statement ->
            statement.setBytes(1, replacement.ciphertext)
            statement.setBytes(2, replacement.nonce)
            statement.setInt(3, keyId)
            statement.setBytes(4, old.ciphertext)
            statement.setBytes(5, old.nonce)
            statement.executeUpdate()
        }
    }

    private fun migrateSignedPreKey(
        conn: Connection,
        keyId: Int,
        old: PrivateKeyRow,
        replacement: KeyEncryptor.WrappedKey,
    ) {
        conn.prepareStatement(
            """UPDATE bot_signed_prekey
               SET private_key_enc = ?, private_key_nonce = ?
               WHERE key_id = ? AND private_key_enc = ? AND private_key_nonce = ?""",
        ).use { statement ->
            statement.setBytes(1, replacement.ciphertext)
            statement.setBytes(2, replacement.nonce)
            statement.setInt(3, keyId)
            statement.setBytes(4, old.ciphertext)
            statement.setBytes(5, old.nonce)
            statement.executeUpdate()
        }
    }

    // =========================================================================
    // SessionStore — recipient basina (recipientUserId, deviceId) PK
    // =========================================================================

    override fun loadSession(address: SignalProtocolAddress): SessionRecord {
        val recipientIndex = recipientIndex(address.name)
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """SELECT session_record FROM bot_signal_session
                   WHERE recipient_index = ? AND device_id = ?"""
            ).use { stmt ->
                stmt.setString(1, recipientIndex)
                stmt.setInt(2, address.deviceId)
                stmt.executeQuery().use { rs ->
                    return if (rs.next()) {
                        val sealed = rs.getBytes(1)
                        // Yazma sirasinda compare-and-set icin saklanir.
                        lastLoaded.get()[sessionSlot(address)] = sealed
                        SessionRecord(
                            BotSessionRecordCipher.open(
                                recipientIndex,
                                address.deviceId,
                                sealed
                            )
                        )
                    } else {
                        // Kayit yok: yazma INSERT yolunu kullanmali.
                        clearLoadedSession(sessionSlot(address))
                        SessionRecord()
                    }
                }
            }
        }
    }

    override fun getSubDeviceSessions(name: String): List<Int> {
        val ids = mutableListOf<Int>()
        val recipientIndex = recipientIndex(name)
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """SELECT device_id FROM bot_signal_session
                   WHERE recipient_index = ? AND device_id <> 1"""
            ).use { stmt ->
                stmt.setString(1, recipientIndex)
                stmt.executeQuery().use { rs ->
                    while (rs.next()) ids += rs.getInt(1)
                }
            }
        }
        return ids
    }

    /**
     * Bu is parcaciginin en son okudugu ratchet kaydi.
     *
     * `storeSession` kayittan once okunan degeri bilmezse ustune korkusuzca
     * yazar; iki es zamanli gonderim ayni kaydi yukleyip ilerletince biri
     * kaybolur ve alici o mesaji hicbir zaman cozemez. Karsilastirma degeri
     * burada tutulur.
     */
    private val lastLoaded = ThreadLocal.withInitial { mutableMapOf<String, ByteArray?>() }

    private fun sessionSlot(address: SignalProtocolAddress) =
        "${recipientIndex(address.name)}:${address.deviceId}"

    private fun clearLoadedSession(slot: String) {
        val loaded = lastLoaded.get()
        loaded.remove(slot)
        if (loaded.isEmpty()) lastLoaded.remove()
    }

    class ConcurrentSessionModificationException :
        IllegalStateException("Signal session was modified concurrently")

    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord) {
        val recipientIndex = recipientIndex(address.name)
        val data = BotSessionRecordCipher.seal(
            recipientIndex,
            address.deviceId,
            record.serialize()
        )
        val slot = sessionSlot(address)
        val expected = lastLoaded.get()[slot]
        try {
            BotDatabase.getConnection().use { conn ->
                val updated = if (expected == null) {
                    // Yeni oturum: yalniz kayit yoksa yazilir.
                    conn.prepareStatement(
                        """INSERT INTO bot_signal_session(recipient_index, device_id, session_record)
                           VALUES (?, ?, ?)
                           ON CONFLICT (recipient_index, device_id) DO NOTHING"""
                    ).use { stmt ->
                        stmt.setString(1, recipientIndex)
                        stmt.setInt(2, address.deviceId)
                        stmt.setBytes(3, data)
                        stmt.executeUpdate()
                    }
                } else {
                    // Compare-and-set: kayit okundugundan beri degistiyse yazma.
                    conn.prepareStatement(
                        """UPDATE bot_signal_session SET session_record = ?
                           WHERE recipient_index = ? AND device_id = ? AND session_record = ?"""
                    ).use { stmt ->
                        stmt.setBytes(1, data)
                        stmt.setString(2, recipientIndex)
                        stmt.setInt(3, address.deviceId)
                        stmt.setBytes(4, expected)
                        stmt.executeUpdate()
                    }
                }
                if (updated != 1) {
                    // Sessizce ustune yazmak ratchet adimini kaybettirirdi.
                    log.error("[Store] Ratchet kaydi es zamanli degistirildi — yazma reddedildi")
                    throw ConcurrentSessionModificationException()
                }
            }
        } finally {
            // Her store yeni bir load baseline'i gerektirir; ThreadLocal map
            // recipient blind-index'lerini process omru boyunca biriktirmez.
            clearLoadedSession(slot)
        }
    }

    override fun containsSession(address: SignalProtocolAddress): Boolean {
        val recipientIndex = recipientIndex(address.name)
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT 1 FROM bot_signal_session WHERE recipient_index = ? AND device_id = ?"
            ).use { stmt ->
                stmt.setString(1, recipientIndex)
                stmt.setInt(2, address.deviceId)
                stmt.executeQuery().use { rs -> return rs.next() }
            }
        }
    }

    override fun deleteSession(address: SignalProtocolAddress) {
        clearLoadedSession(sessionSlot(address))
        val recipientIndex = recipientIndex(address.name)
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "DELETE FROM bot_signal_session WHERE recipient_index = ? AND device_id = ?"
            ).use { stmt ->
                stmt.setString(1, recipientIndex)
                stmt.setInt(2, address.deviceId)
                stmt.executeUpdate()
            }
        }
    }

    override fun deleteAllSessions(name: String) {
        val recipientIndex = recipientIndex(name)
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "DELETE FROM bot_signal_session WHERE recipient_index = ?"
            ).use { stmt ->
                stmt.setString(1, recipientIndex)
                stmt.executeUpdate()
            }
        }
    }
}
