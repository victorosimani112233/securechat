package com.securechat.network

import com.google.common.truth.Truth.assertThat
import com.securechat.network.model.CallAction
import com.securechat.network.model.CallType
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Before
import org.junit.Test

/**
 * SignalMessage sealed class'inin serialization/deserialization testleri.
 * Tum alt tiplerin dogru JSON formatinda serialize/deserialize edildigini dogrular.
 */
class SignalMessageTest {

    private lateinit var json: Json

    @Before
    fun setUp() {
        json = Json {
            ignoreUnknownKeys = true
            classDiscriminator = "type"
        }
    }

    @Test
    fun `SdpOffer serialization roundtrip`() {
        val original = SignalMessage.SdpOffer(
            senderId = "alice",
            recipientId = "bob",
            timestamp = 1000L,
            sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1",
            callType = CallType.VIDEO
        )

        val serialized = json.encodeToString<SignalMessage>(original)
        val deserialized = json.decodeFromString<SignalMessage>(serialized)

        assertThat(deserialized).isEqualTo(original)
        assertThat(deserialized).isInstanceOf(SignalMessage.SdpOffer::class.java)
        assertThat(serialized).contains("\"type\":\"sdp_offer\"")
    }

    @Test
    fun `SdpAnswer serialization roundtrip`() {
        val original = SignalMessage.SdpAnswer(
            senderId = "bob",
            recipientId = "alice",
            timestamp = 2000L,
            sdp = "v=0\r\no=- 654321 2 IN IP4 127.0.0.1"
        )

        val serialized = json.encodeToString<SignalMessage>(original)
        val deserialized = json.decodeFromString<SignalMessage>(serialized)

        assertThat(deserialized).isEqualTo(original)
        assertThat(deserialized).isInstanceOf(SignalMessage.SdpAnswer::class.java)
        assertThat(serialized).contains("\"type\":\"sdp_answer\"")
    }

    @Test
    fun `IceCandidate serialization roundtrip`() {
        val original = SignalMessage.IceCandidate(
            senderId = "alice",
            recipientId = "bob",
            timestamp = 3000L,
            candidate = "candidate:1 1 udp 2113937151 192.168.1.1 12345 typ host",
            sdpMid = "0",
            sdpMLineIndex = 0
        )

        val serialized = json.encodeToString<SignalMessage>(original)
        val deserialized = json.decodeFromString<SignalMessage>(serialized)

        assertThat(deserialized).isEqualTo(original)
        assertThat(deserialized).isInstanceOf(SignalMessage.IceCandidate::class.java)
        assertThat(serialized).contains("\"type\":\"ice_candidate\"")
    }

    @Test
    fun `IceCandidate with null sdpMid serialization roundtrip`() {
        val original = SignalMessage.IceCandidate(
            senderId = "alice",
            recipientId = "bob",
            timestamp = 3000L,
            candidate = "candidate:1 1 udp 2113937151 192.168.1.1 12345 typ host",
            sdpMid = null,
            sdpMLineIndex = 0
        )

        val serialized = json.encodeToString<SignalMessage>(original)
        val deserialized = json.decodeFromString<SignalMessage>(serialized)

        assertThat(deserialized).isEqualTo(original)
        val iceCandidate = deserialized as SignalMessage.IceCandidate
        assertThat(iceCandidate.sdpMid).isNull()
    }

    @Test
    fun `EncryptedMessage serialization roundtrip`() {
        val original = SignalMessage.EncryptedMessage(
            senderId = "alice",
            recipientId = "bob",
            timestamp = 4000L,
            envelope = "SGVsbG8gV29ybGQ="
        )

        val serialized = json.encodeToString<SignalMessage>(original)
        val deserialized = json.decodeFromString<SignalMessage>(serialized)

        assertThat(deserialized).isEqualTo(original)
        assertThat(deserialized).isInstanceOf(SignalMessage.EncryptedMessage::class.java)
        assertThat(serialized).contains("\"type\":\"encrypted_message\"")
    }

    @Test
    fun `PreKeyBundleMessage serialization roundtrip`() {
        val original = SignalMessage.PreKeyBundleMessage(
            senderId = "alice",
            recipientId = "bob",
            timestamp = 5000L,
            bundle = "eyJpZGVudGl0eUtleSI6Ii4uLiJ9"
        )

        val serialized = json.encodeToString<SignalMessage>(original)
        val deserialized = json.decodeFromString<SignalMessage>(serialized)

        assertThat(deserialized).isEqualTo(original)
        assertThat(deserialized).isInstanceOf(SignalMessage.PreKeyBundleMessage::class.java)
        assertThat(serialized).contains("\"type\":\"prekey_bundle\"")
    }

    @Test
    fun `CallControl serialization roundtrip for all actions`() {
        CallAction.entries.forEach { action ->
            val original = SignalMessage.CallControl(
                senderId = "alice",
                recipientId = "bob",
                timestamp = 6000L,
                action = action
            )

            val serialized = json.encodeToString<SignalMessage>(original)
            val deserialized = json.decodeFromString<SignalMessage>(serialized)

            assertThat(deserialized).isEqualTo(original)
            assertThat(deserialized).isInstanceOf(SignalMessage.CallControl::class.java)
            assertThat(serialized).contains("\"type\":\"call_control\"")
        }
    }

    @Test
    fun `SdpOffer with VOICE call type`() {
        val original = SignalMessage.SdpOffer(
            senderId = "alice",
            recipientId = "bob",
            timestamp = 7000L,
            sdp = "v=0",
            callType = CallType.VOICE
        )

        val serialized = json.encodeToString<SignalMessage>(original)
        val deserialized = json.decodeFromString<SignalMessage>(serialized) as SignalMessage.SdpOffer

        assertThat(deserialized.callType).isEqualTo(CallType.VOICE)
    }

    @Test
    fun `deserialization preserves all fields for IceCandidate`() {
        val jsonStr = """
            {
                "type": "ice_candidate",
                "senderId": "peer1",
                "recipientId": "peer2",
                "timestamp": 999,
                "candidate": "candidate:0 1 UDP 2122194687 192.168.0.1 50000 typ host",
                "sdpMid": "audio",
                "sdpMLineIndex": 1
            }
        """.trimIndent()

        val deserialized = json.decodeFromString<SignalMessage>(jsonStr)
        assertThat(deserialized).isInstanceOf(SignalMessage.IceCandidate::class.java)

        val ice = deserialized as SignalMessage.IceCandidate
        assertThat(ice.senderId).isEqualTo("peer1")
        assertThat(ice.recipientId).isEqualTo("peer2")
        assertThat(ice.timestamp).isEqualTo(999L)
        assertThat(ice.candidate).contains("candidate:0")
        assertThat(ice.sdpMid).isEqualTo("audio")
        assertThat(ice.sdpMLineIndex).isEqualTo(1)
    }

    @Test
    fun `deserialization ignores unknown keys`() {
        val jsonStr = """
            {
                "type": "sdp_answer",
                "senderId": "bob",
                "recipientId": "alice",
                "timestamp": 100,
                "sdp": "v=0",
                "unknownField": "should be ignored"
            }
        """.trimIndent()

        val deserialized = json.decodeFromString<SignalMessage>(jsonStr)
        assertThat(deserialized).isInstanceOf(SignalMessage.SdpAnswer::class.java)
        assertThat((deserialized as SignalMessage.SdpAnswer).sdp).isEqualTo("v=0")
    }

    @Test
    fun `serialized JSON contains type discriminator`() {
        val messages = listOf(
            SignalMessage.SdpOffer("a", "b", 0, "sdp", CallType.VOICE) to "sdp_offer",
            SignalMessage.SdpAnswer("a", "b", 0, "sdp") to "sdp_answer",
            SignalMessage.IceCandidate("a", "b", 0, "c", "0", 0) to "ice_candidate",
            SignalMessage.EncryptedMessage("a", "b", 0, "e") to "encrypted_message",
            SignalMessage.PreKeyBundleMessage("a", "b", 0, "pk") to "prekey_bundle",
            SignalMessage.CallControl("a", "b", 0, CallAction.HANGUP) to "call_control"
        )

        messages.forEach { (message, expectedType) ->
            val serialized = json.encodeToString<SignalMessage>(message)
            assertThat(serialized).contains("\"type\":\"$expectedType\"")
        }
    }
}
