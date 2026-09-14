package com.securechat.signaling

import jakarta.mail.Authenticator
import jakarta.mail.Message
import jakarta.mail.PasswordAuthentication
import jakarta.mail.Session
import jakarta.mail.Transport
import jakarta.mail.internet.InternetAddress
import jakarta.mail.internet.MimeMessage
import org.slf4j.LoggerFactory
import java.util.Properties

private val log = LoggerFactory.getLogger("EmailService")

/**
 * SMTP uzerinden e-posta gonderimi.
 * Kendi sunucundaki SMTP'yi kullan (Postfix, Mailcow, vb.).
 *
 * Env variables:
 *   SMTP_HOST       — ornek: mail.securechat.com
 *   SMTP_PORT       — ornek: 587 (STARTTLS) veya 465 (SSL)
 *   SMTP_USERNAME   — SMTP authentication username
 *   SMTP_PASSWORD   — SMTP authentication password
 *   SMTP_FROM       — gonderici adresi (ornek: noreply@securechat.com)
 *   SMTP_TLS        — "starttls" (default), "ssl", veya "none"
 */
object EmailService {

    private val host: String? by lazy { System.getenv("SMTP_HOST") }
    private val port: Int by lazy { System.getenv("SMTP_PORT")?.toIntOrNull() ?: 587 }
    private val username: String? by lazy { System.getenv("SMTP_USERNAME") }
    private val password: String? by lazy { SecretSource.optional("SMTP_PASSWORD") }
    private val fromAddress: String? by lazy { System.getenv("SMTP_FROM") }
    private val tlsMode: String by lazy { System.getenv("SMTP_TLS") ?: "starttls" }

    val isConfigured: Boolean
        get() = !host.isNullOrBlank() && !fromAddress.isNullOrBlank()

    /** Production registration must never silently degrade to no-OTP mode. */
    fun initialize() = validate()

    /**
     * SMTP yapilandirmasinin fail-closed dogrulamasi.
     *
     * Kayit akisi OTP'ye baglidir: eksik ya da duz metin bir SMTP
     * yapilandirmasi sessizce "OTP'siz kayit" moduna dusmemelidir. Ortam
     * disaridan verilebildigi icin bu kurallar gercek bir SMTP sunucusu
     * olmadan surulebilir.
     */
    internal fun validate(environment: Map<String, String> = System.getenv()) {
        val smtpHost = environment["SMTP_HOST"]
        val smtpFrom = environment["SMTP_FROM"]
        val smtpPort = environment["SMTP_PORT"]?.toIntOrNull() ?: 587
        val smtpTls = environment["SMTP_TLS"] ?: "starttls"
        val smtpUser = environment["SMTP_USERNAME"]
        val smtpPassword = SecretSource.optional("SMTP_PASSWORD", environment)

        require(!smtpHost.isNullOrBlank() && !smtpFrom.isNullOrBlank()) {
            "SMTP_HOST ve SMTP_FROM production OTP icin zorunludur"
        }
        require(smtpPort in 1..65535) { "SMTP_PORT gecersiz" }
        require(smtpTls.lowercase() in setOf("starttls", "ssl")) {
            "SMTP_TLS production'da starttls veya ssl olmali"
        }
        if (!smtpUser.isNullOrBlank()) {
            require(!smtpPassword.isNullOrBlank()) { "SMTP_PASSWORD, SMTP_USERNAME ile zorunludur" }
        }
    }

    private val session: Session by lazy {
        val props = Properties().apply {
            put("mail.smtp.host", host)
            put("mail.smtp.port", port.toString())
            put("mail.smtp.connectiontimeout", "10000")
            put("mail.smtp.timeout", "10000")
            put("mail.smtp.writetimeout", "10000")
            when (tlsMode.lowercase()) {
                "ssl" -> {
                    put("mail.smtp.ssl.enable", "true")
                    put("mail.smtp.socketFactory.class", "javax.net.ssl.SSLSocketFactory")
                    put("mail.smtp.socketFactory.port", port.toString())
                }
                "starttls" -> {
                    put("mail.smtp.starttls.enable", "true")
                    put("mail.smtp.starttls.required", "true")
                }
                else -> { /* none */ }
            }
            if (!username.isNullOrBlank()) {
                put("mail.smtp.auth", "true")
            }
        }
        if (!username.isNullOrBlank()) {
            Session.getInstance(props, object : Authenticator() {
                override fun getPasswordAuthentication() = PasswordAuthentication(username, password)
            })
        } else {
            Session.getInstance(props)
        }
    }

    /**
     * E-posta gonderir. Bloklayan call — IO dispatcher'da cagrilmali.
     * @return true = basarili
     */
    fun sendMail(to: String, subject: String, htmlBody: String, textBody: String? = null): Boolean {
        if (!isConfigured) {
            log.warn("[Email] SMTP yapilandirilmamis — mail gonderilmedi")
            return false
        }
        return try {
            val message = MimeMessage(session).apply {
                setFrom(InternetAddress(fromAddress!!, "SecureChat"))
                setRecipient(Message.RecipientType.TO, InternetAddress(to))
                this.subject = subject
                if (textBody != null) {
                    val multipart = jakarta.mail.internet.MimeMultipart("alternative")
                    val textPart = jakarta.mail.internet.MimeBodyPart().apply {
                        setText(textBody, "UTF-8")
                    }
                    val htmlPart = jakarta.mail.internet.MimeBodyPart().apply {
                        setContent(htmlBody, "text/html; charset=UTF-8")
                    }
                    multipart.addBodyPart(textPart)
                    multipart.addBodyPart(htmlPart)
                    setContent(multipart)
                } else {
                    setContent(htmlBody, "text/html; charset=UTF-8")
                }
            }
            Transport.send(message)
            log.info("[Email] Gonderildi")
            true
        } catch (e: Exception) {
            log.error("[Email] Gonderim hatasi: {}", e.javaClass.simpleName)
            false
        }
    }
}
