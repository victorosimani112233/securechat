package com.securechat.signaling

import ch.qos.logback.classic.pattern.ClassicConverter
import ch.qos.logback.classic.spi.ILoggingEvent

class PrivacyMessageConverter : ClassicConverter() {
    override fun convert(event: ILoggingEvent): String =
        ServerPrivacy.redactLogMessage(event.formattedMessage)
}
