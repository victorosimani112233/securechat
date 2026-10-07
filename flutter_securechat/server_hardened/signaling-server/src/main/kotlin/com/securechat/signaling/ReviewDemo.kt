package com.securechat.signaling

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.concurrent.atomic.AtomicInteger
import org.slf4j.LoggerFactory

/**
 * Store incelemesi icin demo hesap girisi.
 *
 * Apple ve Google inceleme ekipleri e-posta kutusuna erisemez; e-posta OTP'li
 * bir uygulamada calisan bir demo hesap ister. Bu yol yalniz acikca
 * listelenen e-postalarda, operatorun sectigi sabit kodu e-posta gondermeden
 * gecerli kilar. Sabit bir kod hesap ele gecirme ilkelidir; bu yuzden:
 *
 *  - Uc degiskenin (`REVIEW_DEMO_EMAILS`, `REVIEW_DEMO_OTP`,
 *    `REVIEW_DEMO_UNTIL`) hepsi yoksa yol kapalidir.
 *  - `REVIEW_DEMO_UNTIL` (YYYY-MM-DD, UTC gun sonu) gecince kendiliginden
 *    kapanir. Production profilinde bu tarih baslangicta en cok 30 gun
 *    ilerde olabilir (`ProductionDeploymentPolicy`).
 *  - Kod surec omru boyunca en cok [MAX_ISSUES] kez verilir. Her verilen kod
 *    en cok 5 deneme kabul ettigi icin tahmin sansi ~150/10^6 ile sinirlidir.
 *  - Normal OTP ile ayni dogrulama, deneme sayaci ve hiz sinirlari gecerlidir.
 */
object ReviewDemo {
    private val log = LoggerFactory.getLogger("ReviewDemo")

    const val MAX_EMAILS = 2
    const val MAX_ISSUES = 30
    const val MAX_PRODUCTION_DAYS = 30L

    data class Config(val emails: Set<String>, val code: String, val until: Instant)

    private val issued = AtomicInteger(0)

    @Volatile
    private var config: Config? = null

    fun initialize(environment: Map<String, String> = System.getenv()) {
        config = parse(
            emails = SecretSource.optional("REVIEW_DEMO_EMAILS", environment),
            code = SecretSource.optional("REVIEW_DEMO_OTP", environment),
            until = environment["REVIEW_DEMO_UNTIL"],
        )
        config?.let { log.warn("[REVIEW] Demo girisi acik: {} adres, bitis {}", it.emails.size, it.until) }
    }

    internal fun parse(emails: String?, code: String?, until: String?): Config? {
        if (emails.isNullOrBlank() && code.isNullOrBlank() && until.isNullOrBlank()) return null
        val list = emails.orEmpty().split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
        require(list.isNotEmpty() && list.size <= MAX_EMAILS) {
            "REVIEW_DEMO_EMAILS 1-$MAX_EMAILS adres icermeli"
        }
        require(code != null && code.matches(Regex("[0-9]{6}")) && code.toSet().size > 2) {
            "REVIEW_DEMO_OTP 6 haneli ve tekrar etmeyen bir kod olmali"
        }
        val end = runCatching { LocalDate.parse(until?.trim()) }.getOrNull()
            ?: error("REVIEW_DEMO_UNTIL YYYY-MM-DD olmali")
        return Config(list.toSet(), code, end.plusDays(1).atStartOfDay().toInstant(ZoneOffset.UTC))
    }

    /** Production baslangic kontrolu: acik demo yolu en cok 30 gun surebilir. */
    internal fun requireBoundedForProduction(environment: Map<String, String>, now: Instant = Instant.now()) {
        val parsed = parse(
            emails = SecretSource.optional("REVIEW_DEMO_EMAILS", environment),
            code = SecretSource.optional("REVIEW_DEMO_OTP", environment),
            until = environment["REVIEW_DEMO_UNTIL"],
        ) ?: return
        require(parsed.until <= now.plusSeconds(MAX_PRODUCTION_DAYS * 86_400 + 86_400)) {
            "REVIEW_DEMO_UNTIL production'da en cok $MAX_PRODUCTION_DAYS gun ilerde olabilir"
        }
    }

    fun isDemo(email: String, now: Instant = Instant.now()): Boolean {
        val active = config ?: return false
        return now < active.until && email.trim().lowercase() in active.emails
    }

    /**
     * Demo adresi icin sabit kodu verir ve sayaci artirir; demo degilse veya
     * kota/tarih dolduysa null (cagiran normal rastgele kod uretir).
     */
    fun issueCode(email: String, now: Instant = Instant.now()): String? {
        val active = config ?: return null
        if (!isDemo(email, now)) return null
        if (issued.incrementAndGet() > MAX_ISSUES) {
            log.warn("[REVIEW] Demo kod kotasi doldu; normal OTP'ye donuldu")
            return null
        }
        AuditLog.log(eventType = "REVIEW_DEMO_CODE_ISSUED")
        return active.code
    }

    internal fun resetForTest(value: Config?) {
        config = value
        issued.set(0)
    }
}
