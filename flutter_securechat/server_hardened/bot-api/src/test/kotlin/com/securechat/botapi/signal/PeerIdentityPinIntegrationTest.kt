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
import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.state.IdentityKeyStore
import org.whispersystems.libsignal.util.KeyHelper
import java.nio.file.Files
import java.nio.file.Path
import java.sql.DriverManager
import java.util.UUID

/**
 * Alici identity pinlemesi.
 *
 * Onceki implementasyonda `isTrustedIdentity` kosulsuz true donuyor ve
 * hicbir peer identity saklanmiyordu; signaling/DB/ic ag ihlali alicinin
 * anahtarini sessizce degistirebilirdi. Burada ilk anahtarin pinlendigi,
 * degisen anahtarin fail-closed reddedildigi ve rotasyonun ancak acik
 * operator onayindan sonra kabul edildigi kanitlanir.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PeerIdentityPinIntegrationTest {

    private val postgres = PostgreSQLContainer<Nothing>("postgres:16").apply {
        withDatabaseName("securechat_identity_pin_test")
        withUsername("securechat_test")
        withPassword("securechat_test_password")
    }

    private lateinit var store: PgSignalProtocolStore

    @BeforeAll
    fun setUp() {
        assumeTrue(
            DockerClientFactory.instance().isDockerAvailable,
            "Docker yok; identity pin integration testi atlandi",
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
        BotApiConfig.botMasterKey = ByteArray(32) { (it + 13).toByte() }
        BotApiConfig.privacyIndexKey = ByteArray(32) { (it + 53).toByte() }
        BotApiConfig.botQueueEncryptionKey = ByteArray(32) { (it + 103).toByte() }
        BotDatabase.init()
        store = PgSignalProtocolStore()
    }

    @AfterAll
    fun tearDown() {
        BotDatabase.close()
        postgres.stop()
    }

    private fun identity(): IdentityKey = KeyHelper.generateIdentityKeyPair().publicKey

    private fun address(): SignalProtocolAddress =
        SignalProtocolAddress(UUID.randomUUID().toString(), 1)

    @Test
    fun `the first identity is trusted and pinned`() {
        val peer = address()
        val key = identity()

        assertThat(
            store.isTrustedIdentity(peer, key, IdentityKeyStore.Direction.SENDING),
        ).isTrue()
        store.saveIdentity(peer, key)

        assertThat(store.getIdentity(peer)?.serialize()).isEqualTo(key.serialize())
        assertThat(
            store.isTrustedIdentity(peer, key, IdentityKeyStore.Direction.SENDING),
        ).isTrue()
    }

    @Test
    fun `a swapped identity is refused instead of silently accepted`() {
        val peer = address()
        val original = identity()
        store.saveIdentity(peer, original)

        val attacker = identity()

        assertThat(
            store.isTrustedIdentity(peer, attacker, IdentityKeyStore.Direction.SENDING),
        ).isFalse()
        // Pin sessizce ustune yazilmaz.
        assertThat(store.getIdentity(peer)?.serialize()).isEqualTo(original.serialize())
        store.saveIdentity(peer, attacker)
        assertThat(store.getIdentity(peer)?.serialize()).isEqualTo(original.serialize())
    }

    @Test
    fun `rotation is accepted only after an explicit operator approval`() {
        val peer = address()
        val original = identity()
        store.saveIdentity(peer, original)
        val rotated = identity()
        assertThat(
            store.isTrustedIdentity(peer, rotated, IdentityKeyStore.Direction.SENDING),
        ).isFalse()

        val index = PeerIdentityStore.recipientIndex(peer.name)
        assertThat(PeerIdentityStore.approveRotation(index, peer.deviceId)).isTrue()

        assertThat(
            store.isTrustedIdentity(peer, rotated, IdentityKeyStore.Direction.SENDING),
        ).isTrue()
        store.saveIdentity(peer, rotated)
        assertThat(store.getIdentity(peer)?.serialize()).isEqualTo(rotated.serialize())
    }

    @Test
    fun `pins are stored without a raw recipient id and sealed at rest`() {
        val peer = address()
        val key = identity()
        store.saveIdentity(peer, key)

        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                "SELECT recipient_index, identity_key_sealed FROM bot_peer_identity",
            ).use { statement ->
                statement.executeQuery().use { rows ->
                    var seenPeer = false
                    while (rows.next()) {
                        val index = rows.getString("recipient_index")
                        assertThat(index).doesNotContain(peer.name)
                        val sealed = rows.getBytes("identity_key_sealed")
                        // Public anahtar bile at-rest muhurlu tutulur; ham
                        // byte'lar satirda gorunmez.
                        assertThat(sealed).isNotEqualTo(key.serialize())
                        if (index == PeerIdentityStore.recipientIndex(peer.name)) seenPeer = true
                    }
                    assertThat(seenPeer).isTrue()
                }
            }
        }
    }

    @Test
    fun `a pin sealed for one recipient cannot be opened under another`() {
        val peer = address()
        val other = address()
        val key = identity()
        store.saveIdentity(peer, key)

        val peerIndex = PeerIdentityStore.recipientIndex(peer.name)
        val otherIndex = PeerIdentityStore.recipientIndex(other.name)
        // AAD baglantisi: muhurlu satir baska bir index altina tasinirsa
        // acilamaz.
        BotDatabase.getConnection().use { connection ->
            connection.prepareStatement(
                """INSERT INTO bot_peer_identity(recipient_index, device_id, identity_key_sealed)
                   SELECT ?, device_id, identity_key_sealed FROM bot_peer_identity
                   WHERE recipient_index = ?""",
            ).use { statement ->
                statement.setString(1, otherIndex)
                statement.setString(2, peerIndex)
                statement.executeUpdate()
            }
        }

        assertThat(runCatching { PeerIdentityStore.pinned(otherIndex, 1) }.isFailure).isTrue()
        // Okunamayan bir pin guvenilir sayilmaz.
        assertThat(
            store.isTrustedIdentity(other, key, IdentityKeyStore.Direction.SENDING),
        ).isFalse()
    }

    private companion object {
        const val LAST_MIGRATION = 18
    }
}
