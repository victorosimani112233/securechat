package com.securechat.botapi.signal

import com.google.common.truth.Truth.assertThat
import org.junit.jupiter.api.Test
import org.whispersystems.libsignal.SessionBuilder
import org.whispersystems.libsignal.SessionCipher
import org.whispersystems.libsignal.SignalProtocolAddress
import org.whispersystems.libsignal.protocol.CiphertextMessage
import org.whispersystems.libsignal.protocol.PreKeySignalMessage
import org.whispersystems.libsignal.state.PreKeyBundle
import org.whispersystems.libsignal.state.PreKeyRecord
import org.whispersystems.libsignal.state.SignedPreKeyRecord
import org.whispersystems.libsignal.state.impl.InMemorySignalProtocolStore
import org.whispersystems.libsignal.util.KeyHelper

/**
 * libsignal'in JVM (signal-protocol-java) varianti calismakta mi smoke test.
 *
 * Iki sahte identity uretir; Alice bot rolu, Bob recipient. Alice
 * Bob'un bundle'iyla session kurar, mesaji sifreler; Bob mesaji decrypt eder.
 * Wire format crypto modulundeki signal-protocol-android ile uyumlu.
 */
class SignalEncryptorSmokeTest {

    @Test
    fun `libsignal roundtrip encrypt decrypt`() {
        // --- Bob (recipient) — kendi identity + bundle ---
        val bobIdentity = KeyHelper.generateIdentityKeyPair()
        val bobRegId = KeyHelper.generateRegistrationId(false)
        val bobStore = InMemorySignalProtocolStore(bobIdentity, bobRegId)

        val bobPreKey: PreKeyRecord = KeyHelper.generatePreKeys(1, 1).first()
        val bobSignedPreKey: SignedPreKeyRecord = KeyHelper.generateSignedPreKey(bobIdentity, 1)
        bobStore.storePreKey(bobPreKey.id, bobPreKey)
        bobStore.storeSignedPreKey(bobSignedPreKey.id, bobSignedPreKey)

        val bobBundle = PreKeyBundle(
            bobRegId,
            1,                              // deviceId
            bobPreKey.id,
            bobPreKey.keyPair.publicKey,
            bobSignedPreKey.id,
            bobSignedPreKey.keyPair.publicKey,
            bobSignedPreKey.signature,
            bobIdentity.publicKey
        )

        // --- Alice (bot) — kendi identity, Bob ile session kurar ---
        val aliceIdentity = KeyHelper.generateIdentityKeyPair()
        val aliceRegId = KeyHelper.generateRegistrationId(false)
        val aliceStore = InMemorySignalProtocolStore(aliceIdentity, aliceRegId)
        val bobAddress = SignalProtocolAddress("bob", 1)
        SessionBuilder(aliceStore, bobAddress).process(bobBundle)

        // Alice → Bob
        val plaintext = "Selam Bob — bu bot tarafindan gonderildi.".toByteArray()
        val ciphertext: CiphertextMessage = SessionCipher(aliceStore, bobAddress).encrypt(plaintext)

        // Bob decrypt
        val aliceAddress = SignalProtocolAddress("alice", 1)
        val bobCipher = SessionCipher(bobStore, aliceAddress)
        val decrypted: ByteArray = bobCipher.decrypt(PreKeySignalMessage(ciphertext.serialize()))

        assertThat(decrypted).isEqualTo(plaintext)
        assertThat(ciphertext.type).isEqualTo(CiphertextMessage.PREKEY_TYPE)
    }
}
