package com.securechat.signaling

import java.sql.Connection

/** Caller must lock users first. Recovery is the only writer allowed to replace a pin. */
/// Prekey yazmalarinda kimlik sahipligi ve epoch kontrolu.
///
/// Burada bir zamanlar `checkOtherNamespace` da vardi: iki prekey
/// namespace'i (v1 `users` ve v2 `modern_prekey_bundles`) bulundugu icin,
/// saldirgan ODEKI namespace'i baslatip kendi kimligini oraya dikebilirdi.
/// v2 kaldirildi; tek namespace kaldigi icin o saldiri sinifi yapisal
/// olarak imkansiz ve capraz kontrole gerek yok.
internal object PreKeyIdentityGuard {
    fun check(connection: Connection, userId: String, identity: ByteArray? = null, expectedEpoch: String? = null) {
        connection.prepareStatement("SELECT recovery_identity_pin, credential_epoch FROM users WHERE user_id = ?::uuid FOR UPDATE").use {
            it.setString(1, userId)
            it.executeQuery().use { rows ->
                check(rows.next()) { "Unknown account" }
                val pin = rows.getBytes(1)
                check(identity == null || pin == null || pin.contentEquals(identity)) { "Explicit identity recovery required" }
                check(expectedEpoch == null || expectedEpoch == rows.getString(2)) { "Superseded credential epoch" }
            }
        }
    }
}
