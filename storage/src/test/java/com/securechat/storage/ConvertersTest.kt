package com.securechat.storage

import com.google.common.truth.Truth.assertThat
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.model.TrustLevel
import org.junit.Before
import org.junit.Test

/**
 * Converters sinifi icin unit testler.
 * Tum enum <-> String donusumlerin dogru calistigini dogrular.
 */
class ConvertersTest {

    private lateinit var converters: Converters

    @Before
    fun setup() {
        converters = Converters()
    }

    // --- MessageContentType ---

    @Test
    fun `fromMessageContentType TEXT returns TEXT string`() {
        assertThat(converters.fromMessageContentType(MessageContentType.TEXT)).isEqualTo("TEXT")
    }

    @Test
    fun `toMessageContentType TEXT returns TEXT enum`() {
        assertThat(converters.toMessageContentType("TEXT")).isEqualTo(MessageContentType.TEXT)
    }

    @Test
    fun `MessageContentType round-trip for all values`() {
        MessageContentType.values().forEach { type ->
            val str = converters.fromMessageContentType(type)
            val back = converters.toMessageContentType(str)
            assertThat(back).isEqualTo(type)
        }
    }

    // --- MessageStatus ---

    @Test
    fun `fromMessageStatus SENDING returns SENDING string`() {
        assertThat(converters.fromMessageStatus(MessageStatus.SENDING)).isEqualTo("SENDING")
    }

    @Test
    fun `toMessageStatus DELIVERED returns DELIVERED enum`() {
        assertThat(converters.toMessageStatus("DELIVERED")).isEqualTo(MessageStatus.DELIVERED)
    }

    @Test
    fun `MessageStatus round-trip for all values`() {
        MessageStatus.values().forEach { status ->
            val str = converters.fromMessageStatus(status)
            val back = converters.toMessageStatus(str)
            assertThat(back).isEqualTo(status)
        }
    }

    // --- TrustLevel ---

    @Test
    fun `fromTrustLevel UNTRUSTED returns UNTRUSTED string`() {
        assertThat(converters.fromTrustLevel(TrustLevel.UNTRUSTED)).isEqualTo("UNTRUSTED")
    }

    @Test
    fun `toTrustLevel TRUSTED_VERIFIED returns TRUSTED_VERIFIED enum`() {
        assertThat(converters.toTrustLevel("TRUSTED_VERIFIED")).isEqualTo(TrustLevel.TRUSTED_VERIFIED)
    }

    @Test
    fun `TrustLevel round-trip for all values`() {
        TrustLevel.values().forEach { level ->
            val str = converters.fromTrustLevel(level)
            val back = converters.toTrustLevel(str)
            assertThat(back).isEqualTo(level)
        }
    }

    // --- Hata durumlari ---

    @Test(expected = IllegalArgumentException::class)
    fun `toMessageContentType with invalid value throws exception`() {
        converters.toMessageContentType("INVALID_TYPE")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `toMessageStatus with invalid value throws exception`() {
        converters.toMessageStatus("INVALID_STATUS")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `toTrustLevel with invalid value throws exception`() {
        converters.toTrustLevel("INVALID_LEVEL")
    }
}
