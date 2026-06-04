package com.securechat.botadmin

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.newsclub.net.unix.AFUNIXSocket
import org.newsclub.net.unix.AFUNIXSocketAddress
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.time.Duration
import javax.net.SocketFactory

/**
 * Admin endpoint'lerine HTTP istegi yapan client.
 * Hedef: TCP (localhost:8092) veya Unix domain socket
 * (env BOT_ADMIN_SOCKET, default /var/run/securechat/bot-admin.sock).
 *
 * BOT_ADMIN_TOKEN env'i her istege X-Admin-Token header'i olarak eklenir.
 */
class AdminClient(
    private val baseUrl: String,
    private val adminToken: String,
    private val unixSocketPath: String? = null
) {
    private val client: OkHttpClient = if (unixSocketPath != null) {
        // Unix domain socket factory (junixsocket)
        val socketFactory = object : SocketFactory() {
            override fun createSocket(): Socket {
                val socket = AFUNIXSocket.newInstance()
                socket.connect(AFUNIXSocketAddress.of(File(unixSocketPath)))
                return socket
            }
            override fun createSocket(host: String, port: Int): Socket = createSocket()
            override fun createSocket(host: String, port: Int, localHost: java.net.InetAddress, localPort: Int): Socket = createSocket()
            override fun createSocket(host: java.net.InetAddress, port: Int): Socket = createSocket()
            override fun createSocket(address: java.net.InetAddress, port: Int, localAddress: java.net.InetAddress, localPort: Int): Socket = createSocket()
        }
        OkHttpClient.Builder()
            .socketFactory(socketFactory)
            .callTimeout(Duration.ofSeconds(10))
            .build()
    } else {
        OkHttpClient.Builder()
            .callTimeout(Duration.ofSeconds(10))
            .build()
    }

    fun get(path: String): Response {
        val req = Request.Builder()
            .url("$baseUrl$path")
            .header("X-Admin-Token", adminToken)
            .get()
            .build()
        return execute(req)
    }

    fun post(path: String, jsonBody: String): Response {
        val req = Request.Builder()
            .url("$baseUrl$path")
            .header("X-Admin-Token", adminToken)
            .post(jsonBody.toRequestBody("application/json".toMediaType()))
            .build()
        return execute(req)
    }

    fun delete(path: String): Response {
        val req = Request.Builder()
            .url("$baseUrl$path")
            .header("X-Admin-Token", adminToken)
            .delete()
            .build()
        return execute(req)
    }

    private fun execute(req: Request): Response {
        client.newCall(req).execute().use { resp ->
            return Response(resp.code, resp.body?.string() ?: "")
        }
    }

    data class Response(val code: Int, val body: String) {
        val isOk: Boolean get() = code in 200..299
    }
}

/** Env / arg'lardan AdminClient olustur. */
fun buildAdminClient(): AdminClient {
    val token = System.getenv("BOT_ADMIN_TOKEN")
        ?: error("BOT_ADMIN_TOKEN env zorunlu")
    val sockPath = System.getenv("BOT_ADMIN_SOCKET")
    return if (!sockPath.isNullOrBlank() && File(sockPath).exists()) {
        // Unix socket — host ve port okhttp icin dummy, baglanti socketFactory uzerinden
        AdminClient("http://localhost", token, unixSocketPath = sockPath)
    } else {
        val url = System.getenv("BOT_ADMIN_URL") ?: "http://127.0.0.1:8092"
        AdminClient(url, token)
    }
}
