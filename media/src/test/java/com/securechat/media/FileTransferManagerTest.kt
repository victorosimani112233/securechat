package com.securechat.media

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import com.securechat.network.SignalMessage
import com.securechat.network.SignalingClient
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.slot
import io.mockk.verify
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.File
import java.util.Base64

/**
 * FileTransferManager sinifinin unit testleri.
 *
 * Dosya gonderme, alma, boyut kontrolu, dosya adi cozumleme
 * ve hata durumlari test edilir.
 */
class FileTransferManagerTest {

    private lateinit var fileTransferManager: FileTransferManager
    private lateinit var context: Context
    private lateinit var contentResolver: ContentResolver
    private lateinit var signalingClient: SignalingClient

    private val testSenderId = "user-123"
    private val testRecipientId = "peer-456"

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        contentResolver = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)

        every { context.contentResolver } returns contentResolver

        fileTransferManager = FileTransferManager(context, signalingClient)
    }

    // ---- sendFile testleri ----

    @Test
    fun `sendFile basarili sekilde dosya gonderir`() = runTest {
        // Arrange
        val testData = "Test dosya icerigi".toByteArray()
        val uri = mockk<Uri>()
        val inputStream = ByteArrayInputStream(testData)

        every { contentResolver.getType(uri) } returns "text/plain"
        every { contentResolver.openInputStream(uri) } returns inputStream
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("test.txt")
        every { signalingClient.sendSignal(any()) } returns true

        // Act
        val result = fileTransferManager.sendFile(testSenderId, testRecipientId, uri)

        // Assert
        assertTrue(result is FileTransferResult.Success)
        val success = result as FileTransferResult.Success
        assertEquals("test.txt", success.fileName)
        assertEquals("text/plain", success.mimeType)
        assertEquals(testData.size.toLong(), success.fileSize)
    }

    @Test
    fun `sendFile dosya boyutu limitini asinca hata doner`() = runTest {
        // Arrange — 6MB dosya (limit 5MB)
        val largeData = ByteArray(6 * 1024 * 1024)
        val uri = mockk<Uri>()
        val inputStream = ByteArrayInputStream(largeData)

        every { contentResolver.getType(uri) } returns "application/pdf"
        every { contentResolver.openInputStream(uri) } returns inputStream
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("buyuk.pdf")

        // Act
        val result = fileTransferManager.sendFile(testSenderId, testRecipientId, uri)

        // Assert
        assertTrue(result is FileTransferResult.Error)
        val error = result as FileTransferResult.Error
        assertTrue(error.message.contains("buyuk"))
    }

    @Test
    fun `sendFile dosya okunamazsa hata doner`() = runTest {
        // Arrange
        val uri = mockk<Uri>()
        every { contentResolver.getType(uri) } returns "image/jpeg"
        every { contentResolver.openInputStream(uri) } returns null
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("foto.jpg")

        // Act
        val result = fileTransferManager.sendFile(testSenderId, testRecipientId, uri)

        // Assert
        assertTrue(result is FileTransferResult.Error)
        val error = result as FileTransferResult.Error
        assertTrue(error.message.contains("okunamadi"))
    }

    @Test
    fun `sendFile WebSocket gonderimi basarisiz olunca hata doner`() = runTest {
        // Arrange
        val testData = "Test".toByteArray()
        val uri = mockk<Uri>()
        val inputStream = ByteArrayInputStream(testData)

        every { contentResolver.getType(uri) } returns "text/plain"
        every { contentResolver.openInputStream(uri) } returns inputStream
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("test.txt")
        every { signalingClient.sendSignal(any()) } returns false

        // Act
        val result = fileTransferManager.sendFile(testSenderId, testRecipientId, uri)

        // Assert
        assertTrue(result is FileTransferResult.Error)
        val error = result as FileTransferResult.Error
        assertTrue(error.message.contains("gonderilemedi"))
    }

    @Test
    fun `sendFile dogru SignalMessage olusturur`() = runTest {
        // Arrange
        val testData = "Merhaba Dunya".toByteArray()
        val uri = mockk<Uri>()
        val inputStream = ByteArrayInputStream(testData)
        val signalSlot = slot<SignalMessage>()

        every { contentResolver.getType(uri) } returns "text/plain"
        every { contentResolver.openInputStream(uri) } returns inputStream
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("merhaba.txt")
        every { signalingClient.sendSignal(capture(signalSlot)) } returns true

        // Act
        fileTransferManager.sendFile(testSenderId, testRecipientId, uri)

        // Assert
        val signal = signalSlot.captured
        assertTrue(signal is SignalMessage.FileTransfer)
        val fileTransfer = signal as SignalMessage.FileTransfer
        assertEquals(testSenderId, fileTransfer.senderId)
        assertEquals(testRecipientId, fileTransfer.recipientId)
        assertEquals("merhaba.txt", fileTransfer.fileName)
        assertEquals("text/plain", fileTransfer.mimeType)
        assertEquals(testData.size.toLong(), fileTransfer.fileSize)

        // Base64 verisini dogrula
        val decoded = Base64.getDecoder().decode(fileTransfer.data)
        assertEquals("Merhaba Dunya", String(decoded))
    }

    @Test
    fun `sendFile grup mesajinda tum uyelere gonderir`() = runTest {
        // Arrange
        val testData = "Grup dosyasi".toByteArray()
        val uri = mockk<Uri>()
        val inputStream = ByteArrayInputStream(testData)
        val groupMembers = listOf(testSenderId, "member-2", "member-3")

        every { contentResolver.getType(uri) } returns "text/plain"
        every { contentResolver.openInputStream(uri) } returns inputStream
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("grup.txt")
        every { signalingClient.sendSignal(any()) } returns true

        // Act
        val result = fileTransferManager.sendFile(
            localUserId = testSenderId,
            recipientId = "group-1",
            uri = uri,
            isGroup = true,
            groupMembers = groupMembers
        )

        // Assert
        assertTrue(result is FileTransferResult.Success)
        // Kendisinni haric tutarak 2 kez gonderilmeli
        verify(exactly = 2) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `sendFile grup mesajinda kendine gondermez`() = runTest {
        // Arrange
        val testData = "Test".toByteArray()
        val uri = mockk<Uri>()
        val inputStream = ByteArrayInputStream(testData)
        val signals = mutableListOf<SignalMessage>()

        every { contentResolver.getType(uri) } returns "text/plain"
        every { contentResolver.openInputStream(uri) } returns inputStream
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("test.txt")
        every { signalingClient.sendSignal(capture(signals)) } returns true

        // Act
        fileTransferManager.sendFile(
            localUserId = testSenderId,
            recipientId = "group-1",
            uri = uri,
            isGroup = true,
            groupMembers = listOf(testSenderId, "member-2")
        )

        // Assert — sadece member-2'ye gonderilmeli
        assertEquals(1, signals.size)
        val sent = signals.first() as SignalMessage.FileTransfer
        assertEquals("member-2", sent.recipientId)
    }

    // ---- saveReceivedFile testleri ----
    // NOT: Uri.fromFile() JVM unit testlerinde null doner (Android framework),
    // bu yuzden dosya kaydini received_files dizini uzerinden dogrudan dogruluyoruz.

    @Test
    fun `saveReceivedFile dosyayi diske yazar`() {
        // Arrange
        val originalContent = "Kaydedilecek icerik"
        val encoded = Base64.getEncoder().encodeToString(originalContent.toByteArray())
        val tempDir = createTempDir("test_files")

        every { context.filesDir } returns tempDir

        // Act
        fileTransferManager.saveReceivedFile("test.txt", encoded)

        // Assert — received_files altinda dosya olusturulmus olmali
        val receivedDir = File(tempDir, "received_files")
        assertTrue("received_files dizini olmali", receivedDir.exists())
        val files = receivedDir.listFiles() ?: emptyArray()
        assertTrue("En az bir dosya olmali", files.isNotEmpty())
        val savedFile = files.first()
        assertTrue("Dosya adi 'test.txt' icermeli", savedFile.name.contains("test.txt"))
        assertEquals(originalContent, savedFile.readText())

        // Temizlik
        tempDir.deleteRecursively()
    }

    @Test
    fun `saveReceivedFile gecersiz base64 verisi icin null doner`() {
        // Arrange
        val tempDir = createTempDir("test_files")
        every { context.filesDir } returns tempDir

        // Act
        val uri = fileTransferManager.saveReceivedFile("test.txt", "gecersiz-base64!!!")

        // Assert
        assertNull(uri)

        // Temizlik
        tempDir.deleteRecursively()
    }

    @Test
    fun `saveReceivedFile dosya adini sanitize eder`() {
        // Arrange
        val encoded = Base64.getEncoder().encodeToString("test".toByteArray())
        val tempDir = createTempDir("test_files")

        every { context.filesDir } returns tempDir

        // Act — ozel karakterli dosya adi (path traversal denemesi)
        fileTransferManager.saveReceivedFile("../../../etc/passwd", encoded)

        // Assert — dosya received_files icinde olmali, ust dizinde degil
        val receivedDir = File(tempDir, "received_files")
        assertTrue(receivedDir.exists())
        val files = receivedDir.listFiles() ?: emptyArray()
        assertTrue(files.isNotEmpty())
        // Dosya adi sanitize edilmis olmali — / karakterleri _ ile degistirilmis
        val savedFile = files.first()
        assertTrue("Dosya adi '/' icermemeli", !savedFile.name.contains("/"))

        // Temizlik
        tempDir.deleteRecursively()
    }

    // ---- getFileName testleri ----

    @Test
    fun `getFileName ContentResolver'dan dosya adini okur`() {
        // Arrange
        val uri = mockk<Uri>()
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithName("belge.pdf")

        // Act
        val fileName = fileTransferManager.getFileName(uri)

        // Assert
        assertEquals("belge.pdf", fileName)
    }

    @Test
    fun `getFileName cursor bossa URI segmentini doner`() {
        // Arrange
        val uri = mockk<Uri>()
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns null
        every { uri.lastPathSegment } returns "fallback.zip"

        // Act
        val fileName = fileTransferManager.getFileName(uri)

        // Assert
        assertEquals("fallback.zip", fileName)
    }

    // ---- getMimeType testleri ----

    @Test
    fun `getMimeType ContentResolver'dan MIME tipini okur`() {
        // Arrange
        val uri = mockk<Uri>()
        every { contentResolver.getType(uri) } returns "image/png"

        // Act
        val mimeType = fileTransferManager.getMimeType(uri)

        // Assert
        assertEquals("image/png", mimeType)
    }

    @Test
    fun `getMimeType bilinmeyen tip icin fallback doner`() {
        // Arrange
        val uri = mockk<Uri>()
        every { contentResolver.getType(uri) } returns null

        // Act
        val mimeType = fileTransferManager.getMimeType(uri)

        // Assert
        assertEquals("application/octet-stream", mimeType)
    }

    // ---- getFileSize testleri ----

    @Test
    fun `getFileSize ContentResolver'dan boyut okur`() {
        // Arrange
        val uri = mockk<Uri>()
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns mockCursorWithSize(12345L)

        // Act
        val size = fileTransferManager.getFileSize(uri)

        // Assert
        assertEquals(12345L, size)
    }

    @Test
    fun `getFileSize cursor bossa null doner`() {
        // Arrange
        val uri = mockk<Uri>()
        every { contentResolver.query(uri, any(), any(), any(), any()) } returns null

        // Act
        val size = fileTransferManager.getFileSize(uri)

        // Assert
        assertNull(size)
    }

    // ---- MAX_FILE_SIZE sabiti ----

    @Test
    fun `MAX_FILE_SIZE 5MB olarak tanimli`() {
        assertEquals(5L * 1024 * 1024, FileTransferManager.MAX_FILE_SIZE)
    }

    // ---- Yardimci metodlar ----

    private fun mockCursorWithName(name: String): Cursor {
        val cursor = mockk<Cursor>(relaxed = true)
        every { cursor.moveToFirst() } returns true
        every { cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME) } returns 0
        every { cursor.getString(0) } returns name
        every { cursor.close() } returns Unit
        return cursor
    }

    private fun mockCursorWithSize(size: Long): Cursor {
        val cursor = mockk<Cursor>(relaxed = true)
        every { cursor.moveToFirst() } returns true
        every { cursor.getColumnIndex(OpenableColumns.SIZE) } returns 0
        every { cursor.getLong(0) } returns size
        every { cursor.close() } returns Unit
        return cursor
    }
}
