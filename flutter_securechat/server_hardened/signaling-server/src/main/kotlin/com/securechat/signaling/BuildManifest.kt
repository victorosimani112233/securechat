package com.securechat.signaling

import java.util.Properties
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("BuildManifest")

/**
 * Calisan artefaktin kimligi.
 *
 * Canli uctaki route seti kaynak agaciyla uyusmadiginda "hangi commit
 * calisiyor" sorusunun cevabi yoktu; incelenen guvenlik garantilerinin
 * production'da gecerli oldugu soylenemiyordu. Manifest image'a build
 * aninda gomulur ve operator bunu deploy kaydiyla karsilastirabilir.
 *
 * Icerikte secret yoktur: commit, build zamani ve beklenen migration
 * hedefi. Yine de yuzey operator'a ozeldir; tam commit'i anonim bir
 * istemciye vermek saldirgana kaynak esleme kolayligi saglar.
 */
object BuildManifest {

    private const val RESOURCE = "/build-info.properties"
    private const val UNKNOWN = "unknown"

    val commit: String
    val builtAt: String
    val migrationTarget: String

    init {
        val properties = Properties()
        val stream = BuildManifest::class.java.getResourceAsStream(RESOURCE)
        if (stream == null) {
            log.warn("[Build] build-info.properties bulunamadi; artefakt kimligi dogrulanamaz")
        } else {
            stream.use(properties::load)
        }
        commit = properties.getProperty("commit")?.takeIf { it.isNotBlank() } ?: UNKNOWN
        builtAt = properties.getProperty("builtAt")?.takeIf { it.isNotBlank() } ?: UNKNOWN
        migrationTarget =
            properties.getProperty("migrationTarget")?.takeIf { it.isNotBlank() } ?: UNKNOWN
    }

    /** Release kaydiyla karsilastirilabilir, secret icermeyen ozet. */
    fun asMap(): Map<String, String> = mapOf(
        "commit" to commit,
        "builtAt" to builtAt,
        "migrationTarget" to migrationTarget,
    )

    /**
     * Manifest eksikse artefaktin kaynagi kanitlanamaz. Production'da bu
     * sessizce gecilmez.
     */
    fun validate(environment: Map<String, String> = System.getenv()) {
        val production =
            environment["PRIVACY_PRODUCTION_MODE"]?.equals("true", ignoreCase = true) == true
        if (!production) return
        require(commit != UNKNOWN && migrationTarget != UNKNOWN) {
            "Production artefacts must carry a build manifest (commit + migration target)"
        }
    }
}
