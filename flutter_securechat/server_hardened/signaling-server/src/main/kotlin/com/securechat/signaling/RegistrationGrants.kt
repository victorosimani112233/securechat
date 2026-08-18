package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.sql.Connection
import java.sql.Timestamp
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("RegistrationGrants")

/**
 * Registration grant'in tek kullanimlik olmasini kalici olarak zorlar.
 *
 * Onceki isaret yalniz persistence'siz ve `allkeys-lru` calisan Redis'teydi:
 * grant'in 15 dakikalik omru icinde bir restart veya eviction, tuketilmis bir
 * grant'i yeniden oynatilabilir hale getiriyordu. Tuketim artik hesap
 * kaydiyla **ayni transaction** icinde yapilir; kayit geri alinirsa grant da
 * tuketilmemis sayilir, kayit basarili olursa grant kesin olarak yanar.
 *
 * Satirda hesap, e-posta, telefon veya directory referansi yoktur: yalniz
 * grant'in rastgele JTI'sinin keyed blind index'i ve replay penceresinin
 * bitisi tutulur.
 */
object RegistrationGrants {

    /**
     * @return grant bu transaction icinde tuketildiyse true; daha once
     *   tuketilmisse (replay) false.
     */
    fun consume(connection: Connection, claim: AuthService.RegistrationGrant): Boolean =
        connection.prepareStatement(
            """INSERT INTO registration_grant_use(grant_index, expires_at)
               VALUES (?, ?) ON CONFLICT (grant_index) DO NOTHING""",
        ).use { statement ->
            statement.setString(1, ServerPrivacy.registrationTokenUseKey(claim.grantId))
            statement.setTimestamp(2, Timestamp(claim.expiresAtMs))
            statement.executeUpdate() == 1
        }

    /** Replay penceresi kapanmis satirlari siler. */
    fun purgeExpired(connection: Connection): Int =
        connection.prepareStatement(
            "DELETE FROM registration_grant_use WHERE expires_at < NOW()",
        ).use { statement -> statement.executeUpdate() }

    /**
     * Grant tuketimi ile hesap kaydini tek transaction'da yurutur.
     *
     * @return kayitli kullanici; grant replay ise null.
     */
    fun claimAccount(
        claim: AuthService.RegistrationGrant,
        candidate: RegisteredUser,
        userRegistry: UserRegistry,
    ): RegisteredUser? {
        val committed = Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                if (!consume(connection, claim)) {
                    connection.rollback()
                    return@use false
                }
                if (!userRegistry.insertRegistration(connection, candidate)) {
                    // Directory kimligi arada baskasi tarafindan alinmis:
                    // grant da tuketilmemis kalir.
                    connection.rollback()
                    throw DirectoryIdentityAlreadyRegisteredException()
                }
                connection.commit()
                true
            } catch (e: Exception) {
                runCatching { connection.rollback() }
                throw e
            } finally {
                connection.autoCommit = true
            }
        }
        if (!committed) {
            log.warn("[Register] Tuketilmis registration grant yeniden sunuldu")
            return null
        }
        userRegistry.cacheRegistered(candidate)
        return candidate
    }
}
