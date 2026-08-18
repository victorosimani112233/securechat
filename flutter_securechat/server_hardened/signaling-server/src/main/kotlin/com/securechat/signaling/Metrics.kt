package com.securechat.signaling

import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.MeterRegistry
import io.micrometer.core.instrument.binder.jvm.ClassLoaderMetrics
import io.micrometer.core.instrument.binder.jvm.JvmGcMetrics
import io.micrometer.core.instrument.binder.jvm.JvmMemoryMetrics
import io.micrometer.core.instrument.binder.jvm.JvmThreadMetrics
import io.micrometer.core.instrument.binder.system.ProcessorMetrics
import io.micrometer.prometheus.PrometheusConfig
import io.micrometer.prometheus.PrometheusMeterRegistry

/**
 * Prometheus metrics — `/metrics` endpoint'ine expose edilir.
 *
 * Kayitlar:
 *   - JVM (memory, GC, threads, classloader)
 *   - System (CPU, processor count)
 *   - Custom: WS connections, messages, fanout, FCM, auth events
 */
object Metrics {

    val registry: PrometheusMeterRegistry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT).apply {
        // JVM ve system metrik'leri
        ClassLoaderMetrics().bindTo(this)
        JvmMemoryMetrics().bindTo(this)
        JvmGcMetrics().bindTo(this)
        JvmThreadMetrics().bindTo(this)
        ProcessorMetrics().bindTo(this)
    }

    // --- Custom counter'lar ---

    val wsConnections: Counter = Counter.builder("securechat_ws_connections_total")
        .description("Toplam WebSocket baglanti sayisi")
        .register(registry)

    val wsAuthFailures: Counter = Counter.builder("securechat_ws_auth_failures_total")
        .description("WebSocket auth fail sayisi (token missing/invalid/mismatch)")
        .register(registry)

    val messagesRouted: Counter = Counter.builder("securechat_messages_routed_total")
        .description("WebSocket uzerinden iletilen mesaj sayisi")
        .register(registry)

    val messagesQueued: Counter = Counter.builder("securechat_messages_queued_total")
        .description("Offline kuyruga eklenen mesaj sayisi")
        .register(registry)

    val groupFanouts: Counter = Counter.builder("securechat_group_fanouts_total")
        .description("Grup mesaj fanout sayisi")
        .register(registry)

    val fcmPushes: Counter = Counter.builder("securechat_fcm_pushes_total")
        .description("FCM wake-up push sayisi")
        .tag("status", "sent")
        .register(registry)

    val fcmPushFailures: Counter = Counter.builder("securechat_fcm_pushes_total")
        .description("FCM wake-up push fail sayisi")
        .tag("status", "failed")
        .register(registry)

    val authRegistrations: Counter = Counter.builder("securechat_auth_registrations_total")
        .description("Yeni kullanici kayit sayisi")
        .register(registry)

    val authLogouts: Counter = Counter.builder("securechat_auth_logouts_total")
        .description("Logout sayisi")
        .register(registry)

    val otpRequests: Counter = Counter.builder("securechat_otp_requests_total")
        .description("OTP istegi sayisi")
        .register(registry)

    val otpVerifications: Counter = Counter.builder("securechat_otp_verifications_total")
        .description("OTP basarili dogrulama sayisi")
        .tag("result", "success")
        .register(registry)

    val otpFailures: Counter = Counter.builder("securechat_otp_verifications_total")
        .description("OTP basarisiz dogrulama sayisi")
        .tag("result", "failed")
        .register(registry)

    /** Aktif WebSocket connection sayisini gostergesi (gauge) — ConnectionManager set eder. */
    fun registerOnlineUsersGauge(supplier: () -> Int) {
        io.micrometer.core.instrument.Gauge.builder("securechat_online_users", supplier) { it().toDouble() }
            .description("Anlik aktif WebSocket baglantisi")
            .register(registry)
    }
}
