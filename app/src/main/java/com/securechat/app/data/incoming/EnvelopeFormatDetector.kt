package com.securechat.app.data.incoming

import com.securechat.crypto.model.EnvelopeType

/**
 * Gelen mesaj envelope'unun format tipi.
 *
 * Format tablosu (hibrit donem):
 * - "E2EE:v1:<TYPE>:<regId>:<b64ciphertext>"  → DirectE2EE   (Faz 0)
 * - "GROUPSK:v1:<groupId>:<groupName>:<b64>"  → GroupV1      (Faz 5)
 * - "SKDM:<groupId>:<b64skdm>"                → SKDM         (Faz 4 — 1:1 envelope icinde)
 * - "GROUP:<groupId>[:<groupName>]:<icerik>"  → GroupLegacy  (eski plaintext grup, 30 gun)
 * - hicbiri                                    → DirectLegacy (eski plaintext 1:1, 30 gun)
 */
sealed class EnvelopeFormat {
    data class DirectE2EE(
        val type: EnvelopeType,
        val regId: Int,
        val ciphertextB64: String
    ) : EnvelopeFormat()

    data class GroupV1(
        val groupId: String,
        val groupName: String,
        val ciphertextB64: String
    ) : EnvelopeFormat()

    data class Skdm(
        val groupId: String,
        val skdmB64: String
    ) : EnvelopeFormat()

    data class GroupLegacy(
        val groupId: String,
        val groupName: String?,
        val payload: String
    ) : EnvelopeFormat()

    data class DirectLegacy(val payload: String) : EnvelopeFormat()

    object Unknown : EnvelopeFormat()
}

object EnvelopeFormatDetector {

    /** Envelope string'ini parse edip format tipini dondurur. Hata varsa Unknown. */
    fun detect(envelope: String): EnvelopeFormat = try {
        when {
            envelope.startsWith("E2EE:v1:") -> parseDirectE2EE(envelope)
            envelope.startsWith("GROUPSK:v1:") -> parseGroupV1(envelope)
            envelope.startsWith("SKDM:") -> parseSkdm(envelope)
            envelope.startsWith("GROUP:") -> parseGroupLegacy(envelope)
            else -> EnvelopeFormat.DirectLegacy(envelope)
        }
    } catch (e: Exception) {
        EnvelopeFormat.Unknown
    }

    private fun parseDirectE2EE(envelope: String): EnvelopeFormat {
        // E2EE:v1:<TYPE>:<regId>:<b64>
        val rest = envelope.removePrefix("E2EE:v1:")
        val parts = rest.split(":", limit = 3)
        if (parts.size < 3) return EnvelopeFormat.Unknown
        val type = EnvelopeType.valueOf(parts[0])
        val regId = parts[1].toInt()
        return EnvelopeFormat.DirectE2EE(type, regId, parts[2])
    }

    private fun parseGroupV1(envelope: String): EnvelopeFormat {
        // GROUPSK:v1:<groupId>:<groupName>:<b64>
        val rest = envelope.removePrefix("GROUPSK:v1:")
        val parts = rest.split(":", limit = 3)
        if (parts.size < 3) return EnvelopeFormat.Unknown
        return EnvelopeFormat.GroupV1(parts[0], parts[1], parts[2])
    }

    private fun parseSkdm(envelope: String): EnvelopeFormat {
        // SKDM:<groupId>:<b64skdm>
        val rest = envelope.removePrefix("SKDM:")
        val parts = rest.split(":", limit = 2)
        if (parts.size < 2) return EnvelopeFormat.Unknown
        return EnvelopeFormat.Skdm(parts[0], parts[1])
    }

    private fun parseGroupLegacy(envelope: String): EnvelopeFormat {
        // GROUP:<groupId>:<groupName>:<payload>   (4 parca)
        // GROUP:<groupId>:<payload>               (3 parca, eski)
        val parts = envelope.split(":", limit = 4)
        return when {
            parts.size >= 4 -> EnvelopeFormat.GroupLegacy(parts[1], parts[2], parts[3])
            parts.size >= 3 -> EnvelopeFormat.GroupLegacy(parts[1], null, parts[2])
            else -> EnvelopeFormat.Unknown
        }
    }
}
