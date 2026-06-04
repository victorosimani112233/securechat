package com.securechat.botapi.send

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.auth.AuthenticatedClient
import org.junit.jupiter.api.Test

class AllowListCheckerTest {

    private fun client(allowList: List<String>) = AuthenticatedClient(
        clientId = "abc",
        kid = "k_test",
        name = "test",
        publicKey = ByteArray(32),
        allowList = allowList,
        ratePerHour = 50,
        perRecipientPerDay = 500
    )

    @Test
    fun `allows exact user match`() {
        val c = client(listOf("user:u1", "user:u2"))
        assertThat(AllowListChecker.isAllowed(c, "user:u1")).isTrue()
        assertThat(AllowListChecker.isAllowed(c, "user:u2")).isTrue()
    }

    @Test
    fun `denies user not in list`() {
        val c = client(listOf("user:u1"))
        assertThat(AllowListChecker.isAllowed(c, "user:u9")).isFalse()
    }

    @Test
    fun `allows group when listed`() {
        val c = client(listOf("group:g1"))
        assertThat(AllowListChecker.isAllowed(c, "group:g1")).isTrue()
    }

    @Test
    fun `empty allow list denies everything`() {
        val c = client(emptyList())
        assertThat(AllowListChecker.isAllowed(c, "user:any")).isFalse()
        assertThat(AllowListChecker.isAllowed(c, "group:any")).isFalse()
    }

    @Test
    fun `blank recipient rejected`() {
        val c = client(listOf("user:u1"))
        assertThat(AllowListChecker.isAllowed(c, "")).isFalse()
    }

    @Test
    fun `user listed does not match group with same name`() {
        val c = client(listOf("user:foo"))
        assertThat(AllowListChecker.isAllowed(c, "group:foo")).isFalse()
    }
}
