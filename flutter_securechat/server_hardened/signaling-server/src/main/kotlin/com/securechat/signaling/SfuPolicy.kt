package com.securechat.signaling

import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("SfuPolicy")

/**
 * Janus SFU'nun medya gizliligi sinirindaki yeri.
 *
 * P2P/TURN yolunda DTLS-SRTP iki uc arasinda kalir ve TURN yalniz ciphertext
 * relay eder. SFU yolunda ise WebRTC oturumu Janus'ta **sonlanir**: ayri bir
 * uygulama-katmani medya sifrelemesi (SFrame veya FrameCryptor) olmadan
 * Janus host/process'i ses ve goruntu icin guven sinirinin **icindedir**.
 *
 * Kaynak agacinda boyle bir katman yoktur. Bu yuzden SFU varsayilan olarak
 * kapalidir ve production'da acilmasi operatorun bu sinirI acikca kabul
 * etmesini gerektirir. Kapaliyken grup aramalari mesh modda kalir;
 * kullaniciya sessizce zayif bir garanti verilmez.
 */
object SfuPolicy {

    /** Kabulun anlamini gizlemeyen, kopyalanmasi bilincli olan deger. */
    const val REQUIRED_ACKNOWLEDGEMENT = "sfu-media-not-end-to-end-encrypted"

    /**
     * Protokol tavani. Mesh'te her cihaz N-1 encode ve N-1 upload yapar;
     * SFU'da tek encode/upload yeter. Tavan bu yuzden moda baglidir.
     */
    const val MAX_PARTICIPANTS = 32

    /** Mesh'in pratik tavani; SFU esiginin ustunde arama kullanilamaz hale gelir. */
    fun meshCapacity(callType: String): Int = if (callType.equals("VIDEO", true)) 6 else 10

    fun sfuThreshold(callType: String): Int = meshCapacity(callType)

    /**
     * Bir aramanin SFU'ya gecebilmesi.
     *
     * Tum katilimcilar medya frame sifrelemesi bildiriyorsa Janus yalniz
     * ciphertext yonlendirir ve medya guven siniri disinda kalir; bu durumda
     * operator kabul beyani gerekmez. Biri bile bildirmiyorsa medya Janus'ta
     * aciktir ve ancak acik kabulle gecilebilir.
     */
    fun canPromote(
        mediaEndToEndEncrypted: Boolean,
        environment: Map<String, String> = System.getenv(),
    ): Boolean {
        if (environment["JANUS_WS_URL"].isNullOrBlank()) return false
        if (environment["SFU_ENABLED"]?.equals("true", ignoreCase = true) != true) return false
        if (mediaEndToEndEncrypted) return true
        return isEnabled(environment)
    }

    fun isEnabled(environment: Map<String, String> = System.getenv()): Boolean {
        if (environment["JANUS_WS_URL"].isNullOrBlank()) return false
        if (environment["SFU_ENABLED"]?.equals("true", ignoreCase = true) != true) return false
        val production =
            environment["PRIVACY_PRODUCTION_MODE"]?.equals("true", ignoreCase = true) == true
        if (!production) return true
        return environment["SFU_MEDIA_BOUNDARY_ACK"]?.trim() == REQUIRED_ACKNOWLEDGEMENT
    }

    /**
     * Production'da SFU acilmak isteniyorsa kabul beyani zorunludur; eksik
     * beyan sessizce "kapali"ya donusmez, startup durur.
     */
    fun validate(environment: Map<String, String> = System.getenv()) {
        val requested = environment["SFU_ENABLED"]?.equals("true", ignoreCase = true) == true
        if (!requested) return
        require(!environment["JANUS_WS_URL"].isNullOrBlank()) {
            "SFU_ENABLED=true requires JANUS_WS_URL"
        }
        val production =
            environment["PRIVACY_PRODUCTION_MODE"]?.equals("true", ignoreCase = true) == true
        if (!production) return
        require(environment["SFU_MEDIA_BOUNDARY_ACK"]?.trim() == REQUIRED_ACKNOWLEDGEMENT) {
            "Enabling the SFU in production requires SFU_MEDIA_BOUNDARY_ACK=" +
                REQUIRED_ACKNOWLEDGEMENT
        }
        log.warn(
            "[SFU] Medya, uygulama katmaninda sifrelenmemis olarak Janus'tan gecer; " +
                "bu sinir operator tarafindan kabul edildi",
        )
    }
}
