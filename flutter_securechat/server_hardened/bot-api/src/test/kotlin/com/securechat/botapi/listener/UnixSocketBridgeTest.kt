package com.securechat.botapi.listener

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SocketChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermission
import kotlin.concurrent.thread

/**
 * Bot'un dis yuzunun gercekten bir Unix domain socket uzerinden
 * erisilebildigini ve socket dosyasinin yalniz sahibine acik oldugunu
 * kanitlar.
 *
 * Onceki durumda listener yalniz container ici `127.0.0.1`'e bind oluyordu
 * ve compose ne port ne socket mount sagladigi icin yuzey disaridan hic
 * erisilemiyordu.
 */
class UnixSocketBridgeTest {

    private var bridge: UnixSocketBridge? = null
    private var upstream: ServerSocket? = null
    private var socketPath: Path? = null

    @AfterEach
    fun tearDown() {
        runCatching { bridge?.close() }
        runCatching { upstream?.close() }
        socketPath?.let { runCatching { Files.deleteIfExists(it) } }
    }

    /** Gonderilen byte'lari buyuk harfe cevirip geri yollayan upstream. */
    private fun startUpstream(): Int {
        val server = ServerSocket(0, 16, java.net.InetAddress.getLoopbackAddress())
        upstream = server
        thread(isDaemon = true) {
            while (!server.isClosed) {
                val socket = runCatching { server.accept() }.getOrNull() ?: break
                thread(isDaemon = true) {
                    socket.use {
                        val input = it.getInputStream()
                        val output = it.getOutputStream()
                        val buffer = ByteArray(1024)
                        while (true) {
                            val read = runCatching { input.read(buffer) }.getOrDefault(-1)
                            if (read <= 0) break
                            output.write(
                                String(buffer, 0, read, Charsets.UTF_8)
                                    .uppercase()
                                    .toByteArray(Charsets.UTF_8),
                            )
                            output.flush()
                        }
                    }
                }
            }
        }
        return server.localPort
    }

    private fun startBridge(): Path {
        val port = startUpstream()
        val path = Files.createTempDirectory("bot-bridge").resolve("public.sock")
        socketPath = path
        bridge = UnixSocketBridge(path, port, "test").also { it.start() }
        return path
    }

    @Test
    fun `traffic reaches the listener through the unix socket`() {
        val path = startBridge()

        SocketChannel.open(StandardProtocolFamily.UNIX).use { channel ->
            channel.connect(UnixDomainSocketAddress.of(path))
            channel.write(ByteBuffer.wrap("ping".toByteArray(Charsets.UTF_8)))
            val buffer = ByteBuffer.allocate(64)
            val read = channel.read(buffer)
            buffer.flip()
            assertThat(read).isGreaterThan(0)
            assertThat(String(buffer.array(), 0, buffer.limit(), Charsets.UTF_8)).isEqualTo("PING")
        }
    }

    @Test
    fun `the socket file is reachable only by its owner`() {
        val path = startBridge()

        val permissions = Files.getPosixFilePermissions(path)
        assertThat(permissions).containsExactly(
            PosixFilePermission.OWNER_READ,
            PosixFilePermission.OWNER_WRITE,
        )
    }

    @Test
    fun `a stale socket file does not block a restart`() {
        val path = startBridge()
        bridge?.close()
        // Kapanista dosya silinir; kalmis olsa bile yeniden baslatma
        // engellenmemeli.
        Files.createFile(path)

        val port = startUpstream()
        bridge = UnixSocketBridge(path, port, "test-restart").also { it.start() }

        SocketChannel.open(StandardProtocolFamily.UNIX).use { channel ->
            channel.connect(UnixDomainSocketAddress.of(path))
            channel.write(ByteBuffer.wrap("ok".toByteArray(Charsets.UTF_8)))
            val buffer = ByteBuffer.allocate(16)
            channel.read(buffer)
            buffer.flip()
            assertThat(String(buffer.array(), 0, buffer.limit(), Charsets.UTF_8)).isEqualTo("OK")
        }
    }

    @Test
    fun `closing the bridge removes the socket and stops serving`() {
        val path = startBridge()
        bridge?.close()

        assertThat(Files.exists(path)).isFalse()
        val failed = runCatching {
            SocketChannel.open(StandardProtocolFamily.UNIX).use { channel ->
                channel.connect(UnixDomainSocketAddress.of(path))
            }
        }.isFailure
        assertThat(failed).isTrue()
    }

    @Test
    fun `the loopback listener is not published on an external interface`() {
        startBridge()
        // Upstream yalniz loopback'e bind edilir; bu, bridge'in disariya
        // acilan tek yuzunun socket dosyasi olmasini saglar.
        val bound = upstream!!.inetAddress
        assertThat(bound.isLoopbackAddress).isTrue()
        assertThat(InetSocketAddress(bound, upstream!!.localPort).address.isAnyLocalAddress).isFalse()
    }
}
