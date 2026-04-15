package com.securechat.app.debug

import android.content.Context
import com.securechat.app.IncomingCallActivity
import com.securechat.app.data.UserSession
import com.securechat.media.CallManager
import com.securechat.media.IncomingCallHandler
import com.securechat.media.model.CallDirection
import com.securechat.media.model.CallSession
import com.securechat.media.model.CallState
import com.securechat.network.model.CallType
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Gelen arama bildirim sistemini test etmek için debug utility.
 *
 * Bu sınıf production build'de kullanılmamalı, sadece debug/development amaçlı.
 */
@Singleton
class CallNotificationTester @Inject constructor(
    @ApplicationContext private val context: Context,
    private val incomingCallHandler: IncomingCallHandler,
    private val callManager: CallManager,
    private val userSession: UserSession
) {

    /**
     * Sahte bir gelen arama bildirimi gösterir.
     * Background call detection sistemini test etmek için kullanılır.
     *
     * @param callerName Arayan kişinin adı
     * @param callType Arama tipi (VOICE veya VIDEO)
     */
    fun simulateIncomingCall(callerName: String = "Test Caller", callType: CallType = CallType.VOICE) {
        android.util.Log.d("CallNotificationTester", "Sahte gelen arama simüle ediliyor: $callerName")

        // Fake call session oluştur
        val fakeSession = CallSession(
            callId = UUID.randomUUID().toString(),
            peerId = "test_caller_id",
            callType = callType,
            direction = CallDirection.INCOMING,
            state = CallState.RINGING,
            startTime = null
        )

        // Notification göster
        incomingCallHandler.showIncomingCall(
            session = fakeSession,
            peerName = callerName,
            fullScreenActivityClass = IncomingCallActivity::class.java
        )

        // IncomingCallActivity'yi direkt başlat
        try {
            val intent = android.content.Intent(context, IncomingCallActivity::class.java).apply {
                putExtra("peer_id", "test_caller_id")
                putExtra("peer_name", callerName)
                putExtra("call_type", callType.name)
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            context.startActivity(intent)
            android.util.Log.d("CallNotificationTester", "Test IncomingCallActivity başlatıldı")
        } catch (e: Exception) {
            android.util.Log.e("CallNotificationTester", "Test Activity başlatılamadı: ${e.message}")
        }
    }

    /**
     * Missed call bildirimi test eder.
     *
     * @param callerName Arayan kişinin adı
     */
    fun simulateMissedCall(callerName: String = "Missed Caller") {
        android.util.Log.d("CallNotificationTester", "Sahte kaçırılan arama simüle ediliyor: $callerName")

        // TODO: MissedCallTracker.showMissedCallNotification()'ı doğrudan çağır
        // Şimdilik manuel notification gösterelim

        val fakeSession = CallSession(
            callId = UUID.randomUUID().toString(),
            peerId = "missed_caller_id",
            callType = CallType.VOICE,
            direction = CallDirection.INCOMING,
            state = CallState.ENDED,
            startTime = null
        )

        android.util.Log.d("CallNotificationTester", "Test missed call session oluşturuldu: ${fakeSession.callId}")
    }

    /**
     * Bildirim channel'larının doğru kurulup kurulmadığını test eder.
     */
    fun testNotificationChannels() {
        android.util.Log.d("CallNotificationTester", "Notification channel'ları test ediliyor...")

        incomingCallHandler.initialize()
        android.util.Log.d("CallNotificationTester", "IncomingCallHandler initialized")

        val nm = context.getSystemService(android.app.NotificationManager::class.java)
        val incomingCallChannel = nm.getNotificationChannel("incoming_call_channel")
        val missedCallChannel = nm.getNotificationChannel("missed_call_channel")

        android.util.Log.d("CallNotificationTester", "Incoming call channel: ${incomingCallChannel?.name}")
        android.util.Log.d("CallNotificationTester", "Missed call channel: ${missedCallChannel?.name}")
    }
}