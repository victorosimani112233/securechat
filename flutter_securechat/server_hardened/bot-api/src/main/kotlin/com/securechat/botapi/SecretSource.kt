package com.securechat.botapi

import java.nio.charset.StandardCharsets
import java.nio.file.Files
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
        val size = Files.size(path)
        require(size in 1..MAX_SECRET_BYTES.toLong()) {
            "Secret file has an invalid size"
        }
        return Files.readString(path, StandardCharsets.UTF_8)
    }
}
