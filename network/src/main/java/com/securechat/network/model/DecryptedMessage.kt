package com.securechat.network.model

/**
 * P2P DataChannel uzerinden alinan ve cozulmus mesaj.
 *
 * GUVENLIK: Bu nesne plaintext icerir, kullanim sonrasi bellekten
 * silinmesi (reference'in null yapilmasi) onemlidir.
 */
data class DecryptedMessage(
    val senderId: String,
    val content: String,
    val timestamp: Long
)
