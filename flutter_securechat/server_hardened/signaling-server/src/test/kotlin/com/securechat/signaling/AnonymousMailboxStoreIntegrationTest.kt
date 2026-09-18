package com.securechat.signaling

import com.securechat.signaling.db.Database
import java.util.UUID
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class AnonymousMailboxStoreIntegrationTest {
    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_anonymous_mailbox")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }
    private lateinit var registry: UserRegistry

    @BeforeAll
    fun setUp() {
        assumeTrue(DockerClientFactory.instance().isDockerAvailable, "Docker yok; mailbox testi atlandi")
        postgres.start()
        Database.init(postgres.jdbcUrl, postgres.username, postgres.password)
        Database.ensureSchema()
        ServerPrivacy.initialize()
        registry = UserRegistry()
    }

    @AfterAll
    fun tearDown() {
        if (!DockerClientFactory.instance().isDockerAvailable) return
        runCatching { Database.close() }
        postgres.stop()
    }

    private fun account(): String = UUID.randomUUID().toString().also(registry::registerUser)

    private val capabilityCounter = java.util.concurrent.atomic.AtomicInteger()

    /**
     * Her cagrida farkli, 43 karakterlik gecerli bir capability.
     *
     * Testler ayni PostgreSQL ornegini paylasir ve rotasyon artik kalici bir
     * tombstone birakir; sabit degerler kullanilsaydi bir testin emekliye
     * ayirdigi mailbox baska bir testin kaydini bozardi.
     */
    private fun capability(): String =
        "cap" + capabilityCounter.incrementAndGet().toString().padStart(40, '0')

    @Test
    fun `registration persists only purpose-separated indexes and authorizes exact capability`() {
        val userId = account()
        val mailbox = capability()
        val writeKey = capability()

        AnonymousMailboxStore.register(
            userId,
            AnonymousMailboxStore.Registration(mailbox, writeKey, 1, 1),
        )

        val stored = Database.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT mailbox_index, write_key_index FROM sealed_sender_mailboxes WHERE user_id = ?::uuid",
            ).use { statement ->
                statement.setString(1, userId)
                statement.executeQuery().use { rows ->
                    assertTrue(rows.next())
                    rows.getString(1) to rows.getString(2)
                }
            }
        }
        assertEquals(43, stored.first.length)
        assertEquals(43, stored.second.length)
        assertFalse(stored.first.contains(mailbox))
        assertFalse(stored.second.contains(writeKey))
        assertEquals(userId, AnonymousMailboxStore.authorize(mailbox, writeKey))
        assertNull(AnonymousMailboxStore.authorize(mailbox, capability()))
        assertNull(AnonymousMailboxStore.authorize(capability(), writeKey))
    }

    @Test
    fun `a retired capability cannot be claimed by another account`() {
        // Rotasyondan once mailbox'i ogrenmis bir peer, eski adresi kendi
        // uzerine alabilseydi oraya gonderilen zarflari toplayabilir,
        // icerigi cozemese de kimin-ne-zaman metadatasini elde eder ve
        // mesajlari sessizce dusururdu.
        val owner = account()
        val peer = account()
        val retired = capability()
        val rotated = capability()
        val writeKey = capability()
        val peerWriteKey = capability()

        AnonymousMailboxStore.register(
            owner,
            AnonymousMailboxStore.Registration(retired, writeKey, 1, 1),
        )
        AnonymousMailboxStore.register(
            owner,
            AnonymousMailboxStore.Registration(rotated, writeKey, 1, 2),
        )

        val claim = assertThrows(IllegalArgumentException::class.java) {
            AnonymousMailboxStore.register(
                peer,
                AnonymousMailboxStore.Registration(retired, peerWriteKey, 1, 1),
            )
        }
        assertEquals("Retired mailbox capability", claim.message)
        assertNull(AnonymousMailboxStore.authorize(retired, writeKey))
        assertNull(AnonymousMailboxStore.authorize(retired, peerWriteKey))
        assertEquals(owner, AnonymousMailboxStore.authorize(rotated, writeKey))
    }

    @Test
    fun `an owner cannot silently reclaim its own retired capability`() {
        val owner = account()
        val retired = capability()
        val writeKey = capability()

        AnonymousMailboxStore.register(
            owner,
            AnonymousMailboxStore.Registration(retired, writeKey, 1, 1),
        )
        AnonymousMailboxStore.register(
            owner,
            AnonymousMailboxStore.Registration(capability(), writeKey, 1, 2),
        )

        assertThrows(IllegalArgumentException::class.java) {
            AnonymousMailboxStore.register(
                owner,
                AnonymousMailboxStore.Registration(retired, writeKey, 1, 3),
            )
        }
    }

    @Test
    fun `rotation atomically invalidates the previous destination capability`() {
        val userId = account()
        val oldMailbox = capability()
        val oldWriteKey = capability()
        val newMailbox = capability()
        val newWriteKey = capability()
        AnonymousMailboxStore.register(
            userId,
            AnonymousMailboxStore.Registration(oldMailbox, oldWriteKey, 1, 1),
        )

        AnonymousMailboxStore.register(
            userId,
            AnonymousMailboxStore.Registration(newMailbox, newWriteKey, 1, 2),
        )

        assertNull(AnonymousMailboxStore.authorize(oldMailbox, oldWriteKey))
        assertEquals(userId, AnonymousMailboxStore.authorize(newMailbox, newWriteKey))
        assertThrows(IllegalArgumentException::class.java) {
            AnonymousMailboxStore.register(
                userId,
                AnonymousMailboxStore.Registration(oldMailbox, oldWriteKey, 1, 1),
            )
        }
        assertEquals(userId, AnonymousMailboxStore.authorize(newMailbox, newWriteKey))
    }

    @Test
    fun `a mailbox cannot be claimed by two accounts`() {
        val first = account()
        val second = account()
        val mailbox = capability()
        val firstWriteKey = capability()
        AnonymousMailboxStore.register(
            first,
            AnonymousMailboxStore.Registration(mailbox, firstWriteKey, 1, 1),
        )

        assertThrows(Exception::class.java) {
            AnonymousMailboxStore.register(
                second,
                AnonymousMailboxStore.Registration(mailbox, capability(), 1, 1),
            )
        }
        assertEquals(first, AnonymousMailboxStore.authorize(mailbox, firstWriteKey))
    }

    @Test
    fun `account deletion removes the anonymous mailbox`() {
        val userId = account()
        val mailbox = capability()
        val writeKey = capability()
        AnonymousMailboxStore.register(
            userId,
            AnonymousMailboxStore.Registration(mailbox, writeKey, 1, 1),
        )

        Database.getConnection().use { connection ->
            connection.prepareStatement("DELETE FROM users WHERE user_id = ?::uuid").use { statement ->
                statement.setString(1, userId)
                assertEquals(1, statement.executeUpdate())
            }
        }

        assertNull(AnonymousMailboxStore.authorize(mailbox, writeKey))
        assertFalse(AnonymousMailboxStore.hasMailbox(userId))
    }
}
