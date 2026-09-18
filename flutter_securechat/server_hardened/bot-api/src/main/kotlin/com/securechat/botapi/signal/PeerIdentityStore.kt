package com.securechat.botapi.signal

import com.securechat.botapi.db.BotDatabase
import com.securechat.botapi.delivery.BotQueuePrivacy
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("PeerIdentityStore")

/**
 * Alici identity key'lerinin trust-on-first-use pinlemesi.
 *
 * Bot, prekey bundle'ini signaling'den alir. Bundle'in icindeki identity key
 * dogrulanmadan kabul edilirse, signaling/DB/ic ag ele gecirildiginde
 * saldirganin anahtari sessizce kullanilir ve mesaj saldirgana sifrelenir.
 * Bu yuzden ilk gorulen anahtar pinlenir; sonraki farkli bir anahtar
 * fail-closed reddedilir ve ancak acik bir operator onayindan sonra
 * yeniden pinlenebilir.
 *
 * Satirda ham UUID veya zaman yoktur: purpose-separated blind index ve
 * BOT_MASTER_KEY altinda AEAD ile muhurlenmis *public* identity key tutulur.
 */
object PeerIdentityStore {

    private val magic = byteArrayOf(0x42, 0x50, 0x49, 0x31) // BPI1
    private const val NONCE_LENGTH = 12

    fun recipientIndex(userId: String): String =
        BotQueuePrivacy.blindIndex("signal-peer", userId)

    /** @return pinlenmis public identity key veya henuz pin yoksa null. */
    fun pinned(recipientIndex: String, deviceId: Int): ByteArray? =
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT identity_key_sealed FROM bot_peer_identity
                   WHERE recipient_index = ? AND device_id = ?""",
            ).use { statement ->
                statement.setString(1, recipientIndex)
                statement.setInt(2, deviceId)
                statement.executeQuery().use { rows ->
                    if (!rows.next()) null else open(recipientIndex, deviceId, rows.getBytes(1))
                }
            }
        }

    /**
     * Ilk kez gorulen anahtari pinler.
     *
     * @return pin bu cagride olustuysa true; satir zaten varsa false. Var olan
     *   bir pin bu yoldan **degistirilemez**; rotasyon acik onay ister.
     */
    fun pinIfAbsent(recipientIndex: String, deviceId: Int, identityKey: ByteArray): Boolean =
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                """INSERT INTO bot_peer_identity(recipient_index, device_id, identity_key_sealed)
                   VALUES (?, ?, ?)
                   ON CONFLICT (recipient_index, device_id) DO NOTHING""",
            ).use { statement ->
                statement.setString(1, recipientIndex)
                statement.setInt(2, deviceId)
                statement.setBytes(3, seal(recipientIndex, deviceId, identityKey))
                statement.executeUpdate() == 1
            }
        }

    /**
     * Operator onayi: mevcut pini dusurur, boylece bir sonraki gonderim yeni
     * anahtari trust-on-first-use ile yeniden pinler. Otomatik cagrilmaz.
     */
    fun approveRotation(recipientIndex: String, deviceId: Int): Boolean =
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                """DELETE FROM bot_peer_identity
                   WHERE recipient_index = ? AND device_id = ?""",
            ).use { statement ->
                statement.setString(1, recipientIndex)
                statement.setInt(2, deviceId)
                statement.executeUpdate() > 0
            }.also {
                if (it) log.warn("[Identity] Pin operator onayiyla dusuruldu")
            }
        }

    /** Operator gorunumu: opaque index + public key parmak izi. */
    fun listPins(): List<Pin> =
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                """SELECT recipient_index, device_id, identity_key_sealed
                   FROM bot_peer_identity ORDER BY recipient_index, device_id""",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    buildList {
                        while (rows.next()) {
                            val index = rows.getString("recipient_index")
                            val deviceId = rows.getInt("device_id")
                            val key = runCatching {
                                open(index, deviceId, rows.getBytes("identity_key_sealed"))
                            }.getOrNull()
                            add(
                                Pin(
                                    recipientIndex = index,
                                    deviceId = deviceId,
                                    fingerprint = key?.let(::fingerprint) ?: "unreadable",
                                ),
                            )
                        }
                    }
                }
            }
        }

    class Pin(val recipientIndex: String, val deviceId: Int, val fingerprint: String)

    fun fingerprint(identityKey: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(identityKey)
            .joinToString("") { "%02x".format(it) }

    private fun seal(recipientIndex: String, deviceId: Int, plaintext: ByteArray): ByteArray {
        val wrapped = KeyEncryptor.wrap(plaintext, aad(recipientIndex, deviceId))
        return ByteBuffer.allocate(magic.size + NONCE_LENGTH + wrapped.ciphertext.size)
            .put(magic)
            .put(wrapped.nonce)
            .put(wrapped.ciphertext)
            .array()
    }

    private fun open(recipientIndex: String, deviceId: Int, envelope: ByteArray): ByteArray {
        require(
            envelope.size >= magic.size + NONCE_LENGTH + 16 &&
                envelope.copyOfRange(0, magic.size).contentEquals(magic),
        ) { "Bot peer identity envelope is malformed" }
        val nonceStart = magic.size
        val ciphertextStart = nonceStart + NONCE_LENGTH
        return KeyEncryptor.unwrap(
            envelope.copyOfRange(ciphertextStart, envelope.size),
            envelope.copyOfRange(nonceStart, ciphertextStart),
            aad(recipientIndex, deviceId),
        )
    }

    private fun aad(recipientIndex: String, deviceId: Int): ByteArray =
        "securechat-bot-peer-identity-v1\u0000$recipientIndex\u0000$deviceId"
            .toByteArray(StandardCharsets.UTF_8)
}
