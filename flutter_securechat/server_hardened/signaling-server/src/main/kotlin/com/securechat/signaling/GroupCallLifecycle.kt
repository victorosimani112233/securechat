package com.securechat.signaling

import io.ktor.server.application.*
import kotlinx.coroutines.*
import org.slf4j.LoggerFactory

/** Retains failed disposal work, including its capacity reservation, for retry. */
internal suspend fun cleanExpiredGroupCalls(
    now: Long = System.currentTimeMillis(),
    dispose: suspend (GroupCallSessionStore.ActiveCall) -> Unit = { call ->
        JanusOrchestrator.destroyVideoRoom(call.groupId, call.sfuRoomId, call.instanceId)
    },
) {
    GroupCallSessionStore.purgeExpired(now)
    for (call in GroupCallSessionStore.roomsAwaitingCleanup()) {
        try {
            dispose(call)
            GroupCallSessionStore.roomCleanupCompleted(call.instanceId)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            LoggerFactory.getLogger("GroupCallLifecycle").warn("Group room disposal will retry: {}", error.javaClass.simpleName)
        }
    }
}

internal fun Application.configureGroupCallLifecycle() {
    val cleanup = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    environment.monitor.subscribe(ApplicationStopping) { cleanup.cancel() }
    cleanup.launch {
        while (isActive) {
            cleanExpiredGroupCalls()
            delay(30_000)
        }
    }
}
