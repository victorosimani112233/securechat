package com.securechat.app.data.incoming.handlers

import com.securechat.network.SignalMessage

/**
 * Tek bir SignalMessage tipi icin handler kontrati.
 *
 * Faz 10: IncomingMessageHandler'in 2249 satirlik tek-when dispatcher'ini
 * kademeli olarak handler class'larina bolmek icin foundation. Her handler:
 *   - Tek bir SignalMessage alt-tipini handle eder
 *   - Kendi dependency'lerini constructor uzerinden alir
 *   - suspend handle(signal) imzasi
 *
 * Dispatch hala IncomingMessageHandler'in `when` bloku — handler'lar
 * field olarak inject edilir, when icinde delegate cagrilir. Tam registry
 * pattern (Hilt @IntoMap) ileride opsiyonel.
 */
interface SignalHandler<T : SignalMessage> {
    suspend fun handle(signal: T)
}
