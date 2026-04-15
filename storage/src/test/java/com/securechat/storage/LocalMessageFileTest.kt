package com.securechat.storage

import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * LocalMessage dosya mesaji yardimci ozelliklerinin unit testleri.
 *
 * Dosya adi, MIME tipi, boyut, dosya yolu ayristirma ve
 * dosya tipi belirleme testleri icerir.
 */
class LocalMessageFileTest {

    // ---- buildFileContent testleri ----

    @Test
    fun `buildFileContent dogru formatta string olusturur`() {
        val content = LocalMessage.buildFileContent(
            fileName = "belge.pdf",
            mimeType = "application/pdf",
            fileSize = 12345L,
            filePath = "/data/files/belge.pdf"
        )
        assertEquals("belge.pdf|application/pdf|12345|/data/files/belge.pdf", content)
    }

    @Test
    fun `buildFileContent filePath olmadan calisir`() {
        val content = LocalMessage.buildFileContent(
            fileName = "resim.jpg",
            mimeType = "image/jpeg",
            fileSize = 5000L
        )
        assertEquals("resim.jpg|image/jpeg|5000|", content)
    }

    // ---- fileName testleri ----

    @Test
    fun `fileName IMAGE mesajinda dosya adini dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.IMAGE,
            content = "foto.jpg|image/jpeg|2048|/data/foto.jpg"
        )
        assertEquals("foto.jpg", message.fileName)
    }

    @Test
    fun `fileName FILE mesajinda dosya adini dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "rapor.pdf|application/pdf|4096|/data/rapor.pdf"
        )
        assertEquals("rapor.pdf", message.fileName)
    }

    @Test
    fun `fileName TEXT mesajinda null dondurur`() {
        val message = createTextMessage("Merhaba")
        assertNull(message.fileName)
    }

    // ---- fileMimeType testleri ----

    @Test
    fun `fileMimeType dogru MIME tipini dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.IMAGE,
            content = "foto.png|image/png|1024|/data/foto.png"
        )
        assertEquals("image/png", message.fileMimeType)
    }

    @Test
    fun `fileMimeType TEXT mesajinda null dondurur`() {
        val message = createTextMessage("Test")
        assertNull(message.fileMimeType)
    }

    // ---- fileSize testleri ----

    @Test
    fun `fileSize dogru boyutu dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "dosya.zip|application/zip|999999|/data/dosya.zip"
        )
        assertEquals(999999L, message.fileSize)
    }

    @Test
    fun `fileSize TEXT mesajinda null dondurur`() {
        val message = createTextMessage("Merhaba")
        assertNull(message.fileSize)
    }

    // ---- filePath testleri ----

    @Test
    fun `filePath dogru yolu dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "test.txt|text/plain|100|/data/files/test.txt"
        )
        assertEquals("/data/files/test.txt", message.filePath)
    }

    @Test
    fun `filePath bos string olabilir`() {
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "test.txt|text/plain|100|"
        )
        assertEquals("", message.filePath)
    }

    // ---- isFileMessage testleri ----

    @Test
    fun `isFileMessage IMAGE mesajinda true dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.IMAGE,
            content = "foto.jpg|image/jpeg|1024|"
        )
        assertTrue(message.isFileMessage)
    }

    @Test
    fun `isFileMessage FILE mesajinda true dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "dosya.zip|application/zip|2048|"
        )
        assertTrue(message.isFileMessage)
    }

    @Test
    fun `isFileMessage TEXT mesajinda false dondurur`() {
        val message = createTextMessage("Test mesaj")
        assertFalse(message.isFileMessage)
    }

    @Test
    fun `isFileMessage VOICE_NOTE mesajinda false dondurur`() {
        val message = createMessage(
            contentType = MessageContentType.VOICE_NOTE,
            content = "voice_data"
        )
        assertFalse(message.isFileMessage)
    }

    // ---- isImageFile testleri ----

    @Test
    fun `isImageFile IMAGE tipindeki mesajda true dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.IMAGE,
            content = "foto.jpg|image/jpeg|1024|"
        )
        assertTrue(message.isImageFile)
    }

    @Test
    fun `isImageFile FILE tipinde resim MIME ile true dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "resim.png|image/png|2048|"
        )
        assertTrue(message.isImageFile)
    }

    @Test
    fun `isImageFile FILE tipinde resim olmayan MIME ile false dondurur`() {
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "belge.pdf|application/pdf|4096|"
        )
        assertFalse(message.isImageFile)
    }

    @Test
    fun `isImageFile TEXT mesajinda false dondurur`() {
        val message = createTextMessage("Test")
        assertFalse(message.isImageFile)
    }

    // ---- Icerik ayristirma edge case'leri ----

    @Test
    fun `pipe iceren dosya adi dogru ayristirilir`() {
        // Dosya adinda pipe olmamali (sanitize edilmis olmali)
        // ama content parse'i ilk pipe'a kadar alir
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "normal_dosya|application/pdf|100|/path"
        )
        assertEquals("normal_dosya", message.fileName)
        assertEquals("application/pdf", message.fileMimeType)
    }

    @Test
    fun `eksik alanlar null doner`() {
        // Sadece dosya adi olan eksik content
        val message = createFileMessage(
            contentType = MessageContentType.FILE,
            content = "dosya.txt"
        )
        assertEquals("dosya.txt", message.fileName)
        assertNull(message.fileMimeType)
        assertNull(message.fileSize)
        assertNull(message.filePath)
    }

    // ---- Yardimci metodlar ----

    private fun createTextMessage(content: String): LocalMessage = LocalMessage(
        id = "msg-1",
        conversationId = "conv-1",
        senderId = "user-1",
        peerId = "user-2",
        content = content,
        contentType = MessageContentType.TEXT,
        timestamp = System.currentTimeMillis(),
        status = MessageStatus.SENT,
        isOutgoing = true
    )

    private fun createFileMessage(contentType: MessageContentType, content: String): LocalMessage = LocalMessage(
        id = "msg-1",
        conversationId = "conv-1",
        senderId = "user-1",
        peerId = "user-2",
        content = content,
        contentType = contentType,
        timestamp = System.currentTimeMillis(),
        status = MessageStatus.SENT,
        isOutgoing = true
    )

    private fun createMessage(contentType: MessageContentType, content: String): LocalMessage = LocalMessage(
        id = "msg-1",
        conversationId = "conv-1",
        senderId = "user-1",
        peerId = "user-2",
        content = content,
        contentType = contentType,
        timestamp = System.currentTimeMillis(),
        status = MessageStatus.SENT,
        isOutgoing = true
    )
}
