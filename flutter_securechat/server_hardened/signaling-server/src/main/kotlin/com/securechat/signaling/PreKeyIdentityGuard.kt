package com.securechat.signaling

import java.sql.Connection

/** Caller must lock users first. Recovery is the only writer allowed to replace a pin. */
internal object PreKeyIdentityGuard {
    fun checkOtherNamespace(connection: Connection, userId: String, identity: ByteArray, otherTable: String) {
        require(otherTable in setOf("users", "modern_prekey_bundles"))
        connection.prepareStatement("SELECT identity_public_key FROM $otherTable WHERE user_id = ?::uuid").use {
            it.setString(1, userId)
            it.executeQuery().use { rows ->
                val existing = if (rows.next()) rows.getBytes(1) else null
                check(existing == null || existing.contentEquals(identity)) { "Explicit identity recovery required" }
            }
        }
    }

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
