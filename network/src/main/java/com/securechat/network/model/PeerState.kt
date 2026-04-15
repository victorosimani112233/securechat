package com.securechat.network.model

/**
 * Bir peer ile olan baglanti durumunu temsil eder.
 * P2P baglanti yasam dongusu boyunca gecisler yapilir.
 */
enum class PeerState {
    /** Peer ile baglanti yok. */
    DISCONNECTED,

    /** Peer ile baglanti kurulma asamasinda. */
    CONNECTING,

    /** Signaling sunucusu uzerinden iletisim kuruldu (relay modu). */
    CONNECTED_SIGNALING,

    /** Dogrudan P2P baglanti kuruldu (WebRTC DataChannel aktif). */
    CONNECTED_P2P,

    /** Baglanti koptu, yeniden kurulma deneniyor. */
    RECONNECTING
}
