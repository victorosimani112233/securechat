package com.securechat.botapi.auth

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test

class BodyHashValidatorTest {

    @Test
    fun `computeBodyHash deterministic for same body`() {
        val body = """{"foo":"bar"}""".toByteArray()
        val h1 = BodyHashValidator.computeBodyHash(body)
        val h2 = BodyHashValidator.computeBodyHash(body)
        assertThat(h1).isEqualTo(h2)
        assertThat(h1).isNotEmpty()
    }

    @Test
    fun `computeBodyHash different for different bodies`() {
        val h1 = BodyHashValidator.computeBodyHash("a".toByteArray())
        val h2 = BodyHashValidator.computeBodyHash("b".toByteArray())
        assertThat(h1).isNotEqualTo(h2)
    }

    @Test
    fun `check passes with matching hash`() {
        val body = """{"x":1}""".toByteArray()
        val claim = BodyHashValidator.computeBodyHash(body)
        assertThat(BodyHashValidator.check(claim, body)).isTrue()
    }

    @Test
    fun `check fails with tampered body`() {
        val original = """{"x":1}""".toByteArray()
        val tampered = """{"x":2}""".toByteArray()
        val claim = BodyHashValidator.computeBodyHash(original)
        assertThat(BodyHashValidator.check(claim, tampered)).isFalse()
    }

    @Test
    fun `check fails with empty claim`() {
        val body = "hello".toByteArray()
        assertThat(BodyHashValidator.check("", body)).isFalse()
    }
}
