package com.securechat.network.model

/**
 * Gonderilmeyi bekleyen mesaj.
 * P2P baglantisi veya signaling baglantisi olmadigi durumlarda
 * mesajlar bu kuyrukta saklanir.
 */
data class PendingMessage(
    val recipientId: String,
    val content: String,
    val timestamp: Long
)
