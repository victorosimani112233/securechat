package com.securechat.storage

import com.securechat.storage.dao.MessageDao
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * DataCleanupManager icin unit testler.
 * Eski mesaj temizligi ve tum veri silme islemlerini dogrular.
 */
class DataCleanupManagerTest {

    private lateinit var database: SecureChatDatabase
    private lateinit var messageDao: MessageDao
    private lateinit var cleanupManager: DataCleanupManager

    @Before
    fun setup() {
        messageDao = mockk(relaxed = true)
        database = mockk(relaxed = true)
        every { database.messageDao() } returns messageDao
        cleanupManager = DataCleanupManager(database)
    }

    @Test
    fun `cleanOldMessages calculates cutoff correctly for 30 days`() = runTest {
        val cutoffSlot = slot<Long>()
        coEvery { messageDao.deleteOlderThan(capture(cutoffSlot)) } returns Unit

        val beforeCall = System.currentTimeMillis()
        cleanupManager.cleanOldMessages(30)
        val afterCall = System.currentTimeMillis()

        val expectedMin = beforeCall - (30 * 24L * 60 * 60 * 1000)
        val expectedMax = afterCall - (30 * 24L * 60 * 60 * 1000)

        assertThat(cutoffSlot.captured).isAtLeast(expectedMin)
        assertThat(cutoffSlot.captured).isAtMost(expectedMax)
    }

    @Test
    fun `cleanOldMessages calculates cutoff correctly for 1 day`() = runTest {
        val cutoffSlot = slot<Long>()
        coEvery { messageDao.deleteOlderThan(capture(cutoffSlot)) } returns Unit

        val beforeCall = System.currentTimeMillis()
        cleanupManager.cleanOldMessages(1)
        val afterCall = System.currentTimeMillis()

        val expectedMin = beforeCall - (1 * 24L * 60 * 60 * 1000)
        val expectedMax = afterCall - (1 * 24L * 60 * 60 * 1000)

        assertThat(cutoffSlot.captured).isAtLeast(expectedMin)
        assertThat(cutoffSlot.captured).isAtMost(expectedMax)
    }

    @Test
    fun `cleanOldMessages delegates to messageDao deleteOlderThan`() = runTest {
        cleanupManager.cleanOldMessages(7)

        coVerify { messageDao.deleteOlderThan(any()) }
    }

    @Test
    fun `nukeAllData clears all tables`() = runTest {
        cleanupManager.nukeAllData()

        coVerify { database.clearAllTables() }
    }
}
