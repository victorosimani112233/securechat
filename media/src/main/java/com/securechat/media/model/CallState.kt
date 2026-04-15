package com.securechat.media.model

/**
 * Arama yasam dongusu durumlari.
 *
 * Durum gecisleri:
 * IDLE -> INITIATING -> RINGING -> CONNECTING -> ACTIVE -> ENDED
 *                          |                       |
 *                       REJECTED                 FAILED
 *                          |
 *                        BUSY
 */
enum class CallState {
    /** Arama yok, bekleme durumunda. */
    IDLE,

    /** Arama baslatiliyor (SDP offer hazirlaniyor). */
    INITIATING,

    /** Karsi tarafa bildirim gonderildi, cevap bekleniyor. */
    RINGING,

    /** SDP answer alindi, ICE negotiation devam ediyor. */
    CONNECTING,

    /** Arama aktif, medya akisi var. */
    ACTIVE,

    /** Baglanti koptu, yeniden baglaniliyor. */
    RECONNECTING,

    /** Normal sonlanma. */
    ENDED,

    /** Karsi taraf aramayi reddetti. */
    REJECTED,

    /** Karsi taraf baska bir aramada mesgul. */
    BUSY,

    /** Teknik hata nedeniyle sonlandi. */
    FAILED
}
