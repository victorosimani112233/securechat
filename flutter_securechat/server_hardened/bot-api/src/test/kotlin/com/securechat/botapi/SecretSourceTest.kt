package com.securechat.botapi

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir

class SecretSourceTest {
    @TempDir
    lateinit var temporary: Path

    @Test
    fun `reads a mounted secret file`() {
        val value = SecretSource.required(
            "BOT_MASTER_KEY",
            mapOf("BOT_MASTER_KEY_FILE" to "/run/secrets/master"),
        ) { "base64-value\r\n" }
        assertEquals("base64-value", value)
    }

    @Test
    fun `does not let an environment value shadow a mounted secret`() {
        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "BOT_MASTER_KEY",
                mapOf(
                    "BOT_MASTER_KEY" to "old",
                    "BOT_MASTER_KEY_FILE" to "/run/secrets/master",
                ),
            ) { "new" }
        }
    }

    @Test
    fun `runtime reader rejects group-readable secret files`() {
        assumeTrue(Files.getFileStore(temporary).supportsFileAttributeView("posix"))
        val secret = Files.writeString(temporary.resolve("master"), "secret")
        Files.setPosixFilePermissions(secret, PosixFilePermissions.fromString("rw-r--r--"))

        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "BOT_MASTER_KEY",
                mapOf("BOT_MASTER_KEY_FILE" to secret.toString()),
            )
        }
    }

    @Test
    fun `runtime reader rejects a symlinked parent directory`() {
        assumeTrue(Files.getFileStore(temporary).supportsFileAttributeView("posix"))
        val real = Files.createDirectory(temporary.resolve("real"))
        val secret = Files.writeString(real.resolve("master"), "secret")
        Files.setPosixFilePermissions(secret, PosixFilePermissions.fromString("rw-------"))
        val link = temporary.resolve("linked")
        assumeTrue(runCatching { Files.createSymbolicLink(link, real); true }.getOrDefault(false))

        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "BOT_MASTER_KEY",
                mapOf("BOT_MASTER_KEY_FILE" to link.resolve("master").toString()),
            )
        }
    }
}
