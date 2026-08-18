package com.securechat.signaling

import com.securechat.signaling.db.Database
import kotlinx.coroutines.delay
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("AccountDeletion")

/**
 * Hesap silmenin idempotent ve kismi-hataya dayanikli yolu.
 *
 * Onceki akista PostgreSQL transaction'i commit olduktan sonra push cache'i,
 * registry, credential cache'i ve socket/queue temizligi sirayla ve
 * korumasiz calisiyordu. Aradaki bir hata kalan adimlarin hic
 * calismamasina ve istemcinin "silme basarisiz" gormesine yol aciyordu;
 * hesap ise DB'de zaten yoktu.
 *
 * Burada iki sey ayrilir:
 *
 *  1. **Kalici durum** — `fcm_tokens`, `bot_signal_session` ve `users` tek
 *     transaction'da silinir. Commit oldugu anda hesap authenticate
 *     edilemez hale gelir: `users` satiri yoksa hicbir token dogrulanamaz.
 *  2. **Gecici durum** — process RAM'i, acik socket ve kisa TTL'li Redis
 *     kuyruklari. Her adim yalitilmis calisir; biri hata verse bile
 *     digerleri atlanmaz.
 *
 * Kalici bir "tombstone" tablosu bilincli olarak eklenmedi: silinen hesabin
 * UUID'sini kalici bir satirda tutmak, tam da silinmesi istenen iliskiyi
 * geride birakirdi. Idempotanlik icin buna gerek de yoktur — `users`
 * satirinin yoklugu zaten kalici ve dogru isarettir.
 */
object AccountDeletion {

    private const val TRANSIENT_PURGE_ATTEMPTS = 3
    private const val RETRY_DELAY_MS = 50L

    enum class Outcome {
        /** Bu istek kalici kaydi sildi. */
        DELETED,

        /** Kayit zaten yoktu; silme istegi yine basarilidir. */
        ALREADY_ABSENT,
    }

    class Result(val outcome: Outcome, val residualSteps: List<String>)

    /** Adi ile birlikte, tekrar calistirilabilir tek bir temizlik adimi. */
    class PurgeStep(val name: String, val action: suspend () -> Unit)

    suspend fun execute(
        userId: String,
        connectionManager: ConnectionManager,
        userRegistry: UserRegistry,
        fcmTokenStore: FcmTokenStore?,
    ): Result = execute(
        userId = userId,
        steps = listOf(
            PurgeStep("push_cache") { fcmTokenStore?.removeToken(userId) },
            PurgeStep("registry") { userRegistry.removeUser(userId) },
            PurgeStep("credential_cache") { AuthService.forgetAccount(userId) },
            PurgeStep("socket") { connectionManager.closeUserSocket(userId) },
            PurgeStep("presence") { connectionManager.forgetPresenceState(userId) },
            PurgeStep("offline_queue") { connectionManager.purgeQueuedEnvelopes(userId) },
        ),
    )

    suspend fun execute(userId: String, steps: List<PurgeStep>): Result {
        val deleted = deleteDurableState(userId)
        val residual = purgeTransientState(steps)
        return Result(
            outcome = if (deleted) Outcome.DELETED else Outcome.ALREADY_ABSENT,
            residualSteps = residual,
        )
    }

    /** @return kalici satir bu cagride silindiyse true. */
    fun deleteDurableState(userId: String): Boolean =
        Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                connection.prepareStatement(
                    "DELETE FROM fcm_tokens WHERE user_index = ?",
                ).use { statement ->
                    statement.setString(1, ServerPrivacy.blindIndex("push-user", userId))
                    statement.executeUpdate()
                }
                connection.prepareStatement(
                    "DELETE FROM bot_signal_session WHERE recipient_index = ?",
                ).use { statement ->
                    statement.setString(1, ServerPrivacy.blindIndex("bot-signal-peer", userId))
                    statement.executeUpdate()
                }
                val removed = connection.prepareStatement(
                    "DELETE FROM users WHERE user_id = ?::uuid",
                ).use { statement ->
                    statement.setString(1, userId)
                    statement.executeUpdate()
                }
                connection.commit()
                removed == 1
            } catch (e: Exception) {
                connection.rollback()
                throw e
            } finally {
                connection.autoCommit = true
            }
        }

    /**
     * Gecici kopyalari temizler. Her adim bagimsizdir; bir adimin hatasi
     * digerlerini atlatmaz ve tekrar calistirildiginda ayni sonucu verir.
     *
     * @return kalan (basarisiz) adim adlari.
     */
    suspend fun purgeTransientState(steps: List<PurgeStep>): List<String> {
        var residual = emptyList<String>()
        for (attempt in 1..TRANSIENT_PURGE_ATTEMPTS) {
            val failed = mutableListOf<String>()
            for (step in steps) {
                // Bir adimin hatasi sonrakileri atlamaz.
                runCatching { step.action() }.onFailure { failed += step.name }
            }
            residual = failed
            if (residual.isEmpty()) return emptyList()
            if (attempt < TRANSIENT_PURGE_ATTEMPTS) delay(RETRY_DELAY_MS)
        }
        // Kalan kopyalar yalnizca RAM'de veya kisa TTL'li Redis'tedir ve
        // hesap artik authenticate olamadigi icin teslim edilemez.
        log.warn("[ACCOUNT] Gecici temizlik adimlari eksik kaldi: {}", residual.joinToString(","))
        return residual
    }
}
