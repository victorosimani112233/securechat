package com.securechat.botapi.delivery

import ch.qos.logback.classic.pattern.ClassicConverter
import ch.qos.logback.classic.spi.ILoggingEvent

class BotPrivacyMessageConverter : ClassicConverter() {
    override fun convert(event: ILoggingEvent): String =
        BotQueuePrivacy.redact(event.formattedMessage)
}
