package com.securechat.signaling

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.LongAdder

/**
 * Identity-free security event counters.
 *
 * No row, timestamp, IP, account pseudonym or metadata is persisted. The
 * existing call signature deliberately accepts and discards identity inputs
 * so route call sites cannot accidentally create another side channel.
 */
object AuditLog {
    private val counters = ConcurrentHashMap<String, LongAdder>()
    private val allowedEvent = Regex("^[A-Z][A-Z0-9_]{1,63}$")

    @Suppress("UNUSED_PARAMETER")
    fun log(
        userId: String? = null,
        eventType: String,
        metadata: Map<String, String>? = null,
        ipAddress: String? = null,
    ) {
        if (!allowedEvent.matches(eventType)) return
        counters.computeIfAbsent(eventType) { LongAdder() }.increment()
    }

    internal fun count(eventType: String): Long = counters[eventType]?.sum() ?: 0L
}
