package com.securechat.botapi

import java.nio.charset.StandardCharsets
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.OpenOption
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.BasicFileAttributes

internal object SecretSource {
    private const val MAX_SECRET_BYTES = 65_536

    fun required(
        name: String,
        environment: Map<String, String> = System.getenv(),
        fileReader: (String) -> String = ::readFile,
    ): String = optional(name, environment, fileReader)
        ?: error("$name or ${name}_FILE is required")

    fun optional(
        name: String,
        environment: Map<String, String> = System.getenv(),
        fileReader: (String) -> String = ::readFile,
    ): String? {
        require(name.matches(Regex("^[A-Z][A-Z0-9_]{1,63}$"))) {
            "Invalid secret name"
        }
        val direct = environment[name]?.takeIf { it.isNotBlank() }
        val file = environment["${name}_FILE"]?.takeIf { it.isNotBlank() }
        require(direct == null || file == null) {
            "$name and ${name}_FILE cannot both be set"
        }
        val value = when {
            direct != null -> direct
            file != null -> fileReader(file).trimEnd('\r', '\n')
            else -> return null
        }
        require(value.isNotBlank()) { "$name secret is empty" }
        require(!value.contains('\u0000')) { "$name secret contains a NUL byte" }
        require(value.toByteArray(StandardCharsets.UTF_8).size <= MAX_SECRET_BYTES) {
            "$name secret exceeds $MAX_SECRET_BYTES bytes"
        }
        return value
    }

    private fun readFile(rawPath: String): String {
        val path = Path.of(rawPath)
        require(path.isAbsolute) { "Secret file path must be absolute" }
        val normalized = path.toAbsolutePath().normalize()
        require(normalized == path) { "Secret file path must be normalized" }
        val parent = normalized.parent ?: error("Secret file must have a parent directory")
        require(parent == parent.toRealPath()) {
            "Secret parent path must not contain symbolic-link components"
        }
        requireDirectoryNotWritableByOthers(parent)
        require(!Files.isSymbolicLink(path)) { "Secret file must not be a symbolic link" }
        require(Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
            "Secret path must be a regular file"
        }
        require(path.toAbsolutePath().normalize() == path.toRealPath()) {
            "Secret path must not contain symbolic-link components"
        }
        val size = Files.size(path)
        require(size in 1..MAX_SECRET_BYTES.toLong()) {
            "Secret file has an invalid size"
        }
        requireOwnerOnly(path)
        val before = Files.readAttributes(
            path,
            BasicFileAttributes::class.java,
            LinkOption.NOFOLLOW_LINKS,
        )
        val options = setOf<OpenOption>(StandardOpenOption.READ, LinkOption.NOFOLLOW_LINKS)
        return Files.newByteChannel(path, options).use { channel ->
            val opened = Files.readAttributes(
                path,
                BasicFileAttributes::class.java,
                LinkOption.NOFOLLOW_LINKS,
            )
            requireSameFile(before, opened)
            val expectedSize = channel.size()
            require(expectedSize in 1..MAX_SECRET_BYTES.toLong()) {
                "Secret file has an invalid size"
            }
            val buffer = ByteBuffer.allocate(expectedSize.toInt())
            while (buffer.hasRemaining()) {
                require(channel.read(buffer) >= 0) { "Secret file changed while reading" }
            }
            require(channel.read(ByteBuffer.allocate(1)) == -1) {
                "Secret file changed while reading"
            }
            val after = Files.readAttributes(
                path,
                BasicFileAttributes::class.java,
                LinkOption.NOFOLLOW_LINKS,
            )
            requireSameFile(before, after)
            String(buffer.array(), StandardCharsets.UTF_8)
        }
    }

    private fun requireSameFile(
        expected: BasicFileAttributes,
        actual: BasicFileAttributes,
    ) {
        require(
            expected.isRegularFile &&
                actual.isRegularFile &&
                expected.fileKey() != null &&
                expected.fileKey() == actual.fileKey() &&
                expected.size() == actual.size() &&
                expected.lastModifiedTime() == actual.lastModifiedTime()
        ) { "Secret file changed while reading" }
    }

    private fun requireDirectoryNotWritableByOthers(path: Path) {
        require(Files.getFileStore(path).supportsFileAttributeView("posix")) {
            "Secret filesystem must expose POSIX permissions"
        }
        val permissions = Files.getPosixFilePermissions(path)
        require(permissions.none { it.name == "GROUP_WRITE" || it.name == "OTHERS_WRITE" }) {
            "Secret parent directory must not be writable by group or others"
        }
    }

    private fun requireOwnerOnly(path: Path) {
        require(Files.getFileStore(path).supportsFileAttributeView("posix")) {
            "Secret filesystem must expose POSIX permissions"
        }
        val permissions = Files.getPosixFilePermissions(path)
        val exposed = permissions.filter { permission ->
            permission.name.startsWith("GROUP_") || permission.name.startsWith("OTHERS_")
        }
        require(exposed.isEmpty()) {
            "Secret file must not be readable by group or others"
        }
    }
}
