package com.securechat.network.model

/**
 * WebSocket baglanti durumunu temsil eder.
 * Signaling sunucusuna olan baglantiyi izlemek icin kullanilir.
 */
sealed class ConnectionState {
    /** Sunucuya bagli degil. */
    data object Disconnected : ConnectionState()

    /** Baglanti kuruluyor. */
    data object Connecting : ConnectionState()

    /** Sunucuya basariyla baglandi. */
    data object Connected : ConnectionState()

    /** Baglanti hatasi olustu. */
    data class Error(val throwable: Throwable) : ConnectionState()
}
