package com.securechat.signaling

import java.io.File
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Yanit govdeleri serialize edilebilir olmalidir.
 *
 * `call.respond(mapOf("a" to "x", "b" to 1))` `Map<String, Any>` uretir;
 * kotlinx-serialization bunun icin serializer bulamaz ve endpoint calisma
 * zamaninda 500 doner. Hata yollarinda bu, istemcinin dogru durum kodunu
 * hic gormemesi demektir — nitekim bot rate-limit yaniti tam bu yuzden
 * bozuktu.
 */
class ResponseSerializationTest {

    private val pairPattern = Regex(""""[^"]*"\s+to\s+([^,\n]+)""")

    private fun sources(): List<File> =
        File("src/main/kotlin/com/securechat/signaling").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .toList()

    @Test
    fun `no route responds with a heterogeneous map literal`() {
        val offenders = mutableListOf<String>()
        for (file in sources()) {
            val text = file.readText()
            Regex("""respond\((?:[^,()]*,\s*)?mapOf\(([^()]*)\)\)""", RegexOption.DOT_MATCHES_ALL)
                .findAll(text)
                .forEach { match ->
                    val values = pairPattern.findAll(match.groupValues[1])
                        .map { it.groupValues[1].trim() }
                        .toList()
                    if (values.size < 2) return@forEach
                    val allStrings = values.all { value ->
                        value.startsWith("\"") ||
                            value.endsWith(".toString()") ||
                            value.endsWith(".name") ||
                            value.endsWith("orEmpty()")
                    }
                    if (!allStrings) {
                        val line = text.take(match.range.first).count { it == '\n' } + 1
                        offenders += "${file.name}:$line ${values.joinToString()}"
                    }
                }
        }

        assertTrue(offenders.isEmpty(), "serialize edilemeyen yanit: $offenders")
    }
}
