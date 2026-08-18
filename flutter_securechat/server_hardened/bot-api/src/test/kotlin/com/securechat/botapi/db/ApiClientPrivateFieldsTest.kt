package com.securechat.botapi.db

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class ApiClientPrivateFieldsTest {
    @BeforeAll
    fun setUp() {
        BotApiConfig.botMasterKey = ByteArray(32) { (it + 17).toByte() }
    }

    @Test
    fun `name and allow-list are randomized and kid bound`() {
        val kid = "k_private"
        val name = "Finance automation"
        val allowList = listOf(
            "user:123e4567-e89b-42d3-a456-426614174000",
            "group:private-group-id"
        )

        val sealedName = ApiClientPrivateFields.sealName(kid, name)
        val sealedAllowList = ApiClientPrivateFields.sealAllowList(kid, allowList)

        assertThat(sealedName).doesNotContain(name)
        assertThat(sealedAllowList).doesNotContain("private-group-id")
        assertThat(ApiClientPrivateFields.openName(kid, sealedName)).isEqualTo(name)
        assertThat(ApiClientPrivateFields.openAllowList(kid, sealedAllowList))
            .containsExactlyElementsIn(allowList)

        var wrongKidFailed = false
        try {
            ApiClientPrivateFields.openAllowList("different-kid", sealedAllowList)
        } catch (_: Exception) {
            wrongKidFailed = true
        }
        assertThat(wrongKidFailed).isTrue()
    }

    @Test
    fun `legacy plaintext fields are rejected by reader`() {
        var failed = false
        try {
            ApiClientPrivateFields.openName("kid", "plaintext-name")
        } catch (_: Exception) {
            failed = true
        }
        assertThat(failed).isTrue()
    }
}
