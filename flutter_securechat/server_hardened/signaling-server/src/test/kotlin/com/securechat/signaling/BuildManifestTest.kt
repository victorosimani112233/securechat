package com.securechat.signaling

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Canli uctaki artefaktin hangi commit ve hangi migration hedefiyle
 * calistigi kanitlanabilmelidir; aksi halde incelenen guvenlik
 * garantilerinin production'da gecerli oldugu soylenemez.
 */
class BuildManifestTest {

    @Test
    fun `the manifest is generated into the artefact`() {
        // Build sirasinda uretilir; kaynak agacinda elle tutulmaz.
        assertTrue(
            BuildManifest::class.java.getResource("/build-info.properties") != null,
            "build-info.properties artefakta gomulmeli",
        )
    }

    @Test
    fun `the migration target follows the migration folder`() {
        val highest = BuildManifest::class.java
            .getResource("/db/migration")
            ?.let { java.io.File(it.toURI()) }
            ?.listFiles { file -> file.name.startsWith("V") && file.name.endsWith(".sql") }
            ?.mapNotNull { Regex("^V(\\d+)__").find(it.name)?.groupValues?.get(1)?.toIntOrNull() }
            ?.maxOrNull()
        if (highest != null) {
            assertEquals("V$highest", BuildManifest.migrationTarget)
        }
    }

    @Test
    fun `the manifest carries no secret material`() {
        val values = BuildManifest.asMap()
        assertEquals(setOf("commit", "builtAt", "migrationTarget"), values.keys)
        for (value in values.values) {
            assertTrue(value.length < 128, "manifest alanlari kisa ve opaque olmali")
        }
    }

    @Test
    fun `production refuses an artefact without provenance`() {
        val production = mapOf("PRIVACY_PRODUCTION_MODE" to "true")
        if (BuildManifest.commit == "unknown" || BuildManifest.migrationTarget == "unknown") {
            assertThrows(IllegalArgumentException::class.java) {
                BuildManifest.validate(production)
            }
        } else {
            BuildManifest.validate(production)
        }
        // Production disi calistirmalar engellenmez.
        BuildManifest.validate(emptyMap())
    }
}
