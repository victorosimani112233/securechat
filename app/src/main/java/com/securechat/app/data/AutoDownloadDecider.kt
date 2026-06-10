package com.securechat.app.data

import javax.inject.Inject
import javax.inject.Singleton

/**
 * AutoDownloadPolicy + dinamik network durumu girdisiyle bir gelen dosyanin
 * otomatik indirilip indirilmeyecegine karar verir.
 *
 * Saf logic — Hilt singleton ama state tutmaz; her cagri bagimsiz.
 *
 * Karar matrisi:
 *   1. NetworkType bilinmiyorsa (OTHER) konservatif davran — wifi politikasi uygula
 *   2. Hucresel'de fileSize > maxAutoDownloadBytes ise her zaman false
 *   3. Kategoriye + agtipine gore policy bit'i sorgulanir
 */
@Singleton
class AutoDownloadDecider @Inject constructor() {

    /**
     * @return true → kullanici acmadan otomatik indir; false → placeholder + manual "İndir"
     */
    fun shouldDownload(
        policy: AutoDownloadPolicy,
        category: MediaCategory,
        fileSize: Long,
        network: NetworkType
    ): Boolean {
        val isCellular = network == NetworkType.CELLULAR
        // Bilinmeyen ag → wifi politikasi uygula (konservatif degil; cunku
        // many devices kim bilir hangi agdadir, ama default policy zaten wifi'da acik).
        // Bu sayede dis hata-cisitleri sessizce blocked olmaz.

        // Cellular emergency-stop: buyuk dosya hucreselde otomatik indirilmemeli
        if (isCellular && fileSize > policy.maxAutoDownloadBytes) return false

        return when (category) {
            MediaCategory.PHOTO ->
                if (isCellular) policy.photosOnCellular else policy.photosOnWifi
            MediaCategory.VIDEO ->
                if (isCellular) policy.videosOnCellular else policy.videosOnWifi
            MediaCategory.DOCUMENT ->
                if (isCellular) policy.documentsOnCellular else policy.documentsOnWifi
        }
    }

    /** MIME tipini MediaCategory'e cevirir. */
    fun categoryFor(mimeType: String): MediaCategory = when {
        mimeType.startsWith("image/") -> MediaCategory.PHOTO
        mimeType.startsWith("video/") -> MediaCategory.VIDEO
        else -> MediaCategory.DOCUMENT
    }
}
