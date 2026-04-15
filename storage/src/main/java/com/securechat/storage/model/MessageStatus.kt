package com.securechat.storage.model

/**
 * Mesaj durumu. Gonderim yasam dongusunu takip eder.
 */
enum class MessageStatus {
    SENDING, SENT, DELIVERED, READ, FAILED
}
