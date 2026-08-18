package com.securechat.botapi.signal

import org.slf4j.LoggerFactory
import org.whispersystems.libsignal.SessionBuilder
import org.whispersystems.libsignal.SessionCipher
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.protocol.CiphertextMessage
import org.whispersystems.libsignal.state.PreKeyBundle

private val log = LoggerFactory.getLogger("SignalEncryptor")

/**
 * Bot tarafindan recipient'lara mesaj sifreleme.
 *
 * Session henuz yoksa PreKeyBundle ile yeni session kurar (X3DH); ardindan
 * SessionCipher.encrypt ile mesaji sifreler. Session state otomatik
 * persist edilir (PgSignalProtocolStore).
 */
class SignalEncryptor(private val store: PgSignalProtocolStore) {

    /** EncryptedEnvelope — bot WS uzerinden gondereceği sifreli paket. */
    data class EncryptedEnvelope(
        val recipientUserId: String,
        val deviceId: Int,
        val type: Int,           // CiphertextMessage.PREKEY_TYPE (3) veya WHISPER_TYPE (2)
        val ciphertext: ByteArray
    )

    /**
     * Hedef ile session yoksa bundle ile kur. Bundle her cagrida fresh
     * fetch edilmeli (PreKeyBundleFetcher cache'lemez) — recipient'in
     * one-time prekey rotation'ini etkilememek icin.
     */
    fun ensureSession(recipientUserId: String, deviceId: Int, bundle: PreKeyBundle) {
        val address = SignalProtocolAddress(recipientUserId, deviceId)
        if (store.containsSession(address)) return
        SessionBuilder(store, address).process(bundle)
        log.info("[SignalEncryptor] Yeni session kuruldu; device={}", deviceId)
    }

    fun encrypt(recipientUserId: String, deviceId: Int, plaintext: ByteArray): EncryptedEnvelope {
        val address = SignalProtocolAddress(recipientUserId, deviceId)
        check(store.containsSession(address)) {
            "Session yok — encrypt cagrilmadan once ensureSession() ile kurulmalı (recipient=$recipientUserId)"
        }
        val cipher = SessionCipher(store, address)
        val msg: CiphertextMessage = cipher.encrypt(plaintext)
        return EncryptedEnvelope(
            recipientUserId = recipientUserId,
            deviceId = deviceId,
            type = msg.type,
            ciphertext = msg.serialize()
        )
    }
}
