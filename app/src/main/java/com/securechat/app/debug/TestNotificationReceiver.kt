package com.securechat.app.debug

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import com.securechat.app.R

/**
 * Debug: ADB ile Elçim bildirimi tetiklemek için receiver.
 *
 * Normal:
 * adb shell "am broadcast -a com.securechat.app.debug.TEST_NOTIFICATION --es sender Ahmet --es message Selam -n com.securechat.app.debug/com.securechat.app.debug.TestNotificationReceiver"
 *
 * Gizlilik modu:
 * adb shell "am broadcast -a com.securechat.app.debug.TEST_NOTIFICATION --es sender Ahmet --es message Selam --ez hide_content true -n com.securechat.app.debug/com.securechat.app.debug.TestNotificationReceiver"
 */
class TestNotificationReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "TestNotifReceiver"
        private const val GROUP_KEY = "elcim_messages"
        private const val SUMMARY_ID = 0
        private const val PRIVACY_NOTIF_ID = 1
        private val messageCountMap = mutableMapOf<String, Int>()
        private val recentMessagesMap = mutableMapOf<String, MutableList<Pair<String, Long>>>()
    }

    override fun onReceive(context: Context, intent: Intent) {
        val sender = intent.getStringExtra("sender") ?: "Test Kullanici"
        val message = intent.getStringExtra("message") ?: "Bu bir test mesajidir."
        val hideContent = intent.getBooleanExtra("hide_content", false)

        Log.d(TAG, "Broadcast alindi: sender=$sender, message=$message, hideContent=$hideContent")

        // Mesaj sayacini guncelle
        messageCountMap[sender] = (messageCountMap[sender] ?: 0) + 1
        val recentList = recentMessagesMap.getOrPut(sender) { mutableListOf() }
        recentList.add(Pair(message, System.currentTimeMillis()))
        if (recentList.size > 5) recentList.removeAt(0)

        val totalMessages = messageCountMap.values.sum()
        val chatCount = messageCountMap.size

        val channelId = "elcim_messages_v4"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (nm.getNotificationChannel(channelId) == null) {
            val channel = NotificationChannel(channelId, "Elçim Mesajlar", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Elçim - Gelen mesaj bildirimleri"
                enableVibration(true)
                enableLights(true)
                lightColor = 0xFF3E7BFA.toInt()
                setShowBadge(true)
            }
            nm.createNotificationChannel(channel)
        }

        val tapIntent = Intent(context, com.securechat.app.SecureChatActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        if (hideContent) {
            // ── GIZLILIK MODU: tek bildirim, her mesajda guncellenir ──
            // Onceki per-conversation bildirimlerini temizle
            nm.cancel(SUMMARY_ID)
            for (notif in nm.activeNotifications) {
                if (notif.notification.group == GROUP_KEY) {
                    nm.cancel(notif.id)
                }
            }

            val privacyPendingIntent = android.app.PendingIntent.getActivity(
                context, PRIVACY_NOTIF_ID, tapIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val privacyText = if (chatCount > 1) {
                "$chatCount sohbetten $totalMessages yeni mesaj"
            } else {
                "$totalMessages yeni mesaj"
            }

            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setColor(0xFF3E7BFA.toInt())
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(privacyPendingIntent)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setNumber(totalMessages)
                .setContentTitle("Elçim")
                .setContentText(privacyText)
                .setSubText("Elçim")

            nm.notify(PRIVACY_NOTIF_ID, builder.build())
            Log.d(TAG, "Gizlilik bildirimi: $privacyText")
            return
        }

        // ── NORMAL MOD: sohbet basina ayri bildirim + grup ozeti ──
        val notifId = sender.hashCode()
        val pendingIntent = android.app.PendingIntent.getActivity(
            context, notifId, tapIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val existingNotifications = nm.activeNotifications.filter {
            it.notification.group == GROUP_KEY && it.id != SUMMARY_ID && it.id != PRIVACY_NOTIF_ID
        }
        val existingChatCount = existingNotifications.map { it.id }.toSet().size
        val willHaveChats = if (existingNotifications.any { it.id == notifId }) existingChatCount else existingChatCount + 1

        val subText = if (willHaveChats > 1) {
            "Elçim · $willHaveChats sohbet, $totalMessages mesaj"
        } else {
            "Elçim"
        }

        val person = androidx.core.app.Person.Builder()
            .setName(sender)
            .setImportant(true)
            .build()

        val style = NotificationCompat.MessagingStyle(person)
        for ((msg, ts) in recentList) {
            style.addMessage(msg, ts, person)
        }

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setColor(0xFF3E7BFA.toInt())
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setGroup(GROUP_KEY)
            .setNumber(messageCountMap[sender] ?: 1)
            .setContentTitle(sender)
            .setContentText(message)
            .setStyle(style)
            .setSubText(subText)

        nm.notify(notifId, builder.build())
        Log.d(TAG, "Bildirim gosterildi: id=$notifId, sender=$sender")

        // Grup ozet bildirimi
        val activeNotifications = nm.activeNotifications.filter {
            it.notification.group == GROUP_KEY && it.id != SUMMARY_ID && it.id != PRIVACY_NOTIF_ID
        }
        if (activeNotifications.size > 1) {
            val summaryPendingIntent = android.app.PendingIntent.getActivity(
                context, SUMMARY_ID, tapIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
            )

            val finalChatCount = activeNotifications.size
            val finalTotalMessages = messageCountMap.values.sum()
            val summaryText = "$finalChatCount sohbetten $finalTotalMessages yeni mesaj"

            val inboxStyle = NotificationCompat.InboxStyle()
                .setBigContentTitle("Elçim")
                .setSummaryText(summaryText)
            for (notif in activeNotifications) {
                val extras = notif.notification.extras
                val title = extras.getString("android.title") ?: ""
                val text = extras.getCharSequence("android.text")?.toString() ?: ""
                if (title.isNotBlank()) {
                    inboxStyle.addLine("$title: $text")
                }
            }

            val summaryBuilder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setColor(0xFF3E7BFA.toInt())
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setGroup(GROUP_KEY)
                .setGroupSummary(true)
                .setAutoCancel(true)
                .setContentIntent(summaryPendingIntent)
                .setSubText("Elçim")
                .setContentTitle("Elçim")
                .setContentText(summaryText)
                .setNumber(finalTotalMessages)
                .setStyle(inboxStyle)

            nm.notify(SUMMARY_ID, summaryBuilder.build())
            Log.d(TAG, "Ozet bildirimi: $summaryText")
        }
    }
}
