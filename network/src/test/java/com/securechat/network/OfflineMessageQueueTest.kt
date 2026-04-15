package com.securechat.network

import com.google.common.truth.Truth.assertThat
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.crypto.model.EnvelopeType
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Before
import org.junit.Test

/**
 * OfflineMessageQueue sinifinin unit testleri.
 * Mesaj kuyruga ekleme, gonderme, flush ve temizleme islemlerini test eder.
 *
 * Gercek OkHttpClient ve SignalingClient kullaniliyor (WebSocket baglantisi yok).
 * Bu sekilde sendSignal her zaman false donecek ve mesajlar kuyruga eklenir.
 * MessageEncryptor MockK ile mocklaniyor (sadece encrypt metodu).
 */
class OfflineMessageQueueTest {

    private lateinit var signalingClient: SignalingClient
    private lateinit var mockEncryptor: MessageEncryptor
    private lateinit var queue: OfflineMessageQueue

    private val testEnvelope = EncryptedEnvelope(
        type = EnvelopeType.SIGNAL,
        content = "fake".toByteArray(),
        timestamp = 1000L,
        senderRegistrationId = 1
    )

    @Before
    fun setUp() {
        // Gercek OkHttpClient ve SignalingClient — WebSocket baglantisi kurmadan
        signalingClient = SignalingClient(OkHttpClient.Builder().build())

        mockEncryptor = mockk()
        every { mockEncryptor.encrypt(any(), any()) } returns testEnvelope

        queue = OfflineMessageQueue(signalingClient, mockEncryptor)
    }

    @After
    fun tearDown() {
        queue.clearQueue()
        signalingClient.disconnect()
    }

    @Test
    fun `initial queue is empty`() {
        assertThat(queue.getPendingCount()).isEqualTo(0)
    }

    @Test
    fun `queueMessage adds to pending when no connection`() {
        queue.queueMessage("s", "r", "Hello!")
        assertThat(queue.getPendingCount()).isEqualTo(1)
    }

    @Test
    fun `multiple failed messages accumulate`() {
        queue.queueMessage("s", "r1", "M1")
        queue.queueMessage("s", "r1", "M2")
        queue.queueMessage("s", "r2", "M3")
        assertThat(queue.getPendingCount()).isEqualTo(3)
    }

    @Test
    fun `clearQueue removes all pending`() {
        queue.queueMessage("s", "r", "M1")
        queue.queueMessage("s", "r", "M2")
        assertThat(queue.getPendingCount()).isEqualTo(2)
        queue.clearQueue()
        assertThat(queue.getPendingCount()).isEqualTo(0)
    }

    @Test
    fun `flushQueue re-queues when still no connection`() {
        queue.queueMessage("s", "r", "M1")
        assertThat(queue.getPendingCount()).isEqualTo(1)
        // Flush sirasinda da baglanti yok, mesaj tekrar kuyruga eklenmeli
        queue.flushQueue("s")
        assertThat(queue.getPendingCount()).isEqualTo(1)
    }

    @Test
    fun `clearQueue on empty does not throw`() {
        queue.clearQueue()
        assertThat(queue.getPendingCount()).isEqualTo(0)
    }

    @Test
    fun `flushQueue on empty does not throw`() {
        queue.flushQueue("s")
        assertThat(queue.getPendingCount()).isEqualTo(0)
    }

    @Test
    fun `queueMessage encrypts with correct recipient`() {
        queue.queueMessage("s", "r42", "test")
        verify { mockEncryptor.encrypt("r42", "test".toByteArray(Charsets.UTF_8)) }
    }
}
