package com.securechat.botapi.signal

import com.securechat.botapi.db.BotDatabase
import org.slf4j.LoggerFactory
import org.whispersystems.libsignal.IdentityKeyPair
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.util.KeyHelper
import java.security.MessageDigest
import java.sql.Connection
import java.util.Base64
import java.util.UUID

private val log = LoggerFactory.getLogger("BotIdentityBootstrap")

/**
 * Bot'un Signal kimligini ve public bundle'ini hazir hale getirir.
 *
 * Bootstrap tek atislik bir "first run" degil, her acilista calisan bir
 * reconcile adimidir. Uc bagimsiz durum ayri ayri dogrulanir:
 *
 *  1. Hesap  — `users` + `bot_identity` satirlari (tek transaction).
 *  2. Local  — `bot_signed_prekey` + `bot_one_time_prekey` havuzu.
 *  3. Yayin  — signaling tarafindaki identity/signed prekey/one-time havuzu.
 *
 * Herhangi bir adimda kesinti olursa bir sonraki acilis yalniz eksik olani
 * tamamlar. `BotIdentity` ancak ucu de dogrulandiktan sonra hazir isaretlenir;
 * yayinlanmamis bir bot asla "kayitli" sayilmaz.
 *
 * Servis hesabi `users.directory_token` alaninda ayrilmis `service:` namespace'i
 * kullanir ve `directory_key_id` NULL kalir. Private-directory snapshot yalniz
 * aktif key id tasiyan satirlari yayinladigi icin bot rehberde gorunmez;
 * OPRF tokenlari url-safe base64 oldugundan bu namespace ile cakisamaz.
 */
object BotIdentityBootstrap {

    private const val ONE_TIME_PREKEY_POOL = 100
    private const val SIGNED_PREKEY_ID = 1
    private const val SERVICE_TOKEN_PREFIX = "service:"

    private val fingerprintEncoder: Base64.Encoder = Base64.getUrlEncoder().withoutPadding()

    fun ensureRegistered(publisher: BotBundlePublisher = HttpBundlePublisher) {
        val account = ensureAccount()
        val store = PgSignalProtocolStore()
        val signedPreKey = ensureSignedPreKey(store, account.identityKeyPair)
        reconcilePublishedBundle(account, store, signedPreKey, publisher)
        BotIdentity.set(account.botUserId, account.registrationId)
        log.info("[Bootstrap] Bot identity hazir ve yayinlanmis durumda")
    }

    // =====================================================================
    // 1) Hesap
    // =====================================================================

    private class BotAccount(
        val botUserId: String,
        val registrationId: Int,
        val identityKeyPair: IdentityKeyPair,
    )

    private fun ensureAccount(): BotAccount {
        loadAccount()?.let {
            log.info("[Bootstrap] Mevcut bot identity yuklendi")
            return it
        }
        log.info("[Bootstrap] Bot identity yok — yeni servis hesabi olusturuluyor")
        return createAccount()
    }

    private fun loadAccount(): BotAccount? {
        // Baglanti icinde ikinci bir baglanti alinmaz; havuz tukenmesi
        // startup'i kilitleyebilir.
        val identity = BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT bot_user_id, registration_id FROM bot_identity WHERE id = 1",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    if (!rows.next()) {
                        null
                    } else {
                        rows.getObject("bot_user_id", UUID::class.java).toString() to
                            rows.getInt("registration_id")
                    }
                }
            }
        } ?: return null
        return BotAccount(
            botUserId = identity.first,
            registrationId = identity.second,
            identityKeyPair = PgSignalProtocolStore().identityKeyPair,
        )
    }

    /**
     * Hesap satiri ve identity kaydi tek transaction'da yazilir. Yarim bir
     * hesap (users var, bot_identity yok) olusamaz.
     */
    private fun createAccount(): BotAccount {
        val identityKeyPair = KeyHelper.generateIdentityKeyPair()
        val registrationId = KeyHelper.generateRegistrationId(false)
        val botUserId = UUID.randomUUID()
        val directoryToken = serviceDirectoryToken(identityKeyPair)

        BotDatabase.getConnection().use { conn ->
            inTransaction(conn) {
                // Public Signal materyali bilerek bos birakilir: `users`
                // uzerindeki identity/registration alanlarini yalniz
                // authenticated yayin yolu doldurur. Boylece "yayinlandi mi"
                // sorusunun cevabi botun kendi yazdigi satirdan uydurulamaz.
                conn.prepareStatement(
                    """INSERT INTO users(user_id, directory_token, directory_key_id)
                       VALUES (?, ?, NULL)""",
                ).use { statement ->
                    statement.setObject(1, botUserId)
                    statement.setString(2, directoryToken)
                    statement.executeUpdate()
                }

                val wrapped = KeyEncryptor.wrap(identityKeyPair.privateKey.serialize())
                conn.prepareStatement(
                    """INSERT INTO bot_identity(id, bot_user_id, registration_id,
                           identity_public_key, identity_private_key_enc,
                           identity_private_key_nonce)
                       VALUES (1, ?, ?, ?, ?, ?)""",
                ).use { statement ->
                    statement.setObject(1, botUserId)
                    statement.setInt(2, registrationId)
                    statement.setBytes(3, identityKeyPair.publicKey.serialize())
                    statement.setBytes(4, wrapped.ciphertext)
                    statement.setBytes(5, wrapped.nonce)
                    statement.executeUpdate()
                }
            }
        }
        return BotAccount(botUserId.toString(), registrationId, identityKeyPair)
    }

    /**
     * Servis hesabinin rehber namespace'i disindaki sabit adresi. Identity
     * public key'inin SHA-256 ozetinden turer; telefon girdisi icermez.
     */
    private fun serviceDirectoryToken(identityKeyPair: IdentityKeyPair): String {
        val fingerprint = MessageDigest.getInstance("SHA-256")
            .digest(identityKeyPair.publicKey.serialize())
        return SERVICE_TOKEN_PREFIX + fingerprintEncoder.encodeToString(fingerprint).take(32)
    }

    // =====================================================================
    // 2) Local prekey durumu
    // =====================================================================

    private fun ensureSignedPreKey(
        store: PgSignalProtocolStore,
        identityKeyPair: IdentityKeyPair,
    ): SignedPreKeyRecord {
        if (store.containsSignedPreKey(SIGNED_PREKEY_ID)) {
            return store.loadSignedPreKey(SIGNED_PREKEY_ID)
        }
        val record = KeyHelper.generateSignedPreKey(identityKeyPair, SIGNED_PREKEY_ID)
        store.storeSignedPreKey(SIGNED_PREKEY_ID, record)
        log.info("[Bootstrap] Signed prekey uretildi")
        return record
    }

    /**
     * Havuzu hedef boyuta tamamlar ve **yalniz yeni uretilen** anahtarlari
     * dondurur. Key id'ler local ve yayinlanmis havuzlarin ustunden devam
     * eder; daha once kullanilmis bir id yeniden uretilmez.
     */
    private fun generateMissingOneTimePreKeys(
        store: PgSignalProtocolStore,
        deficit: Int,
    ): List<PublishedPreKey> {
        if (deficit <= 0) return emptyList()
        val startId = nextOneTimeKeyId()
        val records = KeyHelper.generatePreKeys(startId, deficit)
        for (record in records) {
            store.storePreKey(record.id, record)
        }
        log.info("[Bootstrap] {} yeni one-time prekey uretildi", records.size)
        return records.map { PublishedPreKey(it.id, it.keyPair.publicKey.serialize()) }
    }

    /**
     * Bir sonraki guvenli key id: hem local havuzun hem de yayinlanmis havuzun
     * en yukseginin ustu. Iki tablodan biri retention ile budansa bile
     * digerinden gelen tepe deger id'nin geri sarmasini engeller.
     */
    private fun nextOneTimeKeyId(): Int =
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """SELECT GREATEST(
                       (SELECT COALESCE(MAX(key_id), 0) FROM bot_one_time_prekey),
                       (SELECT COALESCE(MAX(key_id), 0) FROM one_time_prekeys)
                   ) + 1""",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    rows.next()
                    rows.getInt(1)
                }
            }
        }

    // =====================================================================
    // 3) Yayin durumu
    // =====================================================================

    private fun reconcilePublishedBundle(
        account: BotAccount,
        store: PgSignalProtocolStore,
        signedPreKey: SignedPreKeyRecord,
        publisher: BotBundlePublisher,
    ) {
        val identityPublished = isIdentityPublished(account)
        val signedPreKeyPublished = identityPublished && isSignedPreKeyPublished(account, signedPreKey)

        if (!identityPublished || !signedPreKeyPublished) {
            // Ilk yayin veya identity rotasyonu: signaling degisen identity'de
            // eski prekey'leri siler, bu yuzden local havuzun tamami gonderilir.
            val existing = unconsumedLocalOneTimePreKeys()
            val fresh = generateMissingOneTimePreKeys(
                store,
                ONE_TIME_PREKEY_POOL - existing.size,
            )
            publish(account, signedPreKey, existing + fresh, publisher)
            return
        }

        // Yayinlanmis havuzda olmayan bir local anahtar, bir peer tarafindan
        // atomik olarak cekilmis demektir. PreKeySignalMessage henuz gelmemis
        // olsa bile o anahtar tuketilmistir; ikinci kez yayinlanamaz.
        markPeerConsumedKeys(account)

        val publishedCount = publishedOneTimePreKeyCount(account)
        val fresh = generateMissingOneTimePreKeys(store, ONE_TIME_PREKEY_POOL - publishedCount)
        if (fresh.isEmpty()) return
        publish(account, signedPreKey, fresh, publisher)
    }

    private fun publish(
        account: BotAccount,
        signedPreKey: SignedPreKeyRecord,
        oneTimePreKeys: List<PublishedPreKey>,
        publisher: BotBundlePublisher,
    ) {
        publisher.publish(
            PublishedBundle(
                botUserId = account.botUserId,
                identityPublicKey = account.identityKeyPair.publicKey.serialize(),
                registrationId = account.registrationId,
                signedPreKeyId = signedPreKey.id,
                signedPreKey = signedPreKey.keyPair.publicKey.serialize(),
                signedPreKeySignature = signedPreKey.signature,
                oneTimePreKeys = oneTimePreKeys,
            ),
        )
    }

    private fun isIdentityPublished(account: BotAccount): Boolean =
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT identity_public_key, registration_id FROM users WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, account.botUserId)
                statement.executeQuery().use { rows ->
                    if (!rows.next()) return false
                    val published = rows.getBytes("identity_public_key") ?: return false
                    val registrationId = rows.getInt("registration_id")
                    published.contentEquals(account.identityKeyPair.publicKey.serialize()) &&
                        registrationId == account.registrationId
                }
            }
        }

    private fun isSignedPreKeyPublished(
        account: BotAccount,
        signedPreKey: SignedPreKeyRecord,
    ): Boolean =
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT public_key FROM signed_prekeys WHERE user_id = ?::uuid AND key_id = ?",
            ).use { statement ->
                statement.setString(1, account.botUserId)
                statement.setInt(2, signedPreKey.id)
                statement.executeQuery().use { rows ->
                    rows.next() &&
                        rows.getBytes("public_key")
                            .contentEquals(signedPreKey.keyPair.publicKey.serialize())
                }
            }
        }

    private fun publishedOneTimePreKeyCount(account: BotAccount): Int =
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT COUNT(*) FROM one_time_prekeys WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, account.botUserId)
                statement.executeQuery().use { rows ->
                    rows.next()
                    rows.getInt(1)
                }
            }
        }

    private fun markPeerConsumedKeys(account: BotAccount) {
        BotDatabase.getConnection().use { conn ->
            val marked = conn.prepareStatement(
                """UPDATE bot_one_time_prekey
                   SET consumed_at = NOW()
                   WHERE consumed_at IS NULL
                     AND key_id NOT IN (
                         SELECT key_id FROM one_time_prekeys WHERE user_id = ?::uuid
                     )""",
            ).use { statement ->
                statement.setString(1, account.botUserId)
                statement.executeUpdate()
            }
            if (marked > 0) {
                log.info("[Bootstrap] {} one-time prekey peer tarafindan tuketilmis", marked)
            }
        }
    }

    private fun unconsumedLocalOneTimePreKeys(): List<PublishedPreKey> =
        BotDatabase.getConnection().use { conn ->
            conn.prepareStatement(
                """SELECT key_id, public_key FROM bot_one_time_prekey
                   WHERE consumed_at IS NULL ORDER BY key_id""",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    buildList {
                        while (rows.next()) {
                            add(PublishedPreKey(rows.getInt("key_id"), rows.getBytes("public_key")))
                        }
                    }
                }
            }
        }

    private inline fun inTransaction(connection: Connection, block: () -> Unit) {
        connection.autoCommit = false
        try {
            block()
            connection.commit()
        } catch (e: Exception) {
            connection.rollback()
            throw e
        } finally {
            connection.autoCommit = true
        }
    }
}
