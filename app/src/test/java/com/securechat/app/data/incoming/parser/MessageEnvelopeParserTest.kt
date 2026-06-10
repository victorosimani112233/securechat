package com.securechat.app.data.incoming.parser

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.model.MessageContentType
import org.junit.Test

/**
 * Pure parser unit testleri — Faz 10 extract dogrulamasi.
 * Mocking yok, side effect yok.
 */
class MessageEnvelopeParserTest {

    @Test
    fun `plain text — prefix yok`() {
        val r = MessageEnvelopeParser.parse("merhaba dunya")
        assertThat(r.messageId).isNull()
        assertThat(r.replyToId).isNull()
        assertThat(r.content).isEqualTo("merhaba dunya")
        assertThat(r.contentType).isEqualTo(MessageContentType.TEXT)
        assertThat(r.isViewOnce).isFalse()
        assertThat(r.absoluteExpiresAt).isNull()
        assertThat(r.pollVote).isNull()
    }

    @Test
    fun `MSGID prefix`() {
        val r = MessageEnvelopeParser.parse("MSGID:abc-123:icerik")
        assertThat(r.messageId).isEqualTo("abc-123")
        assertThat(r.content).isEqualTo("icerik")
    }

    @Test
    fun `MSGID + REPLY chain`() {
        val r = MessageEnvelopeParser.parse("MSGID:msg-1:REPLY:reply-target:cevap")
        assertThat(r.messageId).isEqualTo("msg-1")
        assertThat(r.replyToId).isEqualTo("reply-target")
        assertThat(r.content).isEqualTo("cevap")
    }

    @Test
    fun `MSGID + EXP — sureli mesaj`() {
        val r = MessageEnvelopeParser.parse("MSGID:m1:EXP:1700000000000:beni 30sn sonra sil")
        assertThat(r.messageId).isEqualTo("m1")
        assertThat(r.absoluteExpiresAt).isEqualTo(1700000000000L)
        assertThat(r.content).isEqualTo("beni 30sn sonra sil")
    }

    @Test
    fun `MSGID + VIEWONCE — tek gosterimlik metin`() {
        val r = MessageEnvelopeParser.parse("MSGID:vo-1:VIEWONCE:gizli")
        assertThat(r.isViewOnce).isTrue()
        assertThat(r.content).isEqualTo("gizli")
    }

    @Test
    fun `MSGID + POLL — anket`() {
        val r = MessageEnvelopeParser.parse("""MSGID:p1:POLL:{"question":"Hangisi?"}""")
        assertThat(r.contentType).isEqualTo(MessageContentType.POLL)
        assertThat(r.content).isEqualTo("""{"question":"Hangisi?"}""")
    }

    @Test
    fun `POLLVOTE — yeni mesaj olarak kaydedilmez`() {
        val r = MessageEnvelopeParser.parse("MSGID:vote-msg:POLLVOTE:poll-target:2")
        assertThat(r.pollVote).isNotNull()
        assertThat(r.pollVote!!.pollMessageId).isEqualTo("poll-target")
        assertThat(r.pollVote!!.optionIndex).isEqualTo(2)
        assertThat(r.content).isEmpty()
    }

    @Test
    fun `tum prefix chain — siralama dogru calismali`() {
        val r = MessageEnvelopeParser.parse(
            "MSGID:m1:REPLY:r1:EXP:1700000000000:VIEWONCE:cok gizli kisa mesaj"
        )
        assertThat(r.messageId).isEqualTo("m1")
        assertThat(r.replyToId).isEqualTo("r1")
        assertThat(r.absoluteExpiresAt).isEqualTo(1700000000000L)
        assertThat(r.isViewOnce).isTrue()
        assertThat(r.content).isEqualTo("cok gizli kisa mesaj")
    }

    @Test
    fun `bozuk MSGID prefix — fallback plain`() {
        // ":" eksik
        val r = MessageEnvelopeParser.parse("MSGID broken icerik")
        assertThat(r.messageId).isNull()
        assertThat(r.content).isEqualTo("MSGID broken icerik")
    }

    @Test
    fun `EXP icindeki sayi parse edilemiyorsa null`() {
        val r = MessageEnvelopeParser.parse("MSGID:m1:EXP:notANumber:icerik")
        assertThat(r.absoluteExpiresAt).isNull()
    }

    @Test
    fun `parseMessageId helper — geriye uyumlu`() {
        val (id, content) = MessageEnvelopeParser.parseMessageId("MSGID:abc:icerik")
        assertThat(id).isEqualTo("abc")
        assertThat(content).isEqualTo("icerik")
    }

    // --- MENTION prefix (Feature 1, Sprint 9) ---

    @Test
    fun `MENTION — tek kullanici`() {
        val r = MessageEnvelopeParser.parse("MSGID:m1:MENTION:uid1:Merhaba @Ali")
        assertThat(r.mentionedUserIds).containsExactly("uid1")
        assertThat(r.content).isEqualTo("Merhaba @Ali")
    }

    @Test
    fun `MENTION — coklu kullanici`() {
        val r = MessageEnvelopeParser.parse("MSGID:m1:MENTION:uid1,uid2,uid3:Merhaba @Ali @Veli @Can")
        assertThat(r.mentionedUserIds).containsExactly("uid1", "uid2", "uid3").inOrder()
        assertThat(r.content).isEqualTo("Merhaba @Ali @Veli @Can")
    }

    @Test
    fun `MENTION — VIEWONCE'tan SONRA, POLL'den ONCE`() {
        val r = MessageEnvelopeParser.parse(
            "MSGID:m1:REPLY:r1:EXP:1700000000000:VIEWONCE:MENTION:uidA:gizli mention"
        )
        assertThat(r.messageId).isEqualTo("m1")
        assertThat(r.replyToId).isEqualTo("r1")
        assertThat(r.absoluteExpiresAt).isEqualTo(1700000000000L)
        assertThat(r.isViewOnce).isTrue()
        assertThat(r.mentionedUserIds).containsExactly("uidA")
        assertThat(r.content).isEqualTo("gizli mention")
    }

    @Test
    fun `MENTION — POLL ile kombine`() {
        val r = MessageEnvelopeParser.parse(
            """MSGID:p1:MENTION:uidX:POLL:{"question":"Ne dersin?"}"""
        )
        assertThat(r.mentionedUserIds).containsExactly("uidX")
        assertThat(r.contentType).isEqualTo(MessageContentType.POLL)
        assertThat(r.content).isEqualTo("""{"question":"Ne dersin?"}""")
    }

    @Test
    fun `MENTION yoksa bos liste`() {
        val r = MessageEnvelopeParser.parse("MSGID:m1:Merhaba grup")
        assertThat(r.mentionedUserIds).isEmpty()
    }

    @Test
    fun `MENTION — bos csv guvenli`() {
        // Bozuk gonderici "MENTION::" gonderirse parser bos liste dondurmeli, content kaymamali
        val r = MessageEnvelopeParser.parse("MSGID:m1:MENTION::icerik")
        assertThat(r.mentionedUserIds).isEmpty()
        assertThat(r.content).isEqualTo("icerik")
    }
}
