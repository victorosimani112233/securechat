package com.securechat.app.data

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * AutoDownloadDecider birim testleri — saf logic, mocking gerekmez.
 *
 * Matris: kategori (PHOTO/VIDEO/DOC) × ag (WIFI/CELL) × policy → bekleneni dogrula.
 */
class AutoDownloadDeciderTest {

    private val decider = AutoDownloadDecider()
    private val small = 1_000_000L  // 1 MB
    private val huge = 100L * 1024 * 1024  // 100 MB

    @Test
    fun `default policy — wifi her sey acik`() {
        val p = AutoDownloadPolicy.DEFAULT
        assertThat(decider.shouldDownload(p, MediaCategory.PHOTO, small, NetworkType.WIFI)).isTrue()
        assertThat(decider.shouldDownload(p, MediaCategory.VIDEO, small, NetworkType.WIFI)).isTrue()
        assertThat(decider.shouldDownload(p, MediaCategory.DOCUMENT, small, NetworkType.WIFI)).isTrue()
    }

    @Test
    fun `default policy — cellular - foto acik, video + dokuman kapali`() {
        val p = AutoDownloadPolicy.DEFAULT
        assertThat(decider.shouldDownload(p, MediaCategory.PHOTO, small, NetworkType.CELLULAR)).isTrue()
        assertThat(decider.shouldDownload(p, MediaCategory.VIDEO, small, NetworkType.CELLULAR)).isFalse()
        assertThat(decider.shouldDownload(p, MediaCategory.DOCUMENT, small, NetworkType.CELLULAR)).isFalse()
    }

    @Test
    fun `cellular emergency-stop — buyuk dosya her zaman false`() {
        val p = AutoDownloadPolicy.DEFAULT
        // Foto cellular acik ama 100MB > 25MB upper bound
        assertThat(decider.shouldDownload(p, MediaCategory.PHOTO, huge, NetworkType.CELLULAR)).isFalse()
        // Wifi'da sinir uygulanmaz
        assertThat(decider.shouldDownload(p, MediaCategory.PHOTO, huge, NetworkType.WIFI)).isTrue()
    }

    @Test
    fun `WIFI_ONLY policy — cellular tum kategoriler kapali`() {
        val p = AutoDownloadPolicy.WIFI_ONLY
        assertThat(decider.shouldDownload(p, MediaCategory.PHOTO, small, NetworkType.CELLULAR)).isFalse()
        assertThat(decider.shouldDownload(p, MediaCategory.VIDEO, small, NetworkType.CELLULAR)).isFalse()
        assertThat(decider.shouldDownload(p, MediaCategory.DOCUMENT, small, NetworkType.CELLULAR)).isFalse()
        // Wifi yine acik
        assertThat(decider.shouldDownload(p, MediaCategory.PHOTO, small, NetworkType.WIFI)).isTrue()
    }

    @Test
    fun `OTHER ag — wifi politikasi gibi davranir`() {
        val p = AutoDownloadPolicy.DEFAULT
        assertThat(decider.shouldDownload(p, MediaCategory.VIDEO, small, NetworkType.OTHER)).isTrue()
    }

    @Test
    fun `MIME tipi → kategori`() {
        assertThat(decider.categoryFor("image/jpeg")).isEqualTo(MediaCategory.PHOTO)
        assertThat(decider.categoryFor("video/mp4")).isEqualTo(MediaCategory.VIDEO)
        assertThat(decider.categoryFor("application/pdf")).isEqualTo(MediaCategory.DOCUMENT)
        assertThat(decider.categoryFor("audio/mpeg")).isEqualTo(MediaCategory.DOCUMENT)
    }
}
