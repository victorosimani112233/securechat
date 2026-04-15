package com.securechat.crypto

import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * PreKeyManager sabit degerlerinin ve yapilandirmasinin unit testleri.
 */
class PreKeyManagerTest {

    @Test
    fun `PREKEY_BATCH_SIZE should be 100`() {
        assertThat(PreKeyManager.PREKEY_BATCH_SIZE).isEqualTo(100)
    }

    @Test
    fun `PREKEY_REFRESH_THRESHOLD should be 20`() {
        assertThat(PreKeyManager.PREKEY_REFRESH_THRESHOLD).isEqualTo(20)
    }

    @Test
    fun `SIGNED_PREKEY_ROTATION_DAYS should be 7`() {
        assertThat(PreKeyManager.SIGNED_PREKEY_ROTATION_DAYS).isEqualTo(7L)
    }

    @Test
    fun `refresh threshold should be less than batch size`() {
        assertThat(PreKeyManager.PREKEY_REFRESH_THRESHOLD)
            .isLessThan(PreKeyManager.PREKEY_BATCH_SIZE)
    }

    @Test
    fun `batch size should be positive`() {
        assertThat(PreKeyManager.PREKEY_BATCH_SIZE).isGreaterThan(0)
    }

    @Test
    fun `rotation days should be positive`() {
        assertThat(PreKeyManager.SIGNED_PREKEY_ROTATION_DAYS).isGreaterThan(0L)
    }
}
