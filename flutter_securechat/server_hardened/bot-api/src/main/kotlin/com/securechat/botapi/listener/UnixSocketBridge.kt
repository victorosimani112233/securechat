package com.securechat.botapi.listener

import java.io.IOException
import java.net.InetSocketAddress
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.ServerSocketChannel
import java.nio.channels.SocketChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.util.concurrent.atomic.AtomicBoolean
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("UnixSocketBridge")

/**
 * Bot public/admin yuzunu gercek bir Unix domain socket uzerinden acar.
 *
 * Onceki durumda iki listener yalniz container ici `127.0.0.1` TCP'sine
 * bind oluyordu ve compose ne port ne socket mount sagliyordu: yuzeyler
 * container disindan hic erisilemiyordu. Bu bir sertlestirme tercihi degil,
 * deployment islev bosluguydu.
 *
 * Socket dosyasi yalniz sahibi tarafindan okunup yazilabilir (0600). Host
 * tarafinda yetkilendirme dosya sahipligi ve izinleriyle, uygulama
 * seviyesinde ise admin token ile yapilir; ikisi birbirinin yerine gecmez.
 *
 * Ktor'un Netty motoru inet olmayan adreslere bind edemedigi icin yonlendirme
 * ayni process icinde yapilir: socket'ten gelen baglanti loopback listener'a
 * baglanir ve byte'lar iki yonlu aktarilir. Boylece ek bir container veya
 * native transport bagimliligi gerekmez.
 */
class UnixSocketBridge(
    private val socketPath: Path,
    private val targetPort: Int,
    private val name: String,
) : AutoCloseable {

    private val running = AtomicBoolean(false)
    private var serverChannel: ServerSocketChannel? = null
    private var acceptThread: Thread? = null

    fun start() {
        check(running.compareAndSet(false, true)) { "$name bridge zaten calisiyor" }
        socketPath.parent?.let { Files.createDirectories(it) }
        // Onceki calismadan kalan dosya bind'i engeller.
        Files.deleteIfExists(socketPath)

        val channel = ServerSocketChannel.open(StandardProtocolFamily.UNIX)
        channel.bind(UnixDomainSocketAddress.of(socketPath))
        Files.setPosixFilePermissions(socketPath, PosixFilePermissions.fromString("rw-------"))
        serverChannel = channel

        acceptThread = Thread({ acceptLoop(channel) }, "unix-bridge-$name").apply {
            isDaemon = true
            start()
        }
        log.info("[Bridge] {} Unix socket hazir: {}", name, socketPath)
    }

    private fun acceptLoop(channel: ServerSocketChannel) {
        while (running.get()) {
            val client = try {
                channel.accept()
            } catch (_: IOException) {
                if (running.get()) log.warn("[Bridge] {} accept hatasi", name)
                null
            } ?: continue
            Thread({ bridgeConnection(client) }, "unix-bridge-$name-conn").apply {
                isDaemon = true
                start()
            }
        }
    }

    private fun bridgeConnection(client: SocketChannel) {
        val upstream = try {
            SocketChannel.open(InetSocketAddress("127.0.0.1", targetPort))
        } catch (_: IOException) {
            log.warn("[Bridge] {} upstream baglanamadi", name)
            runCatching { client.close() }
            return
        }
        val pump = Thread({ transfer(client, upstream) }, "unix-bridge-$name-up").apply {
            isDaemon = true
            start()
        }
        transfer(upstream, client)
        pump.join(CONNECTION_DRAIN_MILLIS)
        runCatching { client.close() }
        runCatching { upstream.close() }
    }

    private fun transfer(from: SocketChannel, to: SocketChannel) {
        val buffer = ByteBuffer.allocate(BUFFER_BYTES)
        try {
            while (true) {
                buffer.clear()
                if (from.read(buffer) < 0) break
                buffer.flip()
                while (buffer.hasRemaining()) to.write(buffer)
            }
        } catch (_: IOException) {
            // Karsi taraf kapandi; baglanti sonlandirilir.
        } finally {
            runCatching { to.shutdownOutput() }
        }
    }

    override fun close() {
        if (!running.compareAndSet(true, false)) return
        runCatching { serverChannel?.close() }
        acceptThread?.join(CONNECTION_DRAIN_MILLIS)
        runCatching { Files.deleteIfExists(socketPath) }
        log.info("[Bridge] {} kapatildi", name)
    }

    private companion object {
        const val BUFFER_BYTES = 16 * 1024
        const val CONNECTION_DRAIN_MILLIS = 2_000L
    }
}
