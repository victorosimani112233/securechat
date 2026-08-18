package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory

private val retentionLog = LoggerFactory.getLogger("PrivacyRetentionWorker")

/**
 * Enforces the bounded persistence contract.
 *
 * Startup cleanup is synchronous and fail-closed. If a periodic cleanup later
 * fails, the privacy health gate closes, live sockets are disconnected and the
 * worker retries every minute. Traffic is admitted again only after a complete
 * transaction succeeds.
 */
object PrivacyRetentionWorker {
    private const val NORMAL_INTERVAL_MILLIS = 6 * 60 * 60 * 1000L
    private const val FAILURE_RETRY_MILLIS = 60 * 1000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val healthy = AtomicBoolean(false)
    private var job: Job? = null
    private var fcmTokenStore: FcmTokenStore? = null
    private var unhealthyHandler: (suspend () -> Unit)? = null

    @Synchronized
    fun start(
        fcmTokenStore: FcmTokenStore,
        onUnhealthy: suspend () -> Unit = {},
    ) {
        if (job != null) return
        this.fcmTokenStore = fcmTokenStore
        this.unhealthyHandler = onUnhealthy

        // No listener is created until this transaction succeeds.
        runOnce()

        job = scope.launch {
            var nextDelay = NORMAL_INTERVAL_MILLIS
            while (isActive) {
                delay(nextDelay)
                try {
                    cleanupTransaction(ServerPrivacy.config, fcmTokenStore)
                    healthy.set(true)
                    nextDelay = NORMAL_INTERVAL_MILLIS
                } catch (error: Exception) {
                    val wasHealthy = healthy.getAndSet(false)
                    retentionLog.error(
                        "[Privacy] Retention cleanup failed; traffic gate closed: {}",
                        error.javaClass.simpleName,
                    )
                    if (wasHealthy) {
                        try {
                            unhealthyHandler?.invoke()
                        } catch (handlerError: Exception) {
                            retentionLog.error(
                                "[Privacy] Unhealthy handler failed: {}",
                                handlerError.javaClass.simpleName,
                            )
                        }
                    }
                    nextDelay = FAILURE_RETRY_MILLIS
                }
            }
        }
    }

    fun isHealthy(): Boolean = healthy.get()

    /** Visible for integration tests and operational maintenance commands. */
    fun runOnce(): RetentionResult = try {
        cleanupTransaction(ServerPrivacy.config, fcmTokenStore).also { healthy.set(true) }
    } catch (error: Exception) {
        healthy.set(false)
        throw IllegalStateException("Privacy retention cleanup failed", error)
    }

    /** Explicit-config boundary used by PostgreSQL retention integration tests. */
    internal fun runOnce(config: PrivacyConfig): RetentionResult =
        cleanupTransaction(config, null)

    private fun cleanupTransaction(
        config: PrivacyConfig,
        tokenStore: FcmTokenStore?,
    ): RetentionResult {
        return Database.getConnection().use { connection ->
            connection.autoCommit = false
            try {
                val botPreKeys = connection.prepareStatement(
                    "DELETE FROM bot_one_time_prekey WHERE consumed_at IS NOT NULL " +
                        "AND consumed_at < NOW() - (? * INTERVAL '1 hour')",
                ).use { statement ->
                    statement.setInt(1, config.consumedPreKeyRetentionHours)
                    statement.executeUpdate()
                }
                // Replay penceresi kapanmis registration grant isaretleri.
                RegistrationGrants.purgeExpired(connection)
                val pushTokens = connection.prepareStatement(
                    "DELETE FROM fcm_tokens WHERE registered_on < CURRENT_DATE - ?",
                ).use { statement ->
                    statement.setInt(1, config.pushTokenRetentionDays)
                    statement.executeUpdate()
                }
                val apiClients = connection.prepareStatement(
                    """DELETE FROM api_client
                       WHERE (revoked_at IS NOT NULL AND
                              revoked_at < NOW() - (? * INTERVAL '1 day'))
                          OR (expires_at IS NOT NULL AND
                              expires_at < NOW() - (? * INTERVAL '1 day'))""",
                ).use { statement ->
                    statement.setInt(1, config.apiClientRetentionDays)
                    statement.setInt(2, config.apiClientRetentionDays)
                    statement.executeUpdate()
                }
                connection.commit()
                val pushCutoff = System.currentTimeMillis() -
                    config.pushTokenRetentionDays * 86_400_000L
                tokenStore?.purgeExpiredMemory(pushCutoff)
                RetentionResult(botPreKeys, pushTokens, apiClients)
            } catch (error: Exception) {
                connection.rollback()
                throw error
            } finally {
                connection.autoCommit = true
            }
        }.also { result ->
            if (result.total > 0) {
                retentionLog.info(
                    "[Privacy] Retention cleanup: consumed_prekeys={}, push_tokens={}, api_clients={}",
                    result.consumedPreKeyRows,
                    result.pushTokenRows,
                    result.apiClientRows,
                )
            }
        }
    }

    suspend fun stop() {
        val active = synchronized(this) {
            val current = job
            job = null
            fcmTokenStore = null
            unhealthyHandler = null
            healthy.set(false)
            current
        }
        active?.cancelAndJoin()
    }
}

data class RetentionResult(
    val consumedPreKeyRows: Int,
    val pushTokenRows: Int,
    val apiClientRows: Int,
) {
    val total: Int get() = consumedPreKeyRows + pushTokenRows + apiClientRows
}
