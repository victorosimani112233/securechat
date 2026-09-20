package com.securechat.app

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log

/** Application-scoped native call entry point; it does not require an Activity. */
internal object SecureChatNativeCallController {
    private const val ACCOUNT_ID = "elcim_self_managed"

    fun register(context: Context) {
        SecureChatCallNotificationManager(context.applicationContext).ensureChannels()
        context.getSystemService(TelecomManager::class.java).registerPhoneAccount(
            PhoneAccount.builder(accountHandle(context), "Elcim")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
        )
    }

    fun reportIncoming(context: Context, info: NativeCallInfo, fromPushHint: Boolean) {
        val appContext = context.applicationContext
        register(appContext)
        val notifications = SecureChatCallNotificationManager(appContext)
        if (!fromPushHint) {
            val promotion = NativeCallRegistry.promoteHint(info)
            if (promotion != null) {
                when (promotion.action) {
                    "answer" -> {
                        notifications.showConnecting(info)
                        NativeCallRegistry.emitResolved("answer", info.callId)
                    }
                    "end" -> {
                        notifications.cancel()
                        NativeCallRegistry.emitResolved("end", info.callId)
                    }
                    else -> notifications.showIncoming(info)
                }
                return
            }
            NativeCallRegistry.remember(
                info.callId,
                info.peerId,
                info.peerName,
                info.hasVideo,
                info.redactIdentity
            )
        } else if (!NativeCallRegistry.rememberHint(info)) {
            return
        }

        try {
            appContext.getSystemService(TelecomManager::class.java)
                .addNewIncomingCall(accountHandle(appContext), callExtras(appContext, info))
        } catch (error: Exception) {
            // The full-screen notification remains a valid fallback on devices
            // that reject self-managed Telecom registration.
            Log.w("SecureChatNativeCall", "Telecom incoming call rejected", error)
        }
        notifications.showIncoming(info)
    }

    fun reportOutgoing(context: Context, info: NativeCallInfo) {
        val appContext = context.applicationContext
        register(appContext)
        NativeCallRegistry.remember(
            info.callId,
            info.peerId,
            info.peerName,
            info.hasVideo,
            info.redactIdentity
        )
        appContext.getSystemService(TelecomManager::class.java).placeCall(
            Uri.fromParts("securechat", info.callId, null),
            callExtras(appContext, info)
        )
        SecureChatCallNotificationManager(appContext).showConnecting(info)
    }

    private fun accountHandle(context: Context) = PhoneAccountHandle(
        ComponentName(context, SecureChatConnectionService::class.java),
        ACCOUNT_ID
    )

    private fun callExtras(context: Context, info: NativeCallInfo) = Bundle().apply {
        putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, accountHandle(context))
        putString(SecureChatConnectionService.EXTRA_CALL_ID, info.callId)
        putString(SecureChatConnectionService.EXTRA_PEER_ID, info.peerId)
        putString(SecureChatConnectionService.EXTRA_PEER_NAME, info.peerName)
        putBoolean(SecureChatConnectionService.EXTRA_HAS_VIDEO, info.hasVideo)
        putBoolean(SecureChatConnectionService.EXTRA_REDACT_IDENTITY, info.redactIdentity)
    }
}
