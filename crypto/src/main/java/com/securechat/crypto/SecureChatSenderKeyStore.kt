package com.securechat.crypto

import com.securechat.crypto.store.CryptoSenderKeyStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.whispersystems.libsignal.groups.SenderKeyName
import org.whispersystems.libsignal.groups.state.SenderKeyRecord
import org.whispersystems.libsignal.groups.state.SenderKeyStore
import javax.inject.Inject
import javax.inject.Singleton

/**
 * libsignal'in synchronous SenderKeyStore interface'ini async storage'a koprular.
 *
 * GroupSessionBuilder ve GroupCipher bu store'u kullanir. Signal Protocol
 * synchronous erisim gerektirdiginden DAO cagrilari runBlocking ile IO
 * dispatcher'da yapilir (SecureChatProtocolStore pattern'i ile ayni).
 *
 * loadSenderKey null donmek YERINE bos bir SenderKeyRecord doner —
 * libsignal'in beklentisi budur (yoksa NoSessionException atilmaz, GroupSessionBuilder
 * yeni record uretip persist eder).
 */
@Singleton
class SecureChatSenderKeyStore @Inject constructor(
    private val backingStore: CryptoSenderKeyStore
) : SenderKeyStore {

    private fun <T> ioBlocking(block: suspend () -> T): T = runBlocking(Dispatchers.IO) { block() }

    override fun storeSenderKey(senderKeyName: SenderKeyName, record: SenderKeyRecord) {
        val groupId = senderKeyName.groupId
        val senderAddr = senderKeyName.sender
        ioBlocking {
            backingStore.storeSenderKey(groupId, senderAddr.name, senderAddr.deviceId, record.serialize())
        }
    }

    override fun loadSenderKey(senderKeyName: SenderKeyName): SenderKeyRecord {
        val groupId = senderKeyName.groupId
        val senderAddr = senderKeyName.sender
        val bytes = ioBlocking {
            backingStore.loadSenderKey(groupId, senderAddr.name, senderAddr.deviceId)
        }
        return if (bytes != null) SenderKeyRecord(bytes) else SenderKeyRecord()
    }
}
