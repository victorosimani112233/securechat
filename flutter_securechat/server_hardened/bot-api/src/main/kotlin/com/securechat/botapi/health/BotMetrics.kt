package com.securechat.botapi.health

import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.Tags
import io.micrometer.core.instrument.binder.jvm.ClassLoaderMetrics
import io.micrometer.core.instrument.binder.jvm.JvmGcMetrics
import io.micrometer.core.instrument.binder.jvm.JvmMemoryMetrics
import io.micrometer.core.instrument.binder.jvm.JvmThreadMetrics
import io.micrometer.core.instrument.binder.system.ProcessorMetrics
import io.micrometer.prometheus.PrometheusConfig
import io.micrometer.prometheus.PrometheusMeterRegistry

/**
 * Bot-api icin ayri Prometheus registry — signaling-server'in registry'sinden bagimsiz.
 */
object BotMetrics {

    val registry: PrometheusMeterRegistry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT).apply {
        ClassLoaderMetrics().bindTo(this)
        JvmMemoryMetrics().bindTo(this)
        JvmGcMetrics().bindTo(this)
        JvmThreadMetrics().bindTo(this)
        ProcessorMetrics().bindTo(this)
    }

    // --- Sayaclar ---
    val sendAccepted: Counter = Counter.builder("botapi_send_accepted_total")
        .description("Bot-api uzerinden kabul edilen mesaj sayisi")
        .register(registry)

    val sendDelivered: Counter = Counter.builder("botapi_send_delivered_total")
        .description("WS uzerinden basariyla iletilen mesaj sayisi")
        .register(registry)

    val sendFailed: Counter = Counter.builder("botapi_send_failed_total")
        .description("Encrypt/delivery hatasi")
        .register(registry)

    val authFailed: Counter = Counter.builder("botapi_auth_failed_total")
        .description("JWT verify reddedildi")
        .register(registry)

    val replayBlocked: Counter = Counter.builder("botapi_replay_blocked_total")
        .description("Replay nonce tekrari yakalandi")
        .register(registry)

    val rateLimitHit: Counter = Counter.builder("botapi_rate_limit_hit_total")
        .description("Rate limit cezasi (herhangi katman)")
        .register(registry)

    val emergencyStopHit: Counter = Counter.builder("botapi_emergency_stop_hit_total")
        .description("Emergency stop ile reddedilen istek")
        .register(registry)

    fun authFailReason(reason: String): Counter =
        Counter.builder("botapi_auth_failed_reason_total")
            .tags(Tags.of("reason", reason))
            .register(registry)
}
