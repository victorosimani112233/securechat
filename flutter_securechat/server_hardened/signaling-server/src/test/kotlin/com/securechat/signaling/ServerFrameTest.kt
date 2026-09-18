package com.securechat.signaling

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Sunucu uretimi cerceveler.
 *
 * Bu cerceveler daha once string interpolation ile kuruluyordu. Icinde
 * tirnak, ters bolu ya da suslu parantez tasiyan bir `callId`/`groupId`
 * cerceveyi bozabilir ya da istemcinin okudugu bir alani ezebilirdi:
 * degeri istemci belirledigi icin bu bir enjeksiyon yuzeyiydi.
 */
class ServerFrameTest {

    private fun parse(frame: String): JsonObject =
        Json.parseToJsonElement(frame) as JsonObject

    @Test
    fun `every frame carries the server identity and a numeric timestamp`() {
        val frame = parse(serverFrame("group_call_member_left", "recipient-1"))

        assertEquals("group_call_member_left", frame["type"]?.jsonPrimitive?.content)
        assertEquals("server", frame["senderId"]?.jsonPrimitive?.content)
        assertEquals("recipient-1", frame["recipientId"]?.jsonPrimitive?.content)
        // Zaman damgasi sayi olarak yazilmali; string'e dusen bir alan
        // istemcide sessiz parse hatasi olurdu.
        assertTrue(frame["timestamp"]?.jsonPrimitive?.longOrNullSafe() != null)
    }

    @Test
    fun `a quoted call id cannot break out of its field`() {
        val hostile = """abc","senderId":"victim","injected":"yes"""

        val frame = parse(
            serverFrame("group_call_status_response", "recipient-1") {
                put("callId", hostile)
            },
        )

        assertEquals(hostile, frame["callId"]?.jsonPrimitive?.content)
        // Enjekte edilmeye calisilan alanlar olusmamali, senderId ezilmemeli.
        assertEquals("server", frame["senderId"]?.jsonPrimitive?.content)
        assertNull(frame["injected"])
    }

    @Test
    fun `backslashes braces and newlines survive as data`() {
        val hostile = "a\\b\"c{d}e\nf\tg"

        val frame = parse(
            serverFrame("group_call_member_left", "recipient-1") {
                put("groupId", hostile)
            },
        )

        assertEquals(hostile, frame["groupId"]?.jsonPrimitive?.content)
    }

    @Test
    fun `a hostile recipient id is still only a value`() {
        val hostile = """x"},{"type":"admin_command","payload":"wipe"""

        val frame = parse(serverFrame("group_call_member_left", hostile))

        assertEquals(hostile, frame["recipientId"]?.jsonPrimitive?.content)
        assertEquals("group_call_member_left", frame["type"]?.jsonPrimitive?.content)
        // Tek bir nesne olmali; ikinci bir nesne enjekte edilememeli.
        assertEquals(4, frame.keys.size)
    }

    @Test
    fun `unicode and multi byte content round trips`() {
        val value = "grup: çağrı — 群組 🎉"

        val frame = parse(
            serverFrame("group_call_status_response", "recipient-1") {
                put("groupId", value)
            },
        )

        assertEquals(value, frame["groupId"]?.jsonPrimitive?.content)
    }

    @Test
    fun `booleans stay booleans instead of becoming strings`() {
        val frame = parse(
            serverFrame("group_call_status_response", "recipient-1") {
                put("isActive", false)
            },
        )

        assertEquals("false", frame["isActive"]?.jsonPrimitive?.content)
        assertTrue(frame["isActive"]!!.jsonPrimitive.isString.not())
    }

    private fun kotlinx.serialization.json.JsonPrimitive.longOrNullSafe(): Long? =
        content.toLongOrNull()
}
