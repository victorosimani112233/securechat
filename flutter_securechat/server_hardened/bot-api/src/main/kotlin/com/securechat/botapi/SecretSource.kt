package com.securechat.botapi

import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path

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
        return Files.readString(path, StandardCharsets.UTF_8)
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
