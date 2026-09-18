package com.securechat.signaling

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

    private fun secureDirectory(path: Path): Path {
        assumeTrue(Files.getFileStore(path).supportsFileAttributeView("posix"))
        Files.setPosixFilePermissions(path, PosixFilePermissions.fromString("rwx------"))
        return path
    }

    @Test
    fun `runtime reader accepts an owner-only file in a protected directory`() {
        val directory = secureDirectory(temporary.resolve("protected").also(Files::createDirectory))
        val secret = Files.writeString(directory.resolve("jwt"), "secret-value\n")
        Files.setPosixFilePermissions(secret, PosixFilePermissions.fromString("rw-------"))

        assertEquals(
            "secret-value",
            SecretSource.required("JWT_SECRET", mapOf("JWT_SECRET_FILE" to secret.toString())),
        )
    }

    @Test
    fun `runtime reader rejects a group-writable parent directory`() {
        assumeTrue(Files.getFileStore(temporary).supportsFileAttributeView("posix"))
        val directory = temporary.resolve("writable").also(Files::createDirectory)
        Files.setPosixFilePermissions(directory, PosixFilePermissions.fromString("rwxrwx---"))
        val secret = Files.writeString(directory.resolve("jwt"), "secret")
        Files.setPosixFilePermissions(secret, PosixFilePermissions.fromString("rw-------"))

        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required("JWT_SECRET", mapOf("JWT_SECRET_FILE" to secret.toString()))
        }
    }

    @Test
    fun `reads a mounted secret without retaining its newline`() {
        val value = SecretSource.required(
            "JWT_SECRET",
            mapOf("JWT_SECRET_FILE" to "/run/secrets/jwt"),
        ) { path ->
            assertEquals("/run/secrets/jwt", path)
            "secret-value\n"
        }
        assertEquals("secret-value", value)
    }

    @Test
    fun `rejects ambiguous direct and file values`() {
        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "JWT_SECRET",
                mapOf(
                    "JWT_SECRET" to "old-value",
                    "JWT_SECRET_FILE" to "/run/secrets/jwt",
                ),
            ) { "new-value" }
        }
    }

    @Test
    fun `rejects empty mounted secrets`() {
        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "JWT_SECRET",
                mapOf("JWT_SECRET_FILE" to "/run/secrets/jwt"),
            ) { "\n" }
        }
    }

    @Test
    fun `runtime reader rejects group-readable secret files`() {
        assumeTrue(Files.getFileStore(temporary).supportsFileAttributeView("posix"))
        val secret = Files.writeString(temporary.resolve("jwt"), "secret")
        Files.setPosixFilePermissions(secret, PosixFilePermissions.fromString("rw-r--r--"))

        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required("JWT_SECRET", mapOf("JWT_SECRET_FILE" to secret.toString()))
        }
    }

    @Test
    fun `runtime reader rejects a symlinked parent directory`() {
        assumeTrue(Files.getFileStore(temporary).supportsFileAttributeView("posix"))
        val real = Files.createDirectory(temporary.resolve("real"))
        val secret = Files.writeString(real.resolve("jwt"), "secret")
        Files.setPosixFilePermissions(secret, PosixFilePermissions.fromString("rw-------"))
        val link = temporary.resolve("linked")
        assumeTrue(runCatching { Files.createSymbolicLink(link, real); true }.getOrDefault(false))

        assertThrows(IllegalArgumentException::class.java) {
            SecretSource.required(
                "JWT_SECRET",
                mapOf("JWT_SECRET_FILE" to link.resolve("jwt").toString()),
            )
        }
    }
}
