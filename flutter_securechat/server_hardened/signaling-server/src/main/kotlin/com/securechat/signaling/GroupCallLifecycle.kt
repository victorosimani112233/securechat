package com.securechat.signaling

import io.ktor.server.application.*
import kotlinx.coroutines.*

/** Suresi dolan grup aramalarini bellekten duzenli olarak siler. */
internal fun Application.configureGroupCallLifecycle() {
    val cleanup = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    environment.monitor.subscribe(ApplicationStopping) { cleanup.cancel() }
    cleanup.launch {
        while (isActive) {
            GroupCallSessionStore.purgeExpired()
            delay(30_000)
        }
    }
}
