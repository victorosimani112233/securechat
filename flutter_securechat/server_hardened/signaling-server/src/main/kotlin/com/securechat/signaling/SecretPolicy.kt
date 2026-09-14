package com.securechat.signaling

/** Minimum deploy-time policy for symmetric authentication secrets. */
internal object SecretPolicy {
    private const val MINIMUM_BYTES = 32

    fun requireStrong(name: String, value: String): String {
        val bytes = value.toByteArray(Charsets.UTF_8)
        require(bytes.size >= MINIMUM_BYTES) { "$name must contain at least $MINIMUM_BYTES bytes" }
        require(bytes.toSet().size >= 8) { "$name has insufficient symbol diversity" }
        require('\u0000' !in value) { "$name contains a NUL byte" }
        return value
    }

    fun requireStrongKey(name: String, value: ByteArray): ByteArray {
        require(value.size == MINIMUM_BYTES) { "$name must contain exactly $MINIMUM_BYTES bytes" }
        require(value.toSet().size >= 8) { "$name has insufficient byte diversity" }
        return value
    }
}
