package com.securechat.app.data

import com.securechat.storage.dao.ConversationDao
import com.securechat.storage.domain.LocalMessage
import com.securechat.storage.entity.ConversationEntity
import com.securechat.storage.model.MessageContentType
import com.securechat.storage.model.MessageStatus
import com.securechat.storage.repository.MessageRepository
import kotlinx.coroutines.flow.first
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DemoDataSeeder @Inject constructor(
    private val messageRepository: MessageRepository,
    private val conversationDao: ConversationDao
) {
    suspend fun seedIfEmpty() {
        val existing = messageRepository.getConversations().first()
        if (existing.isNotEmpty()) return

        val now = System.currentTimeMillis()

        // Ornek konusmalar ve mesajlar
        val demoConversations = listOf(
            DemoConversation(
                peerId = "user_ahmet",
                peerName = "Ahmet Yilmaz",
                peerPhone = "+905551234567",
                messages = listOf(
                    DemoMessage("Selam, nasilsin?", false, now - 3600_000),
                    DemoMessage("Iyiyim, sen nasilsin?", true, now - 3500_000),
                    DemoMessage("Ben de iyiyim. Aksam bulusacak miyiz?", false, now - 3400_000),
                    DemoMessage("Tabii, saat 8'de olur mu?", true, now - 3300_000),
                    DemoMessage("Super, gorusuruz!", false, now - 3200_000),
                )
            ),
            DemoConversation(
                peerId = "user_ayse",
                peerName = "Ayse Demir",
                peerPhone = "+905559876543",
                messages = listOf(
                    DemoMessage("Toplanti saat kacta?", true, now - 7200_000),
                    DemoMessage("14:00'te", false, now - 7100_000),
                    DemoMessage("Tamam, tesekkurler", true, now - 7000_000),
                )
            ),
            DemoConversation(
                peerId = "user_mehmet",
                peerName = "Mehmet Kaya",
                peerPhone = "+905553456789",
                messages = listOf(
                    DemoMessage("Projenin son durumu ne?", false, now - 86400_000),
                    DemoMessage("Yarin raporu gonderecegim", true, now - 86300_000),
                )
            ),
            DemoConversation(
                peerId = "user_fatma",
                peerName = "Fatma Ozturk",
                peerPhone = "+905557654321",
                messages = listOf(
                    DemoMessage("Dogum gunun kutlu olsun!", true, now - 172800_000),
                    DemoMessage("Cok tesekkur ederim!", false, now - 172700_000),
                )
            ),
        )

        demoConversations.forEach { conv ->
            // Once konusmayi olustur
            conversationDao.insert(
                ConversationEntity(
                    id = conv.peerId,
                    peerId = conv.peerId,
                    peerName = conv.peerName,
                    peerPhone = conv.peerPhone,
                    lastMessage = conv.messages.last().text,
                    lastMessageTimestamp = conv.messages.last().timestamp,
                    unreadCount = conv.messages.count { !it.isOutgoing },
                    isMuted = false,
                    isPinned = false
                )
            )

            conv.messages.forEach { msg ->
                val message = LocalMessage(
                    id = "${conv.peerId}_${msg.timestamp}",
                    conversationId = conv.peerId,
                    senderId = if (msg.isOutgoing) "local_user" else conv.peerId,
                    peerId = conv.peerId,
                    content = msg.text,
                    contentType = MessageContentType.TEXT,
                    timestamp = msg.timestamp,
                    status = if (msg.isOutgoing) MessageStatus.READ else MessageStatus.DELIVERED,
                    isOutgoing = msg.isOutgoing
                )
                messageRepository.saveMessage(message)
            }
        }
    }

    private data class DemoConversation(
        val peerId: String,
        val peerName: String,
        val peerPhone: String,
        val messages: List<DemoMessage>
    )

    private data class DemoMessage(
        val text: String,
        val isOutgoing: Boolean,
        val timestamp: Long
    )
}
