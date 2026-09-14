package com.securechat.botapi.health

import com.google.common.truth.Truth.assertThat
import com.securechat.botapi.BotApiConfig
import java.nio.charset.StandardCharsets
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * Bot readiness ve metrics yetkisi.
 *
 * Onceki `/health` yalniz DB ve Redis'e bakiyordu: identity saglanmamis,
 * signaling baglantisi kopmus ya da kuyrugu birikmis bir bot da "ok"
 * gorunuyor, yani gonderim yapamayan bir process trafige aciliyordu.
 */
class HealthReadinessTest {

    private fun ready(
        db: Boolean = true,
        redis: Boolean = true,
        identity: Boolean = true,
        signaling: Boolean = true,
        queueDepth: Long = 0,
    ) = HealthListener.isReady(db, redis, identity, signaling, queueDepth)

    @Test
    fun `everything healthy is ready`() {
        assertThat(ready()).isTrue()
    }

    @Test
    fun `each dependency alone can block readiness`() {
        assertThat(ready(db = false)).isFalse()
        assertThat(ready(redis = false)).isFalse()
        // Bunlarin ikisi eski kontrolde hic yoktu.
        assertThat(ready(identity = false)).isFalse()
        assertThat(ready(signaling = false)).isFalse()
    }

    @Test
    fun `an unmeasurable queue depth is not ready`() {
        // -1 "olculemedi" demektir; bilinmeyen durum hazir sayilmamali.
        assertThat(ready(queueDepth = -1)).isFalse()
    }

    @Test
    fun `a backed up queue is not ready`() {
        val limit = HealthListener.READY_QUEUE_DEPTH_LIMIT

        assertThat(ready(queueDepth = limit)).isTrue()
        assertThat(ready(queueDepth = limit + 1)).isFalse()
    }

    @Test
    fun `metrics requires a matching bearer token`() {
        BotApiConfig.metricsBearerToken = "s3cret-token".toByteArray(StandardCharsets.UTF_8)

        assertThat(HealthListener.metricsAuthorized("Bearer s3cret-token")).isTrue()
        assertThat(HealthListener.metricsAuthorized("Bearer wrong-token")).isFalse()
        assertThat(HealthListener.metricsAuthorized("s3cret-token")).isFalse()
        assertThat(HealthListener.metricsAuthorized("Basic s3cret-token")).isFalse()
        assertThat(HealthListener.metricsAuthorized(null)).isFalse()
        assertThat(HealthListener.metricsAuthorized("")).isFalse()
        // Prefix eslesmesi yetmemeli.
        assertThat(HealthListener.metricsAuthorized("Bearer s3cret")).isFalse()
        assertThat(HealthListener.metricsAuthorized("Bearer s3cret-token-extra")).isFalse()
    }

    @BeforeEach
    fun resetToken() {
        BotApiConfig.metricsBearerToken = "s3cret-token".toByteArray(StandardCharsets.UTF_8)
    }
}
