package com.securechat.signaling

import io.ktor.websocket.Frame
import io.ktor.websocket.WebSocketExtension
import io.ktor.websocket.WebSocketSession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.UUID
import kotlin.coroutines.CoroutineContext

/**
 * Baglanti yasam dongusu.
 *
 * Ayni kullanici yeniden baglandiginda eski soketin `finally` blogu
 * `removeConnection` cagirir. Kosulsuz `remove`, o anda haritada duran
 * **yeni** soketi silerdi: kullanici bagliyken cevrimdisi gorunur, kendisine
 * yonlendirilen mesajlar offline kuyruga duserdi. Kapasite kontrolu de kilit
 * disindaydi; es zamanli iki baglanti ayni "yer var" okumasini paylasabilirdi.
 */
class ConnectionLifecycleTest {

    private class FakeSession : WebSocketSession {
        override val coroutineContext: CoroutineContext = Job() + Dispatchers.Unconfined
        override val incoming = Channel<Frame>(Channel.UNLIMITED)
        override val outgoing = Channel<Frame>(Channel.UNLIMITED)
        override val extensions: List<WebSocketExtension<*>> = emptyList()
        override var maxFrameSize: Long = Long.MAX_VALUE
        override var masking: Boolean = false

        override suspend fun send(frame: Frame) {
            outgoing.trySend(frame)
        }

        override suspend fun flush() = Unit

        @Deprecated(
            "Use cancel() instead.",
            replaceWith = ReplaceWith("cancel()", "kotlinx.coroutines.cancel"),
        )
        override fun terminate() {
            outgoing.close()
            incoming.close()
        }
    }

    private val manager = ConnectionManager()
    private val user = UUID.randomUUID().toString()

    @Test
    fun `a fresh connection is accepted and reported online`() = runBlocking {
        val session = FakeSession()

        assertTrue(manager.addConnection(user, session))
        assertTrue(manager.isOnline(user))
        assertEquals(session, manager.connections()[user])
    }

    @Test
    fun `a stale socket close does not evict the reconnected socket`() = runBlocking {
        val old = FakeSession()
        val new = FakeSession()
        assertTrue(manager.addConnection(user, old))
        assertTrue(manager.addConnection(user, new))

        // Eski soketin `finally` blogu simdi calisiyor.
        manager.removeConnection(user, old)

        assertTrue(manager.isOnline(user), "yeni baglanti silinmis olmamali")
        assertEquals(new, manager.connections()[user])
    }

    @Test
    fun `closing the current socket does take the user offline`() = runBlocking {
        val session = FakeSession()
        manager.addConnection(user, session)

        manager.removeConnection(user, session)

        assertFalse(manager.isOnline(user))
    }

    @Test
    fun `an unconditional remove still works for server initiated teardown`() = runBlocking {
        val session = FakeSession()
        manager.addConnection(user, session)

        // session=null: sunucu tarafli kapatma, hangi soket oldugu onemsiz.
        manager.removeConnection(user, null)

        assertFalse(manager.isOnline(user))
    }

    @Test
    fun `removing an unknown user is a no-op`() = runBlocking {
        manager.removeConnection(UUID.randomUUID().toString(), FakeSession())

        assertEquals(0, manager.getOnlineCount())
    }

    @Test
    fun `reconnecting the same user does not inflate the online count`() = runBlocking {
        repeat(5) { assertTrue(manager.addConnection(user, FakeSession())) }

        assertEquals(1, manager.getOnlineCount())
    }

    @Test
    fun `presence subscriptions survive a stale socket close`() = runBlocking {
        val watcher = UUID.randomUUID().toString()
        val old = FakeSession()
        val new = FakeSession()
        manager.addConnection(watcher, old)
        assertTrue(manager.subscribePresence(watcher, user))
        manager.addConnection(watcher, new)

        manager.removeConnection(watcher, old)

        // Abonelik temizligi yalniz gercekten kopan oturum icin yapilmali;
        // aksi halde canli oturumun abonelikleri sessizce dusurulurdu.
        assertEquals(1, manager.subscriptionCount(watcher))
    }

    @Test
    fun `a genuine close does clear the subscriptions`() = runBlocking {
        val watcher = UUID.randomUUID().toString()
        val session = FakeSession()
        manager.addConnection(watcher, session)
        manager.subscribePresence(watcher, user)

        manager.removeConnection(watcher, session)

        assertEquals(0, manager.subscriptionCount(watcher))
    }

    @Test
    fun `one user disconnecting does not affect another`() = runBlocking {
        val other = UUID.randomUUID().toString()
        val mine = FakeSession()
        val theirs = FakeSession()
        manager.addConnection(user, mine)
        manager.addConnection(other, theirs)

        manager.removeConnection(user, mine)

        assertFalse(manager.isOnline(user))
        assertTrue(manager.isOnline(other))
        assertEquals(1, manager.getOnlineCount())
    }

    @Test
    fun `a shutting down server refuses new connections`() = runBlocking {
        val closing = ConnectionManager()
        isShuttingDown.set(true)
        try {
            assertFalse(closing.addConnection(user, FakeSession()))
            assertFalse(closing.isOnline(user))
        } finally {
            isShuttingDown.set(false)
        }
    }
}
