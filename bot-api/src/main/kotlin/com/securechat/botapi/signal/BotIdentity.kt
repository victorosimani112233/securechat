package com.securechat.botapi.signal

import java.util.concurrent.atomic.AtomicReference

/**
 * Bot identity runtime holder — bootstrap sonrasi doldurulur, send pipeline
 * tarafindan okunur. AtomicReference ile thread-safe.
 */
object BotIdentity {

    data class Snapshot(
        val botUserId: String,
        val registrationId: Int
    )

    private val ref = AtomicReference<Snapshot>()

    fun set(botUserId: String, registrationId: Int) {
        ref.set(Snapshot(botUserId, registrationId))
    }

    fun get(): Snapshot = ref.get()
        ?: throw IllegalStateException("BotIdentity henuz set edilmemis — bootstrap calistirilmali")

    fun isReady(): Boolean = ref.get() != null
}
