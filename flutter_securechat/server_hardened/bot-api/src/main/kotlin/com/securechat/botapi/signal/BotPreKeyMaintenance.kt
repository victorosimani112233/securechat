package com.securechat.botapi.signal

import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import org.slf4j.LoggerFactory

private val maintenanceLog = LoggerFactory.getLogger("BotPreKeyMaintenance")

/** Keeps the bot's published pre-key bundle current while the process is live. */
object BotPreKeyMaintenance {
    private const val INTERVAL_HOURS = 6L
    private var executor: ScheduledExecutorService? = null

    @Synchronized
    fun start() {
        if (executor != null) return
        executor = Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "bot-prekey-maintenance").apply { isDaemon = true }
        }.also { scheduler ->
            scheduler.scheduleWithFixedDelay(
                {
                    runCatching { BotIdentityBootstrap.ensureRegistered() }
                        .onFailure {
                            maintenanceLog.warn(
                                "[Maintenance] Prekey reconcile failed: {}",
                                it.javaClass.simpleName,
                            )
                        }
                },
                INTERVAL_HOURS,
                INTERVAL_HOURS,
                TimeUnit.HOURS,
            )
        }
    }

    @Synchronized
    fun stop() {
        executor?.shutdownNow()
        executor = null
    }
}
