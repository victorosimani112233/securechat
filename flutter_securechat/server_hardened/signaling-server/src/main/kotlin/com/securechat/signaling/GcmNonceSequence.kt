package com.securechat.signaling

import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicLong

/**
 * Process-unique 64-bit random prefix plus an atomic 32-bit invocation counter.
 * A nonce is never returned twice by one instance and the key is refused after
 * the configured GCM invocation budget is exhausted.
 */
internal class GcmNonceSequence(
    random: SecureRandom = SecureRandom(),
    private val maxInvocations: Long = MAX_INVOCATIONS,
) {
    private val prefix = ByteArray(PREFIX_BYTES).also(random::nextBytes)
    private val counter = AtomicLong(0)

    init {
        require(maxInvocations in 1..MAX_INVOCATIONS) { "Invalid AES-GCM invocation budget" }
    }

    fun next(): ByteArray {
        val invocation = counter.getAndIncrement()
        check(invocation < maxInvocations) {
            "AES-GCM invocation budget exhausted; rotate the encryption key"
        }
        return ByteBuffer.allocate(NONCE_BYTES)
            .put(prefix)
            .putInt(invocation.toInt())
            .array()
    }

    internal fun allocations(): Long = counter.get().coerceAtMost(maxInvocations)

    companion object {
        const val NONCE_BYTES = 12
        private const val PREFIX_BYTES = 8
        private const val MAX_INVOCATIONS = 1L shl 32
    }
}
