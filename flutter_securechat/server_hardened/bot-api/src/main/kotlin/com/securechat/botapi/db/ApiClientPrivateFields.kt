package com.securechat.botapi.db

import com.securechat.botapi.signal.KeyEncryptor
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.nio.charset.StandardCharsets
import java.util.Base64

/** AEAD envelope for API-client name and recipient allow-list columns. */
object ApiClientPrivateFields {
    private const val prefix = "AC1:"
    private const val maxEntries = 1024
    private const val maxEntryBytes = 512

    fun sealName(kid: String, name: String): String {
        require(name.isNotBlank() && name.length <= 128) { "Isim 1-128 karakter" }
        return seal("name", kid, name.toByteArray(StandardCharsets.UTF_8))
    }

    fun openName(kid: String, envelope: String): String =
        String(open("name", kid, envelope), StandardCharsets.UTF_8).also {
            require(it.isNotBlank() && it.length <= 128) { "Invalid API client name" }
        }

    fun sealAllowList(kid: String, values: List<String>): String {
        require(values.size <= maxEntries) { "Allow-list cok buyuk" }
        val bytes = ByteArrayOutputStream().use { buffer ->
            DataOutputStream(buffer).use { output ->
                output.writeInt(values.size)
                for (value in values) {
                    val encoded = value.toByteArray(StandardCharsets.UTF_8)
                    require(encoded.isNotEmpty() && encoded.size <= maxEntryBytes) {
                        "Allow-list girdisi gecersiz"
                    }
                    output.writeInt(encoded.size)
                    output.write(encoded)
                }
            }
            buffer.toByteArray()
        }
        return seal("allow-list", kid, bytes)
    }

    fun openAllowList(kid: String, envelope: String): List<String> {
        val plaintext = open("allow-list", kid, envelope)
        return DataInputStream(ByteArrayInputStream(plaintext)).use { input ->
            val count = input.readInt()
            require(count in 0..maxEntries) { "Invalid allow-list count" }
            buildList(count) {
                repeat(count) {
                    val length = input.readInt()
                    require(length in 1..maxEntryBytes) { "Invalid allow-list entry" }
                    add(String(input.readNBytes(length), StandardCharsets.UTF_8))
                }
                require(input.available() == 0) { "Trailing allow-list data" }
            }
        }
    }

    fun isSealed(value: String): Boolean = value.startsWith(prefix)

    private fun seal(purpose: String, kid: String, plaintext: ByteArray): String {
        val wrapped = KeyEncryptor.wrap(plaintext, aad(purpose, kid))
        return prefix + Base64.getUrlEncoder().withoutPadding()
            .encodeToString(wrapped.nonce + wrapped.ciphertext)
    }

    private fun open(purpose: String, kid: String, envelope: String): ByteArray {
        require(isSealed(envelope)) { "Legacy plaintext API client field rejected" }
        val packed = Base64.getUrlDecoder().decode(envelope.removePrefix(prefix))
        require(packed.size >= 12 + 16) { "API client envelope is too short" }
        return KeyEncryptor.unwrap(
            packed.copyOfRange(12, packed.size),
            packed.copyOfRange(0, 12),
            aad(purpose, kid)
        )
    }

    private fun aad(purpose: String, kid: String): ByteArray =
        "securechat-api-client-v1\u0000$purpose\u0000$kid"
            .toByteArray(StandardCharsets.UTF_8)
}
