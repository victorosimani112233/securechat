package com.securechat.network.model

import kotlinx.serialization.Serializable

/**
 * Arama kontrol aksiyonlari.
 * Arama yasam dongusu boyunca gonderilen kontrol mesajlarini tanimlar.
 */
@Serializable
enum class CallAction {
    /** Arama calma durumunda. */
    RINGING,

    /** Arama kabul edildi. */
    ACCEPT,

    /** Arama reddedildi. */
    REJECT,

    /** Arama sonlandirildi. */
    HANGUP,

    /** Kullanici baska bir aramada mesgul. */
    BUSY
}
