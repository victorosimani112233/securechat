package com.securechat.app.data

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.dao.MessageDao
import com.securechat.storage.entity.ConversationEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * ChatStorageAnalyzer birim testleri.
 *
 * Gercek dosya sistemi (TemporaryFolder) ile yapilir — sahte path'lar ile
 * disk boyutu fallback dogru calistigi ve buyukten kucuge siralama islerligi
 * dogrulanir.
 */
class ChatStorageAnalyzerTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val messageDao: MessageDao = mockk(relaxed = true)
    private val conversationDao: ConversationDao = mockk(relaxed = true)
    private val analyzer = ChatStorageAnalyzer(messageDao, conversationDao)

    @Test
    fun `analyzeAll — buyukten kucuge sirali`() = runTest {
        val convA = stubConversation("a", "Ali")
        val convB = stubConversation("b", "Veli")
        coEvery { conversationDao.getAllImmediate() } returns listOf(convA, convB)
        coEvery { messageDao.getMessageCount("a") } returns 10
        coEvery { messageDao.getMessageCount("b") } returns 5

        val fileA = tempFolder.newFile("a.bin").apply { writeBytes(ByteArray(5000)) }
        val fileB = tempFolder.newFile("b.bin").apply { writeBytes(ByteArray(500)) }
        coEvery { messageDao.getFileContentsByConversation("a") } returns
            listOf("photo.jpg|image/jpeg|5000|${fileA.absolutePath}")
        coEvery { messageDao.getFileContentsByConversation("b") } returns
            listOf("doc.pdf|application/pdf|500|${fileB.absolutePath}")

        val result = analyzer.analyzeAll()

        assertThat(result).hasSize(2)
        // A daha buyuk → ilk
        assertThat(result[0].conversationId).isEqualTo("a")
        assertThat(result[0].fileBytes).isEqualTo(5000L)
        assertThat(result[0].messageCount).isEqualTo(10)
        assertThat(result[1].conversationId).isEqualTo("b")
    }

    @Test
    fun `path bos — DB'deki size fallback olarak kullanilir`() = runTest {
        val conv = stubConversation("c", "Cem")
        coEvery { conversationDao.getAllImmediate() } returns listOf(conv)
        coEvery { messageDao.getMessageCount("c") } returns 3
        coEvery { messageDao.getFileContentsByConversation("c") } returns
            listOf("photo.jpg|image/jpeg|9999|")  // path bos

        val result = analyzer.analyze(conv)

        assertThat(result.fileBytes).isEqualTo(9999L)
        assertThat(result.fileCount).isEqualTo(1)
    }

    @Test
    fun `cleanFilesForConversation — fiziksel dosya silinir ve DAO delete cagrilir`() = runTest {
        val file = tempFolder.newFile("c.bin").apply { writeBytes(ByteArray(1234)) }
        coEvery { messageDao.getFileContentsByConversation("z") } returns
            listOf("c.bin|application/octet-stream|1234|${file.absolutePath}")

        val freed = analyzer.cleanFilesForConversation("z")

        assertThat(freed).isEqualTo(1234L)
        assertThat(File(file.absolutePath).exists()).isFalse()
        coVerify { messageDao.deleteMediaByConversation("z") }
    }

    private fun stubConversation(id: String, name: String): ConversationEntity =
        ConversationEntity(
            id = id,
            peerId = id,
            peerName = name,
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null
        )
}
