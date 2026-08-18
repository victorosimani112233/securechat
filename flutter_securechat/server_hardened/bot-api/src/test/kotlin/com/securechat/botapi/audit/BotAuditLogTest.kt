package com.securechat.botapi.audit

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class BotAuditLogTest {
    @Test
    fun `bot audit stores only identity free process counts`() {
        val event = "BOT_API_RATE_LIMIT_HIT"
        val before = BotAuditLog.count(event)
        BotAuditLog.log(
            eventType = event,
            userId = "123e4567-e89b-42d3-a456-426614174000",
            metadata = mapOf("reason" to "private"),
            ipAddress = "192.0.2.2",
        )
        assertEquals(before + 1, BotAuditLog.count(event))
        BotAuditLog.log(eventType = "INVALID")
        assertEquals(0, BotAuditLog.count("INVALID"))
    }
}
