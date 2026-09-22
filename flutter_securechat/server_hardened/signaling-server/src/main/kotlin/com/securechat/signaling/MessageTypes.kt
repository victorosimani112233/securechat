package com.securechat.signaling

/**
 * Cerceve turunun okunmasi.
 *
 * Bu siniflandirma daha once yalniz `FcmPushSender` uzerinden yapiliyordu.
 * Push yapilandirilmamis bir dagitimda (`fcm: disabled` desteklenen bir
 * durumdur) tur `null` kaliyor ve uc davranis birden bozuluyordu:
 *
 *  - gecici sinyaller (typing, presence) filtrelenmiyor ve kalici offline
 *    kuyruga yaziliyordu — davranis verisi tutmama sozlesmesinin ihlali;
 *  - `file_transfer` mesaj kovasina dusuyordu, yani dosya parcalari icin
 *    konan dusuk byte tavani ve kisa TTL uygulanmiyordu;
 *  - bekleyen cagri sinyallerinin temizligi hicbir kaydi silmiyordu.
 *
 * Siniflandirma bu yuzden push tasiyicisindan bagimsizdir.
 */
object MessageTypes {

    /** Kuyruga hic yazilmamasi gereken, yalniz anlik anlami olan turler. */
    val TRANSIENT = setOf(
        "typing_indicator",
        "presence_update",
        "presence_subscribe",
        "presence_unsubscribe",
        "audio_data",
        "video_data",
    )

    /** Ayri kovada, dusuk tavan ve kisa TTL ile tutulan turler. */
    const val FILE_TRANSFER = "file_transfer"

    /** Arayan vazgectiginde temizlenmesi gereken sinyaller. */
    val PENDING_CALL = setOf("sdp_offer", "sdp_answer", "ice_candidate", "call_control")

    /** Message-only background sockets must leave these frames for a call handler. */
    val REQUIRES_CALL_HANDLER = PENDING_CALL + "group_call_invite"

    private val TYPE_FIELD = """"type"\s*:\s*"([^"]+)"""".toRegex()

    /**
     * @return cercevenin `type` alani; okunamiyorsa null.
     *
     * Tam JSON ayristirmasi gereksizdir: alan sunucu tarafinda zaten
     * sanitize edilmis bir cerceveden okunur.
     */
    fun extract(messageJson: String): String? =
        try {
            TYPE_FIELD.find(messageJson)?.groupValues?.get(1)
        } catch (_: Exception) {
            null
        }

    fun isTransient(messageJson: String): Boolean = extract(messageJson) in TRANSIENT

    fun isFileTransfer(messageJson: String): Boolean = extract(messageJson) == FILE_TRANSFER
}
