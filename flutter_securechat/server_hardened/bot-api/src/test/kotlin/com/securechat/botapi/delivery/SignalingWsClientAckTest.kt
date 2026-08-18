package com.securechat.botapi.delivery

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test

class SignalingWsClientAckTest {

    @Test
    fun `only a bounded structured server ack yields a message id`() {
        assertThat(
            SignalingWsClient.parseMessageAck(
                """{"messageId":"m-1","type":"message_ack"}""",
            ),
        ).isEqualTo("m-1")
        assertThat(
            SignalingWsClient.parseMessageAck(
                """{"type":"encrypted_message","messageId":"m-1"}""",
            ),
        ).isNull()
        assertThat(SignalingWsClient.parseMessageAck("not-json")).isNull()
        assertThat(
            SignalingWsClient.parseMessageAck(
                """{"type":"message_ack","messageId":"${"x".repeat(129)}"}""",
            ),
        ).isNull()
    }
}
