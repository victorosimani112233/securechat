package com.securechat.botapi.signal

import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.delivery.BotQueuePrivacy
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

    private fun recipientIndex(userId: String): String =
        BotQueuePrivacy.blindIndex("signal-peer", userId)

    // =========================================================================
    // IdentityKeyStore
    // =========================================================================

    override fun getIdentityKeyPair(): IdentityKeyPair {
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """SELECT identity_public_key, identity_private_key_enc, identity_private_key_nonce
                   FROM bot_identity WHERE id = 1"""
            ).use { stmt ->
                stmt.executeQuery().use { rs ->
                    check(rs.next()) { "bot_identity (id=1) yok — bootstrap calistirilmamis" }
                    val publicKeyBytes = rs.getBytes("identity_public_key")  // 33 byte DJB-typed
                    val privateKeyBytes = KeyEncryptor.unwrap(
                        rs.getBytes("identity_private_key_enc"),
                        rs.getBytes("identity_private_key_nonce")
                    )
                    // IdentityKeyPair(serialized) protobuf bekliyor; biz raw bytes tuttuk.
                    // Public + private'i iki-arg constructor ile dogrudan birlesir.
                    val identityKey = org.whispersystems.libsignal.IdentityKey(
                        org.whispersystems.libsignal.ecc.Curve.decodePoint(publicKeyBytes, 0)
                    )
                    val privateKey = org.whispersystems.libsignal.ecc.Curve
                        .decodePrivatePoint(privateKeyBytes)
                    return IdentityKeyPair(identityKey, privateKey)
                }
            }
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
            conn.prepareStatement(
                """SELECT public_key, private_key_enc, private_key_nonce
                   FROM bot_one_time_prekey
                   WHERE key_id = ? AND consumed_at IS NULL"""
            ).use { stmt ->
                stmt.setInt(1, preKeyId)
                stmt.executeQuery().use { rs ->
                    if (!rs.next()) throw InvalidKeyIdException("PreKey bulunamadi: $preKeyId")
                    val pub = rs.getBytes("public_key")
                    val priv = KeyEncryptor.unwrap(rs.getBytes("private_key_enc"), rs.getBytes("private_key_nonce"))
                    return buildPreKeyRecord(preKeyId, pub, priv)
                }
            }
        }
    }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) {
        val pub = record.keyPair.publicKey.serialize()
        val priv = record.keyPair.privateKey.serialize()
        val wrapped = KeyEncryptor.wrap(priv)
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
            conn.prepareStatement(
                """SELECT public_key, private_key_enc, private_key_nonce, signature
                   FROM bot_signed_prekey WHERE key_id = ?"""
            ).use { stmt ->
                stmt.setInt(1, signedPreKeyId)
                stmt.executeQuery().use { rs ->
                    if (!rs.next()) throw InvalidKeyIdException("SignedPreKey bulunamadi: $signedPreKeyId")
                    val pub = rs.getBytes("public_key")
                    val priv = KeyEncryptor.unwrap(rs.getBytes("private_key_enc"), rs.getBytes("private_key_nonce"))
                    val sig = rs.getBytes("signature")
                    return buildSignedPreKeyRecord(signedPreKeyId, pub, priv, sig)
                }
            }
        }
    }

    override fun loadSignedPreKeys(): List<SignedPreKeyRecord> {
        val out = mutableListOf<SignedPreKeyRecord>()
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT key_id, public_key, private_key_enc, private_key_nonce, signature FROM bot_signed_prekey"
            ).use { stmt ->
                stmt.executeQuery().use { rs ->
                    while (rs.next()) {
                        val id = rs.getInt("key_id")
                        val pub = rs.getBytes("public_key")
                        val priv = KeyEncryptor.unwrap(rs.getBytes("private_key_enc"), rs.getBytes("private_key_nonce"))
                        val sig = rs.getBytes("signature")
                        out += buildSignedPreKeyRecord(id, pub, priv, sig)
                    }
                }
            }
        }
        return out
    }

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) {
        val pub = record.keyPair.publicKey.serialize()
        val priv = record.keyPair.privateKey.serialize()
        val wrapped = KeyEncryptor.wrap(priv)
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
                        SessionRecord(
                            BotSessionRecordCipher.open(
                                recipientIndex,
                                address.deviceId,
                                rs.getBytes(1)
                            )
                        )
                    } else {
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

    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord) {
        val recipientIndex = recipientIndex(address.name)
        val data = BotSessionRecordCipher.seal(
            recipientIndex,
            address.deviceId,
            record.serialize()
        )
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """INSERT INTO bot_signal_session(recipient_index, device_id, session_record)
                   VALUES (?, ?, ?)
                   ON CONFLICT (recipient_index, device_id)
                   DO UPDATE SET session_record = EXCLUDED.session_record"""
            ).use { stmt ->
                stmt.setString(1, recipientIndex)
                stmt.setInt(2, address.deviceId)
                stmt.setBytes(3, data)
                stmt.executeUpdate()
            }
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
