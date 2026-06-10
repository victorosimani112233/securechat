package com.securechat.app.data

/**
 * Otomatik indirme politikasi — kullanici tercihiyle gelen medya/dosyanin
 * otomatik kaydedilip kaydedilmeyecegine karar verir.
 *
 * Dort eksen:
 *   - WiFi vs Hucresel
 *   - Foto, video, dokuman tipleri
 *   - maxAutoDownloadBytes — hucresel uzerinden buyuk dosyalari emergency-stop
 *
 * Default degerler WhatsApp davranisina yakin: WiFi'da her sey acik, hucresel
 * uzerinde sadece foto + max 25MB sinir.
 */
data class AutoDownloadPolicy(
    val photosOnWifi: Boolean = true,
    val photosOnCellular: Boolean = true,
    val videosOnWifi: Boolean = true,
    val videosOnCellular: Boolean = false,
    val documentsOnWifi: Boolean = true,
    val documentsOnCellular: Boolean = false,
    val maxAutoDownloadBytes: Long = 25 * 1024 * 1024
) {
    companion object {
        /** Tum izinlerin default acik oldugu policy. */
        val DEFAULT = AutoDownloadPolicy()

        /** Hucresel uzerinde tum auto-download'i kapatir — yine de wifi'da calisir. */
        val WIFI_ONLY = AutoDownloadPolicy(
            photosOnCellular = false,
            videosOnCellular = false,
            documentsOnCellular = false
        )
    }
}

/** Dosya tipi kategorisi — Decider girdisi. */
enum class MediaCategory {
    PHOTO,    // image/*
    VIDEO,    // video/*
    DOCUMENT  // diger her sey (pdf, doc, ses, vb.)
}
