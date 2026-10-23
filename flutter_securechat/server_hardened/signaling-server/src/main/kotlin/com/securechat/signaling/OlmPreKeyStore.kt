package com.securechat.signaling

import com.securechat.signaling.db.Database
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("OlmPreKeyStore")

/**
 * Olm (vodozemac) prekey materyalinin sunucu tarafi deposu.
 *
 * libsignal deposundan ([PreKeyStore]) ayri bir nesne, ama **ayri bir
 * kimlik namespace'i DEGIL**. Ayrim bilinmesi gereken en onemli nokta:
 *
 *  * Kimlik anahtari ve Ed25519 imza anahtari `users` SATIRINDA durur,
 *    libsignal kimligiyle ayni yerde. Hesabin tek bir kimlik konumu var.
 *    Kaldirilan v2 yolunda kimlik ikinci bir tabloda da tutulabiliyordu ve
 *    `PreKeyIdentityGuard.checkOtherNamespace` tam bu capraz kontrol icin
 *    vardi; o saldiri sinifini geri getirmemek icin kimlik bolunmuyor.
 *  * Yalniz tek kullanimlik anahtar HAVUZU ayri tabloda, cunku Olm
 *    anahtarlari 32 bayt, libsignal anahtarlari tur onekiyle 33 bayt.
 *    Havuz kimlik tasimaz, dolayisiyla ayri olmasi kimlik yuzeyi yaratmaz.
 *
 * Goc suresince libsignal kolonlari yerinde kalir; canli istemci hala onu
 * konusuyor.
 */
object OlmPreKeyStore {

    /** Curve25519 ve Ed25519 acik anahtarlari. */
    const val KEY_LENGTH = 32

    /** Ed25519 imzasi. */
    const val SIGNATURE_LENGTH = 64

    data class FallbackKey(val publicKey: ByteArray, val signature: ByteArray) {
        override fun equals(other: Any?): Boolean =
            other is FallbackKey &&
                publicKey.contentEquals(other.publicKey) &&
                signature.contentEquals(other.signature)

        override fun hashCode(): Int =
            publicKey.contentHashCode() * 31 + signature.contentHashCode()
    }

    /**
     * [keyId] TAMSAYI DEGIL.
     *
     * Olm anahtar kimligi vodozemac tarafindan uretilir ve kabloda base64
     * bir dizedir. Tamsayiya cevirmek icin cozup u64 okumak gerekirdi;
     * kirilgan oldugu gibi, istemcinin kimligi ile sunucunun sakladigini
     * ayirabilen bir donusum de ekler. Catisma tespiti kimligin dogru
     * saklanmasina dayandigi icin bu kozmetik bir ayrinti degil.
     */
    data class OneTimeKey(val keyId: String, val publicKey: ByteArray) {
        override fun equals(other: Any?): Boolean =
            other is OneTimeKey &&
                keyId == other.keyId &&
                publicKey.contentEquals(other.publicKey)

        override fun hashCode(): Int = keyId.hashCode() * 31 + publicKey.contentHashCode()
    }

    data class Bundle(
        val identityKey: ByteArray,
        val signingKey: ByteArray,
        val oneTimeKey: ByteArray?,
        val fallbackKey: FallbackKey?,
    ) {
        override fun equals(other: Any?): Boolean =
            other is Bundle &&
                identityKey.contentEquals(other.identityKey) &&
                signingKey.contentEquals(other.signingKey) &&
                (oneTimeKey?.contentEquals(other.oneTimeKey ?: ByteArray(0))
                    ?: (other.oneTimeKey == null)) &&
                fallbackKey == other.fallbackKey

        override fun hashCode(): Int =
            identityKey.contentHashCode() * 31 + signingKey.contentHashCode()
    }

    /**
     * Ayni `keyId` farkli anahtar materyaliyle yeniden yuklendi.
     *
     * Bunun ayri bir hata olmasi gerekiyor ve sebebi somut: libsignal
     * havuzunda ayni durum `ON CONFLICT (user_id, key_id) DO NOTHING` ile
     * ele aliniyor, yani sunucu **eski anahtari tutup basari donuyor**.
     * Istemci yeni anahtarin yuklendigini sanir, karsi taraf eski anahtari
     * ceker ve kurulan oturum cozulemez. Sessizce yutulan bir prekey
     * yuklemesi bu projede daha once P0 uretti (2026-06-09; `ON CONFLICT DO
     * NOTHING` yeni upload'u yutuyordu, istemcide X3DH uyusmazligi ve
     * "No valid sessions" dongusu). Olm havuzunda bu durum sessiz kalmiyor.
     *
     * AYNI materyalin yeniden yuklenmesi hata degildir: yeniden denemenin
     * idempotent olmasi gerekir, yoksa agi kopan bir istemci kalici olarak
     * tikanir.
     */
    class KeyConflictException(val keyId: String) : IllegalStateException(
        "Olm one-time prekey $keyId already exists with different material",
    )

    /**
     * Hesapta farkli bir Olm kimligi kayitli. Cihazin yerel kimligi
     * sunucudakinden sapmis demektir; yeni kimlik yalniz acik kurtarma ile
     * kabul edilir. Istemci bunu ayirt edip kullaniciyi kurtarmaya
     * yonlendirebilsin diye ayri tip (QA 2026-10-13 T5 madde 3).
     */
    class IdentityRecoveryRequiredException :
        IllegalStateException("Explicit identity recovery required")

    /**
     * Kimligi ve imza anahtarini kurar ya da korur.
     *
     * [PreKeyStore.setIdentityKey] ile ayni kural: ilk yazma kimligi kurar,
     * sonraki yazmalar ayni olmak zorunda. Kimlik degisimi yalniz acik
     * kurtarma yoluyla olur; burada reddedilir.
     */
    fun setIdentity(
        userId: String,
        identityKey: ByteArray,
        signingKey: ByteArray,
        expectedEpoch: String? = null,
    ) {
        requireKey("identityKey", identityKey)
        requireKey("signingKey", signingKey)
        transaction(userId) { conn ->
            val existing = conn.prepareStatement(
                "SELECT olm_identity_key, signing_public_key, " +
                    "recovery_identity_pin, recovery_identity_protocol FROM users " +
                    "WHERE user_id = ?::uuid FOR UPDATE",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows ->
                    check(rows.next()) { "Unknown account" }
                    listOf(rows.getBytes(1), rows.getBytes(2), rows.getBytes(3)) to
                        rows.getString(4)
                }
            }
            PreKeyIdentityGuard.check(conn, userId, expectedEpoch = expectedEpoch)
            val (keys, pinProtocol) = existing
            val (oldIdentity, oldSigning, recoveryPin) = keys
            // Kurtarma (replace) Olm kimlik kolonlarini bosaltir ve yeni
            // cihazin Ed25519 imza anahtarini `recovery_identity_pin`'e yazar.
            // Ilk yukleme bu pine baglanmazsa kurtarma tokenine sahip biri
            // kurtarmada imzaladigindan BASKA bir imza anahtari yazabilirdi.
            // Eski v1/v2 pinleri (libsignal bicimi) Olm anahtariyla
            // karsilastirilamaz; onlar burada engel olmaz.
            if (pinProtocol == "olm" && recoveryPin != null &&
                !recoveryPin.contentEquals(signingKey)
            ) {
                throw IdentityRecoveryRequiredException()
            }
            if (oldIdentity != null && !oldIdentity.contentEquals(identityKey)) {
                throw IdentityRecoveryRequiredException()
            }
            // Imza anahtari da kimligin parcasi. Kimlik ayni kalirken imza
            // anahtarinin degismesine izin vermek, TOFU pinlemesini
            // (`identityBytes` ikisini birlikte pinler) anlamsiz kilardi.
            if (oldSigning != null && !oldSigning.contentEquals(signingKey)) {
                throw IdentityRecoveryRequiredException()
            }
            conn.prepareStatement(
                "UPDATE users SET olm_identity_key = ?, signing_public_key = ? " +
                    "WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setBytes(1, identityKey)
                statement.setBytes(2, signingKey)
                statement.setString(3, userId)
                statement.executeUpdate()
            }
        }
    }

    /** Fallback (last-resort) anahtarini yazar; hesap basina bir satir. */
    fun setFallbackKey(
        userId: String,
        key: FallbackKey,
        expectedEpoch: String? = null,
    ) {
        requireKey("fallbackKey", key.publicKey)
        require(key.signature.size == SIGNATURE_LENGTH) {
            "fallbackKeySignature must be $SIGNATURE_LENGTH bytes"
        }
        transaction(userId) { conn ->
            PreKeyIdentityGuard.check(conn, userId, expectedEpoch = expectedEpoch)
            conn.prepareStatement(
                """INSERT INTO olm_fallback_keys (user_id, public_key, signature)
                   VALUES (?::uuid, ?, ?)
                   ON CONFLICT (user_id) DO UPDATE
                       SET public_key = EXCLUDED.public_key,
                           signature = EXCLUDED.signature,
                           created_at = NOW()""",
            ).use { statement ->
                statement.setString(1, userId)
                statement.setBytes(2, key.publicKey)
                statement.setBytes(3, key.signature)
                statement.executeUpdate()
            }
        }
    }

    /**
     * Tek kullanimlik anahtarlari havuza ekler.
     *
     * Ayni `keyId`'nin farkli materyalle gelmesi [KeyConflictException]
     * yukseltir; ayni materyalle gelmesi sessizce kabul edilir.
     */
    fun addOneTimeKeys(
        userId: String,
        keys: List<OneTimeKey>,
        expectedEpoch: String? = null,
    ) {
        if (keys.isEmpty()) return
        for (key in keys) requireKey("oneTimeKey ${key.keyId}", key.publicKey)
        val byId = keys.associateBy { it.keyId }
        require(byId.size == keys.size) { "Duplicate keyId in the same upload" }

        transaction(userId) { conn ->
            PreKeyIdentityGuard.check(conn, userId, expectedEpoch = expectedEpoch)
            // Catismayi yazmadan ONCE tespit et. Yazdiktan sonra bakmak,
            // catisan satirlar icin "yazilmadi" ile "ayni zaten vardi"
            // arasini ayirt etmeyi zorlastirir.
            conn.prepareStatement(
                "SELECT key_id, public_key FROM olm_one_time_prekeys " +
                    "WHERE user_id = ?::uuid AND key_id = ANY (?)",
            ).use { statement ->
                statement.setString(1, userId)
                statement.setArray(
                    2,
                    conn.createArrayOf("text", byId.keys.toTypedArray()),
                )
                statement.executeQuery().use { rows ->
                    while (rows.next()) {
                        val keyId = rows.getString(1)
                        val stored = rows.getBytes(2)
                        val incoming = byId.getValue(keyId).publicKey
                        if (!stored.contentEquals(incoming)) {
                            throw KeyConflictException(keyId)
                        }
                    }
                }
            }
            conn.prepareStatement(
                "INSERT INTO olm_one_time_prekeys (user_id, key_id, public_key) " +
                    "VALUES (?::uuid, ?, ?) ON CONFLICT (user_id, key_id) DO NOTHING",
            ).use { statement ->
                for (key in keys) {
                    statement.setString(1, userId)
                    statement.setString(2, key.keyId)
                    statement.setBytes(3, key.publicKey)
                    statement.addBatch()
                }
                statement.executeBatch()
            }
        }
        log.info("[OlmPreKey] {} adet one-time key eklendi", keys.size)
    }

    /**
     * Karsi tarafin bundle'i; bir tek kullanimlik anahtar atomik tuketilir.
     *
     * Havuz bossa `oneTimeKey` null doner ama fallback varsa bundle yine
     * kullanilabilir. Ikisi de yoksa null doner — oturum kurulamaz.
     */
    fun fetchBundle(userId: String): Bundle? {
        return try {
            Database.getConnection().use { conn ->
                val identity = conn.prepareStatement(
                    "SELECT olm_identity_key, signing_public_key FROM users " +
                        "WHERE user_id = ?::uuid",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        if (!rows.next()) return null
                        val identityKey = rows.getBytes(1) ?: return null
                        val signingKey = rows.getBytes(2) ?: return null
                        identityKey to signingKey
                    }
                }

                // Tuketilen satir ve erisim zamani PostgreSQL'de bir
                // haberlesme zaman cizgisi olusturmamali; satir silinerek
                // tuketilir.
                val oneTimeKey = conn.prepareStatement(
                    """WITH next_key AS (
                           SELECT id FROM olm_one_time_prekeys
                           WHERE user_id = ?::uuid
                           ORDER BY id LIMIT 1
                           FOR UPDATE SKIP LOCKED
                       )
                       DELETE FROM olm_one_time_prekeys
                       USING next_key
                       WHERE olm_one_time_prekeys.id = next_key.id
                       RETURNING olm_one_time_prekeys.public_key""",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        if (rows.next()) rows.getBytes(1) else null
                    }
                }

                val fallback = conn.prepareStatement(
                    "SELECT public_key, signature FROM olm_fallback_keys " +
                        "WHERE user_id = ?::uuid",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeQuery().use { rows ->
                        if (rows.next()) {
                            FallbackKey(rows.getBytes(1), rows.getBytes(2))
                        } else {
                            null
                        }
                    }
                }

                if (oneTimeKey == null && fallback == null) return null
                Bundle(identity.first, identity.second, oneTimeKey, fallback)
            }
        } catch (error: Exception) {
            log.error("[OlmPreKey] Bundle fetch hatasi: {}", error.javaClass.simpleName)
            null
        }
    }

    /** Kalan tuketilmemis tek kullanimlik anahtar sayisi. */
    fun unconsumedCount(userId: String): Int = try {
        Database.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT COUNT(*) FROM olm_one_time_prekeys WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows ->
                    if (rows.next()) rows.getInt(1) else 0
                }
            }
        }
    } catch (error: Exception) {
        log.error("[OlmPreKey] Sayim hatasi: {}", error.javaClass.simpleName)
        0
    }

    /**
     * Olm kimligini hic yayinlamamis hesaplar: yalniz libsignal kimligi olan
     * eski hesaplar ve anahtar yuklemeden yarim kalmis kayitlar. Sorgu
     * basarisizsa null: cagiran filtrelememeyi secer.
     */
    fun keylessUsers(): Set<String>? = try {
        Database.getConnection().use { conn ->
            conn.createStatement().use { statement ->
                statement.executeQuery(
                    "SELECT user_id::text FROM users " +
                        "WHERE olm_identity_key IS NULL",
                ).use { rows ->
                    buildSet { while (rows.next()) add(rows.getString(1)) }
                }
            }
        }
    } catch (error: Exception) {
        log.error("[OlmPreKey] Kimlik listesi hatasi: {}", error.javaClass.simpleName)
        null
    }

    /** Hesabin Olm kimligi kurulmus mu. */
    fun hasIdentity(userId: String): Boolean = try {
        Database.getConnection().use { conn ->
            conn.prepareStatement(
                "SELECT 1 FROM users WHERE user_id = ?::uuid " +
                    "AND olm_identity_key IS NOT NULL AND signing_public_key IS NOT NULL",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows -> rows.next() }
            }
        }
    } catch (error: Exception) {
        log.error("[OlmPreKey] Kimlik sorgusu hatasi: {}", error.javaClass.simpleName)
        false
    }

    private fun requireKey(field: String, key: ByteArray) {
        // 33 bayt libsignal'in tur onekli kodlamasi. Oneki kirpip kabul
        // etmek YANLIS olurdu: istemcinin Olm anahtari diye gonderdigi sey
        // aslinda libsignal anahtariysa, kurulacak oturum cozulemez.
        require(key.size == KEY_LENGTH) {
            if (key.size == KEY_LENGTH + 1) {
                "$field is ${key.size} bytes; that is libsignal's type-prefixed " +
                    "encoding, not an Olm key"
            } else {
                "$field must be $KEY_LENGTH bytes, got ${key.size}"
            }
        }
    }

    private fun <T> transaction(userId: String, body: (java.sql.Connection) -> T): T =
        try {
            Database.getConnection().use { conn ->
                conn.autoCommit = false
                try {
                    val result = body(conn)
                    conn.commit()
                    result
                } catch (error: Exception) {
                    conn.rollback()
                    throw error
                } finally {
                    conn.autoCommit = true
                }
            }
        } catch (error: Exception) {
            // Istisnanin MESAJI da yazilir. Yalniz sinif adi yazmak bu kodu
            // teshis edilemez yapiyordu: buradaki `IllegalStateException`
            // bes ayri `check()` cagrisindan gelebiliyor ("Unknown account",
            // "Explicit identity recovery required", "Superseded credential
            // epoch", anahtar catismasi) ve hangisi oldugu loga hic
            // dusmuyordu.
            //
            // Mesajlar sunucu tarafi degismez adlari; kullanici icerigi ya
            // da anahtar materyali tasimazlar.
            log.error(
                "[OlmPreKey] Islem basarisiz ({}): {}: {}",
                userId.take(8),
                error.javaClass.simpleName,
                error.message,
            )
            throw error
        }
}
