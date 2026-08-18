package com.securechat.botapi.audit

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.LongAdder

/** Identity-free, process-RAM bot security counters; nothing is persisted. */
object BotAuditLog {
    private val counters = ConcurrentHashMap<String, LongAdder>()
    private val allowedEvent = Regex("^BOT_API_[A-Z0-9_]{1,55}$")

    @Suppress("UNUSED_PARAMETER")
    fun log(
        eventType: String,
        userId: String? = null,
        metadata: Map<String, String>? = null,
        ipAddress: String? = null,
    ) {
        if (!allowedEvent.matches(eventType)) return
        counters.computeIfAbsent(eventType) { LongAdder() }.increment()
    }

    internal fun count(eventType: String): Long = counters[eventType]?.sum() ?: 0L
}
