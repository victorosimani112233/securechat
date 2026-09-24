package com.securechat.signaling

import io.ktor.client.plugins.websocket.WebSockets as ClientWebSockets
import io.ktor.client.plugins.websocket.webSocketSession
import io.ktor.client.request.header
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import io.ktor.server.websocket.WebSockets
import io.ktor.server.websocket.webSocket
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue

class GroupJanusGatewayTest {
    private class Fixture {
        val group = UUID.randomUUID().toString()
        val user = UUID.randomUUID().toString()
        val peer = UUID.randomUUID().toString()
        val feeds = GroupJanusFeeds()
        init {
            GroupCallSessionStore.start(group, "call", user, "VIDEO", listOf(user, peer), "SFU",
                sfuRoomId = 42, janusWsUrl = "wss://signal.invalid/janus", mediaE2eeParticipants = setOf(user, peer))
        }
        fun call() = requireNotNull(GroupCallSessionStore.get(group))
        fun close() = GroupCallSessionStore.end(group)
        fun contract(): GroupJanusContract = GroupJanusContract(user, call(), feeds).also {
            it.request(json("""{"janus":"create","transaction":"create"}"""))
            it.response(json("""{"janus":"success","transaction":"create","data":{"id":1}}"""))
            attach(it, 10)
        }
    }

    @Test
    fun `same room publisher and subscriber succeed but foreign room or feed cannot be used`() {
        val f = Fixture()
        val other = Fixture()
        try {
            val c = f.contract()
            for (role in listOf("publisher", "subscriber")) {
                assertThrows(IllegalArgumentException::class.java) {
                    c.request(message("foreign-$role", 10, """{"request":"join","room":43,"ptype":"$role","feed":99}"""))
                }
            }
            val join = c.request(message("join", 10, """{"request":"join","room":42,"ptype":"publisher","display":"spoof"}"""))
            assertEquals(f.user, join["body"]!!.jsonObject["display"]!!.jsonPrimitive.content)
            c.response(json("""{"janus":"event","transaction":"join","session_id":1,"sender":10,
                "plugindata":{"data":{"room":42,"id":50,"publishers":[{"id":99,"display":"${f.peer}"}]}}}"""))
            attach(c, 11)
            f.feeds.register(other.call(), 100, other.user)
            for (feed in listOf(100, 101)) {
                assertThrows(IllegalArgumentException::class.java) {
                    c.request(message("foreign-feed-$feed", 11, """{"request":"join","room":42,"ptype":"subscriber","feed":$feed}"""))
                }
            }
            c.request(message("subscribe", 11, """{"request":"join","room":42,"ptype":"subscriber","feed":99}"""))
            c.response(json("""{"janus":"event","transaction":"subscribe","session_id":1,"sender":11,"plugindata":{"data":{"room":42}}}"""))
            val start = c.request(message("start", 11, """{"request":"start","room":42}""", """{"type":"answer","sdp":"v=0"}"""))
            assertTrue(start["jsep"]!!.jsonObject["e2ee"]!!.jsonPrimitive.boolean)
            GroupCallSessionStore.removeParticipant(f.group, f.peer)
            attach(c, 12)
            assertThrows(IllegalArgumentException::class.java) {
                c.request(message("removed-feed", 12, """{"request":"join","room":42,"ptype":"subscriber","feed":99}"""))
            }
        } finally { f.close(); other.close() }
    }

    @Test
    fun `foreign sessions handles plugin commands and plaintext negotiation fail closed`() {
        val f = Fixture()
        try {
            val c = f.contract()
            val forbidden = listOf(
                """{"janus":"keepalive","transaction":"x1","session_id":999}""",
                """{"janus":"detach","transaction":"x2","session_id":1,"handle_id":999}""",
                """{"janus":"attach","transaction":"x3","session_id":1,"plugin":"janus.plugin.recordplay"}""",
                """{"janus":"message","transaction":"x4","session_id":1,"handle_id":10,"body":{"request":"list"}}""",
                """{"janus":"message","transaction":"x5","session_id":1,"handle_id":10,"body":{"request":"create","room":42}}""",
                """{"janus":"keepalive","transaction":"x6","session_id":1,"apisecret":"attacker-value"}""",
            )
            for (frame in forbidden) assertThrows(IllegalArgumentException::class.java) { c.request(json(frame)) }
            c.request(message("join", 10, """{"request":"join","room":42,"ptype":"publisher"}"""))
            c.response(json("""{"janus":"event","transaction":"join","sender":10,"plugindata":{"data":{"room":42,"id":50}}}"""))
            assertThrows(IllegalArgumentException::class.java) {
                c.request(message("plaintext", 10, """{"request":"configure","audio":true}""",
                    """{"type":"offer","sdp":"v=0","e2ee":false}"""))
            }
            assertThrows(IllegalArgumentException::class.java) {
                c.request(message("record", 10, """{"request":"configure","record":true}""", """{"type":"offer","sdp":"v=0"}"""))
            }
            val publish = c.request(message("publish", 10, """{"request":"configure","audio":true,"video":true}""",
                """{"type":"offer","sdp":"v=0"}"""))
            assertTrue(publish["jsep"]!!.jsonObject["e2ee"]!!.jsonPrimitive.boolean)
            assertThrows(IllegalArgumentException::class.java) { c.response(json("""{"janus":"event","session_id":999}""")) }
            assertThrows(IllegalArgumentException::class.java) { c.response(json("""{"janus":"event","sender":999}""")) }
            assertThrows(IllegalArgumentException::class.java) { c.response(json("""{"janus":"event","sender":10,"plugindata":{"data":{"room":43}}}""")) }
        } finally { f.close() }
    }

    @Test
    fun `membership revocation replacement and missing encryption remove gateway authorization`() {
        val f = Fixture()
        try {
            val c = f.contract()
            GroupCallSessionStore.removeParticipant(f.group, f.user)
            assertFalse(c.authorized())
            assertThrows(IllegalArgumentException::class.java) { c.request(json("""{"janus":"keepalive","transaction":"k","session_id":1}""")) }
            GroupCallSessionStore.start(f.group, "call", f.user, "VIDEO", listOf(f.user), "SFU",
                sfuRoomId = 42, mediaE2eeParticipants = setOf(f.user))
            assertFalse(c.authorized(), "Replacement with same call and room IDs is a different instance")
            GroupCallSessionStore.start(f.group, "plain", f.user, "VIDEO", listOf(f.user), "SFU", sfuRoomId = 42)
            assertFalse(GroupJanusContract(f.user, f.call()).authorized())
        } finally { f.close() }
    }

    @Test
    fun `real gateway authenticates handshake injects secret internally and redacts errors`() = testApplication {
        val f = Fixture()
        val secret = "test-only-gateway-secret-never-production"
        val received = ConcurrentLinkedQueue<JsonObject>()
        var handleId = 200
        val upstream = embeddedServer(Netty, host = "127.0.0.1", port = 0) {
            install(WebSockets)
            routing { webSocket("/janus", protocol = "janus-protocol") {
                assertNull(call.request.headers["Authorization"], "User Bearer token must not reach Janus")
                for (frame in incoming) {
                    val request = json((frame as Frame.Text).readText())
                    received.add(request)
                    assertEquals(secret, request["apisecret"]!!.jsonPrimitive.content)
                    val transaction = request["transaction"]!!.jsonPrimitive.content
                    val response = when (request["janus"]!!.jsonPrimitive.content) {
                        "create" -> """{"janus":"success","transaction":"$transaction","data":{"id":101},"apisecret":"$secret"}"""
                        "attach" -> """{"janus":"success","transaction":"$transaction","session_id":101,"data":{"id":${++handleId}}}"""
                        "message" -> {
                            send(Frame.Text("""{"janus":"ack","transaction":"$transaction","session_id":101}"""))
                            val body = request["body"]!!.jsonObject
                            val requestHandle = request["handle_id"]!!.jsonPrimitive.long
                            when (body["request"]!!.jsonPrimitive.content) {
                                "join" -> """{"janus":"event","transaction":"$transaction","session_id":101,"sender":$requestHandle,
                                  "plugindata":{"data":{"room":42,"id":50,"publishers":[{"id":99,"display":"${f.peer}"}]}}}"""
                                "start" -> """{"janus":"event","transaction":"$transaction","session_id":101,"sender":$requestHandle,"plugindata":{"data":{"room":42,"started":"ok"}}}"""
                                else -> """{"janus":"event","transaction":"$transaction","session_id":101,"sender":$requestHandle,
                                  "plugindata":{"data":{"error_code":499,"error":"upstream $secret internal details","admin_key":"$secret"}}}"""
                            }
                        }
                        else -> """{"janus":"success","transaction":"$transaction","session_id":101}"""
                    }
                    send(Frame.Text(response))
                }
            } }
        }.start(wait = false)
        val port = upstream.resolvedConnectors().first().port
        application {
            install(WebSockets)
            configureGroupJanusGateway(enabled = { true }, verifyToken = { if (it == "valid") f.user else null },
                upstreamUrl = { "ws://127.0.0.1:$port/janus" }, apiSecret = { secret }, allowRequest = { _, _ -> true })
        }
        val client = createClient { install(ClientWebSockets) }
        try {
            for ((url, credential) in listOf("/janus" to "invalid", "/janus?token=valid" to "valid", "/janus" to null)) {
                val denied = client.webSocketSession(url) {
                    header("Sec-WebSocket-Protocol", "janus-protocol")
                    credential?.let { header("Authorization", "Bearer $it") }
                }
                assertNotNull(withTimeout(3000) { denied.closeReason.await() })
            }
            assertTrue(received.isEmpty())
            val socket = client.webSocketSession("/janus") {
                header("Authorization", "Bearer valid"); header("Sec-WebSocket-Protocol", "janus-protocol")
            }
            socket.send(Frame.Text("""{"janus":"create","transaction":"c"}"""))
            val created = socket.nextJson()
            assertEquals(101, created["data"]!!.jsonObject["id"]!!.jsonPrimitive.int)
            assertNull(created["apisecret"])
            socket.send(Frame.Text("""{"janus":"attach","transaction":"a","session_id":101,"plugin":"janus.plugin.videoroom"}"""))
            assertEquals(201, socket.nextJson()["data"]!!.jsonObject["id"]!!.jsonPrimitive.int)
            socket.send(Frame.Text("""{"janus":"message","transaction":"j","session_id":101,"handle_id":201,"body":{"request":"join","room":42,"ptype":"publisher"}}"""))
            assertEquals("ack", socket.nextJson()["janus"]!!.jsonPrimitive.content)
            assertEquals(42, socket.nextJson()["plugindata"]!!.jsonObject["data"]!!.jsonObject["room"]!!.jsonPrimitive.int)
            socket.send(Frame.Text("""{"janus":"message","transaction":"p","session_id":101,"handle_id":201,
              "body":{"request":"configure","audio":true,"video":true},"jsep":{"type":"offer","sdp":"v=0"}}"""))
            assertEquals("ack", socket.nextJson()["janus"]!!.jsonPrimitive.content)
            val error = socket.nextJson()["plugindata"]!!.jsonObject["data"]!!.jsonObject
            assertEquals("Janus request failed", error["error"]!!.jsonPrimitive.content)
            assertNull(error["admin_key"])
            socket.send(Frame.Text("""{"janus":"attach","transaction":"as","session_id":101,"plugin":"janus.plugin.videoroom"}"""))
            assertEquals(202, socket.nextJson()["data"]!!.jsonObject["id"]!!.jsonPrimitive.int)
            socket.send(Frame.Text("""{"janus":"message","transaction":"s","session_id":101,"handle_id":202,
              "body":{"request":"join","room":42,"ptype":"subscriber","feed":99}}"""))
            socket.nextJson(); socket.nextJson()
            socket.send(Frame.Text("""{"janus":"message","transaction":"start","session_id":101,"handle_id":202,
              "body":{"request":"start","room":42},"jsep":{"type":"answer","sdp":"v=0"}}"""))
            socket.nextJson()
            assertEquals("ok", socket.nextJson()["plugindata"]!!.jsonObject["data"]!!.jsonObject["started"]!!.jsonPrimitive.content)
            val negotiations = received.filter { it["jsep"] != null }
            assertEquals(2, negotiations.size)
            assertTrue(negotiations.all { it["jsep"]!!.jsonObject["e2ee"]!!.jsonPrimitive.boolean })
            GroupCallSessionStore.removeParticipant(f.group, f.user)
            assertNotNull(withTimeout(3500) { socket.closeReason.await() })
            withTimeout(3000) { while (received.none { it["janus"]?.jsonPrimitive?.content == "destroy" }) delay(10) }
        } finally {
            f.close()
            upstream.stop(100, 1000)
        }
    }

    @Test
    fun `revoked bearer is rejected before the next request reaches Janus`() = checkRevocation(sendAfterRevocation = true)

    @Test
    fun `idle gateway revalidates bearer and closes upstream after logout`() = checkRevocation(sendAfterRevocation = false)

    private fun checkRevocation(sendAfterRevocation: Boolean) = testApplication {
        val f = Fixture()
        val valid = java.util.concurrent.atomic.AtomicBoolean(true)
        val received = ConcurrentLinkedQueue<JsonObject>()
        val upstreamClosed = CompletableDeferred<Unit>()
        val upstream = embeddedServer(Netty, host = "127.0.0.1", port = 0) {
            install(WebSockets)
            routing { webSocket("/janus", protocol = "janus-protocol") {
                try {
                    for (frame in incoming) {
                        val request = json((frame as Frame.Text).readText())
                        received.add(request)
                        if (request["janus"]?.jsonPrimitive?.content == "create") {
                            send(Frame.Text("""{"janus":"success","transaction":${request["transaction"]},"data":{"id":101}}"""))
                        }
                    }
                } finally { upstreamClosed.complete(Unit) }
            } }
        }.start(wait = false)
        val port = upstream.resolvedConnectors().first().port
        application {
            install(WebSockets)
            configureGroupJanusGateway(enabled = { true }, verifyToken = { if (valid.get()) f.user else null },
                upstreamUrl = { "ws://127.0.0.1:$port/janus" }, apiSecret = { "test-only-secret" }, allowRequest = { _, _ -> true })
        }
        try {
            val socket = createClient { install(ClientWebSockets) }.webSocketSession("/janus") {
                header("Authorization", "Bearer test"); header("Sec-WebSocket-Protocol", "janus-protocol")
            }
            socket.send(Frame.Text("""{"janus":"create","transaction":"c"}"""))
            socket.nextJson()
            valid.set(false)
            if (sendAfterRevocation) {
                socket.send(Frame.Text("""{"janus":"keepalive","transaction":"revoked","session_id":101}"""))
            }
            assertNotNull(withTimeout(3500) { socket.closeReason.await() })
            withTimeout(3500) { upstreamClosed.await() }
            assertFalse(received.any { it["transaction"]?.jsonPrimitive?.content == "revoked" })
            assertTrue(received.any { it["janus"]?.jsonPrimitive?.content == "destroy" })
        } finally {
            f.close()
            upstream.stop(100, 1000)
        }
    }

    @Test
    fun `SFU disabled or unencrypted membership opens no upstream connection`() = testApplication {
        val f = Fixture()
        application {
            install(WebSockets)
            configureGroupJanusGateway(enabled = { false }, verifyToken = { f.user },
                upstreamUrl = { error("SFU off must not connect") }, apiSecret = { error("SFU off must not read secret") })
        }
        try {
            val socket = createClient { install(ClientWebSockets) }.webSocketSession("/janus") {
                header("Authorization", "Bearer test"); header("Sec-WebSocket-Protocol", "janus-protocol")
            }
            assertNotNull(withTimeout(3000) { socket.closeReason.await() })
        } finally { f.close() }
    }

    companion object {
        private fun json(raw: String) = Json.parseToJsonElement(raw).jsonObject
        private fun attach(contract: GroupJanusContract, id: Long) {
            contract.request(json("""{"janus":"attach","transaction":"a$id","session_id":1,"plugin":"janus.plugin.videoroom"}"""))
            contract.response(json("""{"janus":"success","transaction":"a$id","session_id":1,"data":{"id":$id}}"""))
        }
        private fun message(tx: String, handle: Long, body: String, jsep: String? = null) = buildJsonObject {
            put("janus", "message"); put("transaction", tx); put("session_id", 1); put("handle_id", handle)
            put("body", json(body)); jsep?.let { put("jsep", json(it)) }
        }
        private suspend fun WebSocketSession.nextJson(): JsonObject = withTimeout(3000) {
            json((incoming.receive() as Frame.Text).readText())
        }
    }
}
