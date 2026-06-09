package com.securechat.app.domain.usecase

import com.securechat.app.crypto.GroupSenderKeyDistributor
import com.securechat.app.crypto.SessionEnsurer
import com.securechat.app.data.UserSession
import com.securechat.crypto.MessageEncryptor
import com.securechat.crypto.SecureChatSenderKeyStore
import com.securechat.crypto.model.EncryptedEnvelope
import com.securechat.crypto.model.EnvelopeType
import com.securechat.network.SignalingClient
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * SendMessageUseCase birim testleri.
 */
class SendMessageUseCaseTest {

    private lateinit var messageRepository: MessageRepository
    private lateinit var signalingClient: SignalingClient
    private lateinit var userSession: UserSession
    private lateinit var conversationDao: com.securechat.storage.dao.ConversationDao
    private lateinit var messageEncryptor: MessageEncryptor
    private lateinit var sessionEnsurer: SessionEnsurer
    private lateinit var groupSenderKeyDistributor: GroupSenderKeyDistributor
    private lateinit var senderKeyStore: SecureChatSenderKeyStore
    private lateinit var sendMessageUseCase: SendMessageUseCase

    @Before
    fun setup() {
        messageRepository = mockk(relaxed = true)
        signalingClient = mockk(relaxed = true)
        userSession = mockk(relaxed = true)
        conversationDao = mockk(relaxed = true)
        messageEncryptor = mockk(relaxed = true)
        sessionEnsurer = mockk(relaxed = true)
        groupSenderKeyDistributor = mockk(relaxed = true)
        senderKeyStore = mockk(relaxed = true)
        every { userSession.userId } returns "local_user"
        every { signalingClient.sendSignal(any()) } returns true
        // 2026-06-09 guvenlik fix sonrasi: plaintext fallback YOK. Varsayilanda
        // session kuruldugunu ve encrypt'in basarili oldugunu mock'lariz; bu sayede
        // mevcut testler "sifreli envelope gonderildi" senaryosunda calisir. Negatif
        // (encrypt fail = FAILED) testleri kendi mock'larini ayri ayri kurar.
        coEvery { sessionEnsurer.ensureSession(any()) } returns true
        every { messageEncryptor.encrypt(any(), any()) } returns
            com.securechat.crypto.model.EncryptedEnvelope(
                type = com.securechat.crypto.model.EnvelopeType.SIGNAL,
                content = byteArrayOf(1, 2, 3),
                timestamp = 0L,
                senderRegistrationId = 1
            )
        coEvery { groupSenderKeyDistributor.ensureDistributed(any()) } returns true
        sendMessageUseCase = SendMessageUseCase(
            messageRepository, signalingClient, userSession, conversationDao,
            messageEncryptor, sessionEnsurer, groupSenderKeyDistributor, senderKeyStore
        )
    }

    @Test
    fun `invoke creates message with correct conversationId`() = runTest {
        val conversationId = "conv_123"
        val content = "Merhaba"

        sendMessageUseCase(conversationId, content)

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(conversationId, messageSlot.captured.conversationId)
    }

    @Test
    fun `invoke creates message with correct content`() = runTest {
        val content = "Test mesaji"

        sendMessageUseCase("conv_1", content)

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(content, messageSlot.captured.content)
    }

    @Test
    fun `invoke creates message with TEXT content type`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(MessageContentType.TEXT, messageSlot.captured.contentType)
    }

    @Test
    fun `invoke creates message with SENDING status`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals(MessageStatus.SENDING, messageSlot.captured.status)
    }

    @Test
    fun `invoke creates outgoing message`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertTrue(messageSlot.captured.isOutgoing)
    }

    @Test
    fun `invoke creates message with unique id`() = runTest {
        sendMessageUseCase("conv_1", "test1")
        sendMessageUseCase("conv_1", "test2")

        val messages = mutableListOf<LocalMessage>()
        coVerify(exactly = 2) { messageRepository.saveMessage(capture(messages)) }

        assertTrue(messages[0].id != messages[1].id)
    }

    @Test
    fun `invoke uses userId from UserSession as senderId`() = runTest {
        sendMessageUseCase("conv_1", "test")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }

        assertEquals("local_user", messageSlot.captured.senderId)
    }

    @Test
    fun `invoke calls repository saveMessage`() = runTest {
        sendMessageUseCase("conv_1", "test")

        coVerify(exactly = 1) { messageRepository.saveMessage(any()) }
    }

    @Test
    fun `invoke sends signal via signalingClient`() = runTest {
        sendMessageUseCase("conv_1", "test")

        coVerify(exactly = 1) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `invoke updates status to SENT on success`() = runTest {
        every { signalingClient.sendSignal(any()) } returns true

        sendMessageUseCase("conv_1", "test")

        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.SENT) }
    }

    @Test
    fun `invoke updates status to FAILED on signaling failure`() = runTest {
        every { signalingClient.sendSignal(any()) } returns false

        sendMessageUseCase("conv_1", "test")

        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.FAILED) }
    }

    // ---- Yeni eklenenler (kritik path coverage) ----

    @Test
    fun `transient failure - retry sonrasi basari - SENT olarak isaretlenir`() = runTest {
        // Ilk 2 deneme false, 3. deneme true
        var attempt = 0
        every { signalingClient.sendSignal(any()) } answers {
            attempt++
            attempt >= 3
        }

        sendMessageUseCase("conv_1", "test")

        // En az 3 attempt yapilmis olmali (ilk + 2 retry)
        coVerify(atLeast = 3) { signalingClient.sendSignal(any()) }
        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.SENT) }
        coVerify(exactly = 0) { messageRepository.updateMessageStatus(any(), MessageStatus.FAILED) }
    }

    @Test
    fun `tum retryler fail - en az MAX_RETRY+1 deneme + FAILED`() = runTest {
        every { signalingClient.sendSignal(any()) } returns false

        sendMessageUseCase("conv_1", "test")

        // 1 ilk + 3 retry = 4 deneme
        coVerify(exactly = SendMessageUseCase.MAX_RETRY_COUNT + 1) { signalingClient.sendSignal(any()) }
        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.FAILED) }
    }

    @Test
    fun `grup konusma - GroupCipher fail ise mesaj FAILED + signal yok`() = runTest {
        // 2026-06-09 guvenlik fix: grup encrypt fail (sender key kurulmamis vb.) -> FAILED.
        // Sender key store mock'u bos record doner, GroupCipher.encrypt NoSession atar.
        // Plaintext fallback yok artik.
        val groupId = "group_xyz"
        val groupConv = com.securechat.storage.entity.ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Test Grup",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user_a,user_b,user_c"
        )
        coEvery { conversationDao.getById(groupId) } returns groupConv

        sendMessageUseCase(groupId, "Selam grup")

        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.FAILED) }
        coVerify(exactly = 0) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `birebir konusma - EncryptedMessage signal turu kullanilir`() = runTest {
        coEvery { conversationDao.getById("conv_1") } returns null // birebir, isGroup=false

        sendMessageUseCase("conv_1", "Selam")

        val signalSlot = slot<com.securechat.network.SignalMessage>()
        coVerify { signalingClient.sendSignal(capture(signalSlot)) }
        assertTrue(signalSlot.captured is com.securechat.network.SignalMessage.EncryptedMessage)
    }

    @Test
    fun `replyToId set - mesajda replyToId saklanir`() = runTest {
        sendMessageUseCase("conv_1", "Cevap", replyToId = "msg_123")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }
        assertEquals("msg_123", messageSlot.captured.replyToId)
    }

    @Test
    fun `disappearing duration set - expiresAt hesaplanir`() = runTest {
        val convWithDisappearing = com.securechat.storage.entity.ConversationEntity(
            id = "conv_disap",
            peerId = "conv_disap",
            peerName = "Test",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = false,
            disappearingDuration = 3600_000L // 1 saat
        )
        coEvery { conversationDao.getById("conv_disap") } returns convWithDisappearing

        sendMessageUseCase("conv_disap", "siliner")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }
        val expiresAt = messageSlot.captured.expiresAt
        assertTrue(expiresAt != null && expiresAt > System.currentTimeMillis())
    }

    @Test
    fun `disappearing duration 0 - expiresAt null olur`() = runTest {
        coEvery { conversationDao.getById("conv_1") } returns null

        sendMessageUseCase("conv_1", "kalici")

        val messageSlot = slot<LocalMessage>()
        coVerify { messageRepository.saveMessage(capture(messageSlot)) }
        assertEquals(null, messageSlot.captured.expiresAt)
    }

    @Test
    fun `disappearing duration set - encrypt edilen plaintext EXP prefix icerir`() = runTest {
        // E2EE sonrasi envelope encrypted gidiyor — wire'da EXP gorunmez. MessageEncryptor.encrypt'e
        // GECEN plaintext'i ANSWERS lambda ile KOPYALAYIP capture ederiz (slot capture
        // SendMessageUseCase'in plaintext.fill(0) zeroize'i nedeniyle sifirlanmis referans
        // tutar). Encrypt sonrasi kopya assertion icin temiz kalir.
        val convWithDisappearing = com.securechat.storage.entity.ConversationEntity(
            id = "conv_disap",
            peerId = "conv_disap",
            peerName = "Test",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = false,
            disappearingDuration = 60_000L
        )
        coEvery { conversationDao.getById("conv_disap") } returns convWithDisappearing
        var capturedPlaintext: ByteArray? = null
        every { messageEncryptor.encrypt(eq("conv_disap"), any()) } answers {
            capturedPlaintext = secondArg<ByteArray>().copyOf()
            EncryptedEnvelope(
                type = EnvelopeType.SIGNAL,
                content = byteArrayOf(1),
                timestamp = 0L,
                senderRegistrationId = 1
            )
        }

        sendMessageUseCase("conv_disap", "merhaba")

        val plaintext = String(capturedPlaintext!!, Charsets.UTF_8)
        assertTrue("Plaintext EXP prefix icermeli: $plaintext", plaintext.contains("EXP:"))
        val expRegex = Regex(":EXP:(\\d+):")
        val match = expRegex.find(plaintext)
        assertTrue("EXP ms degeri parse edilemedi: $plaintext", match != null)
        val expMs = match!!.groupValues[1].toLong()
        assertTrue("EXP ms gelecek olmali: $expMs", expMs > System.currentTimeMillis())
    }

    @Test
    fun `disappearing duration 0 - encrypt edilen plaintext EXP icermez`() = runTest {
        coEvery { conversationDao.getById("conv_1") } returns null
        var capturedPlaintext: ByteArray? = null
        every { messageEncryptor.encrypt(eq("conv_1"), any()) } answers {
            capturedPlaintext = secondArg<ByteArray>().copyOf()
            EncryptedEnvelope(
                type = EnvelopeType.SIGNAL,
                content = byteArrayOf(1),
                timestamp = 0L,
                senderRegistrationId = 1
            )
        }

        sendMessageUseCase("conv_1", "kalici")

        val plaintext = String(capturedPlaintext!!, Charsets.UTF_8)
        assertTrue("Plaintext EXP prefix icermemeli: $plaintext", !plaintext.contains("EXP:"))
    }

    // ---- E2EE 1:1 (FAZ 0) ----

    @Test
    fun `1to1 - session kurulduysa envelope E2EE_v1 prefix ile gider`() = runTest {
        coEvery { conversationDao.getById("conv_1") } returns null
        coEvery { sessionEnsurer.ensureSession("conv_1") } returns true
        every { messageEncryptor.encrypt(eq("conv_1"), any()) } returns EncryptedEnvelope(
            type = EnvelopeType.PREKEY,
            content = byteArrayOf(0x01, 0x02, 0x03),
            timestamp = 1L,
            senderRegistrationId = 42
        )

        sendMessageUseCase("conv_1", "Selam")

        val signalSlot = slot<com.securechat.network.SignalMessage>()
        coVerify { signalingClient.sendSignal(capture(signalSlot)) }
        val envelope = (signalSlot.captured as com.securechat.network.SignalMessage.EncryptedMessage).envelope
        assertTrue("Envelope E2EE:v1: prefix ile baslamali: $envelope", envelope.startsWith("E2EE:v1:PREKEY:42:"))
    }

    @Test
    fun `1to1 - session yok ise mesaj FAILED + signal gonderilmez`() = runTest {
        // 2026-06-09 guvenlik fix: plaintext fallback KALDIRILDI. Session kurulamazsa
        // mesaj FAILED isaretlenir, sifresiz gonderilmez.
        coEvery { conversationDao.getById("conv_1") } returns null
        coEvery { sessionEnsurer.ensureSession("conv_1") } returns false

        sendMessageUseCase("conv_1", "Selam")

        coVerify { messageRepository.updateMessageStatus(any(), MessageStatus.FAILED) }
        coVerify(exactly = 0) { signalingClient.sendSignal(any()) }
    }

    @Test
    fun `grup mesaji - sessionEnsurer cagrilmaz`() = runTest {
        val groupId = "g_xyz"
        coEvery { conversationDao.getById(groupId) } returns com.securechat.storage.entity.ConversationEntity(
            id = groupId,
            peerId = groupId,
            peerName = "Test Grup",
            peerPhone = "",
            lastMessage = null,
            lastMessageTimestamp = null,
            isGroup = true,
            groupMembers = "user_a,user_b"
        )

        sendMessageUseCase(groupId, "selam grup")

        coVerify(exactly = 0) { sessionEnsurer.ensureSession(any()) }
    }
}
