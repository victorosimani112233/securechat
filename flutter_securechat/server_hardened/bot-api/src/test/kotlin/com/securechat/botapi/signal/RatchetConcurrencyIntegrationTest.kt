package com.securechat.botapi.signal

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import com.securechat.botapi.db.BotDatabase
import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance
import org.testcontainers.DockerClientFactory
import org.testcontainers.containers.PostgreSQLContainer
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.state.SessionRecord
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.util.UUID

/**
 * Ratchet kaydinin es zamanli yazmaya karsi korunmasi.
 *
 * `loadSession -> ilerlet -> storeSession` dizisi kosulsuz ustune yazarken,
 * ayni aliciya iki es zamanli gonderim bir ratchet adimini kaybediyordu ve
 * alici o mesaji hicbir zaman cozemiyordu. Yazma artik okunan degere karsi
 * compare-and-set'tir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class RatchetConcurrencyIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_ratchet_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; ratchet concurrency testi atlandi",
        )
        postgres.start()
        val migrationDir = Path.of(System.getProperty("serverMigrationDir"))
        DriverManager.getConnection(postgres.jdbcUrl, postgres.username, postgres.password)
            .use { connection ->
                connection.autoCommit = true
                for (version in 1..LAST_MIGRATION) {
                    val migration = Files.list(migrationDir).use { paths ->
                        paths.filter { it.fileName.toString().startsWith("V${version}__") }
                            .findFirst()
                            .orElseThrow()
                    }
                    connection.createStatement().use { it.execute(Files.readString(migration)) }
                }
            }
        BotApiConfig.databaseUrl = postgres.jdbcUrl
        BotApiConfig.databaseUser = postgres.username
        BotApiConfig.databasePassword = postgres.password
        BotApiConfig.botMasterKey = ByteArray(32) { (it + 23).toByte() }
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 63).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 113).toByte() }
        BotDatabase.init()
    }

    @AfterAll
    fun tearDown() {
        BotDatabase.close()
        postgres.stop()
    }

    private fun address() = SignalProtocolAddress(UUID.randomUUID().toString(), 1)

    private fun sessionWith(marker: Byte): SessionRecord {
        // Serilestirilebilir, birbirinden ayirt edilebilir kayitlar.
        val record = SessionRecord()
        record.sessionState.localRegistrationId = marker.toInt() and 0x3FFF
        return record
    }

    @Test
    fun `a first session is written only when no row exists`() {
        val store = PgSignalProtocolStore()
        val peer = address()

        store.loadSession(peer)
        store.storeSession(peer, sessionWith(1))

        assertThat(store.containsSession(peer)).isTrue()
    }

    @Test
    fun `a stale writer is refused instead of overwriting the newer ratchet`() {
        val stale = PgSignalProtocolStore()
        val fresh = PgSignalProtocolStore()
        val peer = address()

        // Ilk kayit.
        stale.loadSession(peer)
        stale.storeSession(peer, sessionWith(1))

        // Iki yazici da ayni kaydi okur.
        stale.loadSession(peer)
        fresh.loadSession(peer)

        // Once biri ilerletip yazar.
        fresh.storeSession(peer, sessionWith(2))

        // Digeri bayat degerin ustune yazamaz.
        val refused = runCatching { stale.storeSession(peer, sessionWith(3)) }
        assertThat(refused.isFailure).isTrue()
        assertThat(refused.exceptionOrNull())
            .isInstanceOf(PgSignalProtocolStore.ConcurrentSessionModificationException::class.java)
    }

    @Test
    fun `a writer that reloads after the change can continue`() {
        val first = PgSignalProtocolStore()
        val second = PgSignalProtocolStore()
        val peer = address()

        first.loadSession(peer)
        first.storeSession(peer, sessionWith(1))

        second.loadSession(peer)
        second.storeSession(peer, sessionWith(2))

        // Guncel degeri yeniden okuyan yazici devam edebilir.
        second.loadSession(peer)
        second.storeSession(peer, sessionWith(3))
        assertThat(store(peer)).isNotNull()
    }

    @Test
    fun `deleting a session clears the tracked baseline`() {
        val store = PgSignalProtocolStore()
        val peer = address()
        store.loadSession(peer)
        store.storeSession(peer, sessionWith(1))

        store.deleteSession(peer)
        assertThat(store.containsSession(peer)).isFalse()

        // Silmeden sonra yeni oturum yeniden yazilabilmeli.
        store.loadSession(peer)
        store.storeSession(peer, sessionWith(2))
        assertThat(store.containsSession(peer)).isTrue()
    }

    private fun store(peer: SignalProtocolAddress): ByteArray? =
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT session_record FROM bot_signal_session WHERE recipient_index = ?",
            ).use { statement ->
                statement.setString(1, PeerIdentityStore.recipientIndex(peer.name))
                statement.executeQuery().use { rows ->
                    if (rows.next()) rows.getBytes(1) else null
                }
            }
        }

    private companion object {
        const val LAST_MIGRATION = 18
    }
}
