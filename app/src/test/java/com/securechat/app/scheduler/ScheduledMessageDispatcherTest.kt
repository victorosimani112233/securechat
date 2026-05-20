package com.securechat.app.scheduler

import com.google.common.truth.Truth.assertThat
import com.securechat.app.data.UserSession
import com.securechat.app.domain.usecase.SendMessageUseCase
import com.securechat.network.SignalingClient
import com.securechat.network.model.ConnectionState
import com.securechat.storage.dao.ScheduledMessageDao
import com.securechat.storage.entity.ScheduledMessageEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.coVerifyOrder
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Test

/**
 * `ScheduledMessageDispatcher.processPlan` testleri.
 *
 * Plan tetiklendiginde dogru davranis: mesaj gonder + tekrarlama yonet.
 * Tum DAO + UseCase + AlarmScheduler interaction'larini mock'lar.
 */
class ScheduledMessageDispatcherTest {

    private val dao: ScheduledMessageDao = mockk(relaxed = true)
    private val sendMessageUseCase: SendMessageUseCase = mockk(relaxed = true)
    private val alarmScheduler: ScheduledMessageAlarmScheduler = mockk(relaxed = true)
    private val signalingClient: SignalingClient = mockk<SignalingClient>(relaxed = true).apply {
        every { connectionState } returns MutableStateFlow(ConnectionState.Connected)
        coEvery { ensureConnected(any(), any(), any(), any()) } returns true
    }
    private val userSession: UserSession = mockk<UserSession>(relaxed = true).apply {
        every { userId } returns "self_user"
        every { accessToken } returns "test_token"
    }
    private val dispatcher = ScheduledMessageDispatcher(
        dao, sendMessageUseCase, alarmScheduler, signalingClient, userSession
    )

    @Test
    fun `plan DB'de yoksa no-op`() = runTest {
        coEvery { dao.getById("missing") } returns null

        val result = dispatcher.processPlan("missing")

        assertThat(result).isNull()
        coVerify(exactly = 0) { sendMessageUseCase.invoke(any(), any(), any(), any()) }
        coVerify(exactly = 0) { dao.deleteById(any()) }
    }

    @Test
    fun `disabled plan no-op`() = runTest {
        val entity = entity(isEnabled = false)
        coEvery { dao.getById("p1") } returns entity

        val result = dispatcher.processPlan("p1")

        assertThat(result).isNull()
        coVerify(exactly = 0) { sendMessageUseCase.invoke(any(), any(), any(), any()) }
        coVerify(exactly = 0) { dao.update(any()) }
    }

    @Test
    fun `recipient bos - kayit silinir`() = runTest {
        val entity = entity(recipientIds = "")
        coEvery { dao.getById("p1") } returns entity

        dispatcher.processPlan("p1")

        coVerify { dao.deleteById("p1") }
        coVerify(exactly = 0) { sendMessageUseCase.invoke(any(), any(), any(), any()) }
    }

    @Test
    fun `ONCE - mesaj gonderilir + DB'den silinir + alarm reschedule edilmez`() = runTest {
        val entity = entity(recipientIds = "user_a", repeatType = "ONCE")
        coEvery { dao.getById("p1") } returns entity

        dispatcher.processPlan("p1")

        coVerify { sendMessageUseCase("user_a", "Test mesaj") }
        coVerify { dao.deleteById("p1") }
        coVerify(exactly = 0) { dao.update(any()) }
        coVerify(exactly = 0) { alarmScheduler.schedule(any()) }
    }

    @Test
    fun `DAILY - mesaj gonderilir + nextTriggerTime guncellenir + alarm reschedule`() = runTest {
        val entity = entity(recipientIds = "user_a", repeatType = "DAILY", hour = 9, minute = 0)
        coEvery { dao.getById("p1") } returns entity
        val updateSlot = slot<ScheduledMessageEntity>()
        coEvery { dao.update(capture(updateSlot)) } returns Unit

        dispatcher.processPlan("p1")

        coVerify { sendMessageUseCase("user_a", "Test mesaj") }
        coVerify(exactly = 0) { dao.deleteById(any()) }
        coVerify { dao.update(any()) }
        coVerify { alarmScheduler.schedule(any()) }
        // nextTriggerTime artmis olmali (gelecekte bir zaman)
        assertThat(updateSlot.captured.nextTriggerTime).isGreaterThan(System.currentTimeMillis())
    }

    @Test
    fun `birden fazla recipient - hepsine gonderilir`() = runTest {
        val entity = entity(recipientIds = "user_a,user_b,user_c", repeatType = "ONCE")
        coEvery { dao.getById("p1") } returns entity

        dispatcher.processPlan("p1")

        coVerifyOrder {
            sendMessageUseCase("user_a", "Test mesaj")
            sendMessageUseCase("user_b", "Test mesaj")
            sendMessageUseCase("user_c", "Test mesaj")
        }
    }

    @Test
    fun `bir alici fail olursa digerlerine devam`() = runTest {
        val entity = entity(recipientIds = "user_a,user_b,user_c", repeatType = "ONCE")
        coEvery { dao.getById("p1") } returns entity
        coEvery { sendMessageUseCase("user_b", any(), any(), any()) } throws RuntimeException("net hatasi")

        dispatcher.processPlan("p1")

        coVerify { sendMessageUseCase("user_a", "Test mesaj") }
        coVerify { sendMessageUseCase("user_b", "Test mesaj") }
        coVerify { sendMessageUseCase("user_c", "Test mesaj") }
        // ONCE: tum gonderim sonrasi DB'den silinir (bir alici fail olsa bile)
        coVerify { dao.deleteById("p1") }
    }

    @Test
    fun `WS baglanamadi - plan korunur, mesaj gonderilmez, FAILED olusmaz`() = runTest {
        val entity = entity(recipientIds = "user_a", repeatType = "ONCE")
        coEvery { dao.getById("p1") } returns entity
        coEvery { signalingClient.ensureConnected(any(), any(), any(), any()) } returns false

        val result = dispatcher.processPlan("p1")

        assertThat(result).isNull()
        coVerify(exactly = 0) { sendMessageUseCase.invoke(any(), any(), any(), any()) }
        coVerify(exactly = 0) { dao.deleteById(any()) }
        coVerify(exactly = 0) { dao.update(any()) }
    }

    @Test
    fun `userId yoksa plan korunur, mesaj gonderilmez`() = runTest {
        val entity = entity(recipientIds = "user_a", repeatType = "ONCE")
        coEvery { dao.getById("p1") } returns entity
        every { userSession.userId } returns null

        val result = dispatcher.processPlan("p1")

        assertThat(result).isNull()
        coVerify(exactly = 0) { sendMessageUseCase.invoke(any(), any(), any(), any()) }
        coVerify(exactly = 0) { dao.deleteById(any()) }
    }

    @Test
    fun `bozuk repeatType - ONCE gibi davranir (kayit silinir)`() = runTest {
        val entity = entity(recipientIds = "user_a", repeatType = "GIBBERISH")
        coEvery { dao.getById("p1") } returns entity

        dispatcher.processPlan("p1")

        coVerify { dao.deleteById("p1") }
        coVerify(exactly = 0) { alarmScheduler.schedule(any()) }
    }

    // ---- Helper ----

    private fun entity(
        id: String = "p1",
        content: String = "Test mesaj",
        recipientIds: String = "user_a",
        repeatType: String = "ONCE",
        hour: Int = 10,
        minute: Int = 0,
        isEnabled: Boolean = true
    ) = ScheduledMessageEntity(
        id = id,
        messageContent = content,
        repeatType = repeatType,
        repeatDays = null,
        hour = hour,
        minute = minute,
        recipientIds = recipientIds,
        recipientNames = "Test",
        isEnabled = isEnabled,
        nextTriggerTime = 0L
    )
}
