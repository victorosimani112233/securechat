package com.securechat.signaling

import ch.qos.logback.classic.Level
import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.classic.spi.ThrowableProxyUtil
import ch.qos.logback.core.read.ListAppender
import java.io.Closeable
import org.junit.jupiter.api.Assertions.assertFalse
import org.slf4j.LoggerFactory

internal class TestLogCapture(vararg loggerNames: String) : Closeable {
    private val loggers = loggerNames.map { LoggerFactory.getLogger(it) as Logger }
    private val previousLevels = loggers.map { it.level }
    private val appender = object : ListAppender<ILoggingEvent>() {
        override fun append(event: ILoggingEvent) {
            event.prepareForDeferredProcessing()
            super.append(event)
        }
    }.apply {
        context = loggers.first().loggerContext
        start()
    }

    init {
        loggers.forEach {
            it.level = Level.ALL
            it.addAppender(appender)
        }
    }

    val events: List<ILoggingEvent>
        get() = synchronized(appender) { appender.list.toList() }

    fun assertNoSecrets(vararg secrets: String) {
        val output = events.joinToString("\n") {
            listOf(
                it.message,
                it.formattedMessage,
                it.argumentArray?.contentDeepToString(),
                it.mdcPropertyMap.toString(),
                it.throwableProxy?.let(ThrowableProxyUtil::asString),
            ).joinToString("\n")
        }
        secrets.forEach { secret ->
            require(secret.isNotEmpty())
            assertFalse(output.contains(secret), "Captured logs must not contain registration secrets")
        }
    }

    override fun close() {
        loggers.forEachIndexed { index, logger ->
            logger.detachAppender(appender)
            logger.level = previousLevels[index]
        }
        appender.stop()
    }
}
