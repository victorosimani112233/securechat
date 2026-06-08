package com.securechat.app.data.incoming.parser

import com.securechat.storage.model.MessageContentType

/**
 * Mesaj envelope prefix parser — pure logic, side effect yok.
 *
 * Wire format: "MSGID:<id>:REPLY:<rid>:EXP:<absMs>:VIEWONCE:POLL:icerik"
 * Tum prefix'ler opsiyonel; bulunan sirayla parse edilir.
 *
 * Sira ZORUNLU:
 *   1. MSGID  — mesaj id (delivery receipt + view-once edit icin)
 *   2. REPLY  — yanit verilen mesaj id (UI reply preview icin)
 *   3. EXP    — mutlak expiresAt ms (sureli mesaj — alici lokal duration'a fallback yapmasin)
 *   4. VIEWONCE — tek gosterimlik metin bayragi (icerik degeri tasimaz, sadece flag)
 *   5. POLLVOTE  — anket oy guncellemesi (yeni mesaj kaydedilmez)
 *   6. POLL   — anket mesaji (alici JSON parse eder)
 *   geriye kalan -> content (TEXT)
 *
 * POLL en sonda olmali cunku parser POLL gorunce kalan her seyi content kabul eder.
 */
data class ParsedEnvelope(
    val messageId: String?,
    val replyToId: String?,
    val content: String,
    val contentType: MessageContentType = MessageContentType.TEXT,
    val pollVote: PollVoteRef? = null,
    /** EXP prefix'ten alinan mutlak expiresAt (ms). Yoksa null. */
    val absoluteExpiresAt: Long? = null,
    /** VIEWONCE prefix bayragi — tek gosterimlik metin mesaji. */
    val isViewOnce: Boolean = false
)

/** Anket oy guncellemesi referansi — alici tarafta uygulanir. */
data class PollVoteRef(val pollMessageId: String, val optionIndex: Int)

object MessageEnvelopeParser {

    /**
     * Envelope string'ini parse eder. Test-friendly: pure function, mocking gereksiz.
     */
    fun parse(content: String): ParsedEnvelope {
        var remaining = content
        var messageId: String? = null
        var replyToId: String? = null
        var absoluteExpiresAt: Long? = null
        var isViewOnce = false

        // MSGID prefix
        if (remaining.startsWith("MSGID:")) {
            val firstColon = remaining.indexOf(':')
            val secondColon = remaining.indexOf(':', firstColon + 1)
            if (secondColon > firstColon) {
                messageId = remaining.substring(firstColon + 1, secondColon)
                remaining = remaining.substring(secondColon + 1)
            }
        }

        // REPLY prefix
        if (remaining.startsWith("REPLY:")) {
            val firstColon = remaining.indexOf(':')
            val secondColon = remaining.indexOf(':', firstColon + 1)
            if (secondColon > firstColon) {
                replyToId = remaining.substring(firstColon + 1, secondColon)
                remaining = remaining.substring(secondColon + 1)
            }
        }

        // EXP prefix — sureli mesaj icin mutlak expiresAt (ms). REPLY'dan sonra, POLL'den once.
        if (remaining.startsWith("EXP:")) {
            val firstColon = remaining.indexOf(':')
            val secondColon = remaining.indexOf(':', firstColon + 1)
            if (secondColon > firstColon) {
                absoluteExpiresAt = remaining.substring(firstColon + 1, secondColon).toLongOrNull()
                remaining = remaining.substring(secondColon + 1)
            }
        }

        // VIEWONCE prefix — tek gosterimlik metin mesaji bayragi (icerik degeri tasimaz).
        // POLL'den ONCE parse edilir, cunku POLL gorunce parser kalan her seyi icerik kabul eder.
        if (remaining.startsWith("VIEWONCE:")) {
            isViewOnce = true
            remaining = remaining.removePrefix("VIEWONCE:")
        }

        // POLLVOTE: prefix — anket oy guncellemesi (yeni mesaj olarak kaydedilmez,
        // mevcut anket mesajinin votes alanini gunceller)
        // Format: POLLVOTE:<pollMsgId>:<optionIndex>
        if (remaining.startsWith("POLLVOTE:")) {
            val parts = remaining.removePrefix("POLLVOTE:").split(":", limit = 2)
            if (parts.size == 2) {
                val pollMsgId = parts[0]
                val optionIdx = parts[1].toIntOrNull()
                if (optionIdx != null) {
                    return ParsedEnvelope(
                        messageId = messageId,
                        replyToId = null,
                        content = "",
                        contentType = MessageContentType.TEXT,
                        pollVote = PollVoteRef(pollMsgId, optionIdx),
                        absoluteExpiresAt = absoluteExpiresAt,
                        isViewOnce = isViewOnce
                    )
                }
            }
        }

        // POLL: prefix — anket mesaji
        if (remaining.startsWith("POLL:")) {
            return ParsedEnvelope(
                messageId = messageId,
                replyToId = replyToId,
                content = remaining.removePrefix("POLL:"),
                contentType = MessageContentType.POLL,
                pollVote = null,
                absoluteExpiresAt = absoluteExpiresAt,
                isViewOnce = isViewOnce
            )
        }

        return ParsedEnvelope(
            messageId = messageId,
            replyToId = replyToId,
            content = remaining,
            absoluteExpiresAt = absoluteExpiresAt,
            isViewOnce = isViewOnce
        )
    }

    /** Sadece messageId + geriye kalan content — eski parseMessageId fonksiyonu icin. */
    fun parseMessageId(content: String): Pair<String?, String> {
        val parsed = parse(content)
        return Pair(parsed.messageId, parsed.content)
    }
}
