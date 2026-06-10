package com.securechat.app.domain.usecase

import com.securechat.storage.dao.ConversationDao
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test

/**
 * MarkConversationAsUnreadUseCase birim testleri.
 */
class MarkConversationAsUnreadUseCaseTest {

    private val conversationDao: ConversationDao = mockk(relaxed = true)
    private val useCase = MarkConversationAsUnreadUseCase(conversationDao)

    @Test
    fun `mark unread — true delegates to dao`() = runTest {
        useCase("conv-1", markUnread = true)

        coVerify { conversationDao.updateManuallyUnread("conv-1", true) }
    }

    @Test
    fun `clear unread — false delegates to dao`() = runTest {
        useCase("conv-1", markUnread = false)

        coVerify { conversationDao.updateManuallyUnread("conv-1", false) }
    }

    @Test
    fun `default markUnread is true`() = runTest {
        useCase("conv-1")

        coVerify { conversationDao.updateManuallyUnread("conv-1", true) }
    }
}
