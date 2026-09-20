package com.securechat.app

import android.content.Context
import android.content.Intent
import android.util.Base64
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver
import java.security.MessageDigest
import java.util.UUID

/** Opens a generic native call surface before Flutter's background isolate starts. */
class SecureChatFirebaseMessagingReceiver : FlutterFirebaseMessagingReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        runCatching { handlePushHint(context, intent) }
        // Preserve FlutterFire foreground delivery and Dart background drain.
        super.onReceive(context, intent)
    }

    private fun handlePushHint(context: Context, intent: Intent) {
        if (intent.getStringExtra("type") != "securechat_wake_v2") return
        val encryptedHint = intent.getStringExtra("k") ?: return
        val key = PushHintKeyStore.read(context.applicationContext) ?: return
        if (PushHintCipher.open(key, encryptedHint) != 'c') return
        val messageId = intent.getStringExtra("google.message_id")
            ?: intent.getStringExtra("message_id")
            ?: UUID.randomUUID().toString()
        val opaqueId = Base64.encodeToString(
            MessageDigest.getInstance("SHA-256").digest(messageId.toByteArray(Charsets.UTF_8)),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
        )
        SecureChatNativeCallController.reportIncoming(
            context,
            NativeCallInfo(
                callId = "push:$opaqueId",
                peerId = "private",
                peerName = "Elçim araması",
                hasVideo = false,
                redactIdentity = true
            ),
            fromPushHint = true
        )
    }
}
