package com.securechat.crypto.model

import org.whispersystems.libsignal.IdentityKey
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyRecord

/**
 * Kullanicinin public key bundle'i.
 * Ilk kayit sirasinda uretilir ve signaling sunucusuna gonderilir.
 * Diger kullanicilar bu bundle ile X3DH key agreement baslatir.
 */
data class KeyBundle(
    val identityKey: IdentityKey,
    val registrationId: Int,
    val preKeys: List<PreKeyRecord>,
    val signedPreKey: SignedPreKeyRecord
)
