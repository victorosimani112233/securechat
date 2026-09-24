package com.securechat.signaling

/**
 * Admission is capped at eight; promotion is optional and encrypted-only.
 * DTLS-SRTP remains endpoint-to-endpoint in mesh/TURN, but terminates at Janus.
 * No deployment acknowledgement can substitute for client frame encryption.
 */
object SfuPolicy {
    // Legacy configuration value retained for regression tests, not an override.
    const val REQUIRED_ACKNOWLEDGEMENT = "sfu-media-not-end-to-end-encrypted"
    const val MAX_PARTICIPANTS = 8

    fun meshCapacity(callType: String): Int {
        require(callType in setOf("VOICE", "VIDEO"))
        return MAX_PARTICIPANTS
    }

    /** Promote on the seventh joined participant, for voice as well as video. */
    fun sfuThreshold(callType: String): Int {
        require(callType in setOf("VOICE", "VIDEO"))
        return 6
    }

    fun canPromote(
        mediaEndToEndEncrypted: Boolean,
        environment: Map<String, String> = System.getenv(),
    ): Boolean = mediaEndToEndEncrypted && isEnabled(environment)

    fun isEnabled(environment: Map<String, String> = System.getenv()): Boolean =
        environment["SFU_ENABLED"]?.equals("true", ignoreCase = true) == true &&
            !environment["JANUS_WS_URL"].isNullOrBlank()

    fun validate(environment: Map<String, String> = System.getenv()) {
        if (environment["SFU_ENABLED"]?.equals("true", ignoreCase = true) != true) return
        require(!environment["JANUS_WS_URL"].isNullOrBlank()) {
            "SFU_ENABLED=true requires JANUS_WS_URL"
        }
        require(!environment["JANUS_PUBLIC_WS_URL"].isNullOrBlank()) {
            "SFU_ENABLED=true requires JANUS_PUBLIC_WS_URL pointing to the authenticated /janus gateway"
        }
        val internal = java.net.URI(environment.getValue("JANUS_WS_URL"))
        val public = java.net.URI(environment.getValue("JANUS_PUBLIC_WS_URL"))
        require(internal.scheme in setOf("ws", "wss") && internal.host != null &&
            internal.userInfo == null && internal.rawQuery == null && internal.fragment == null)
        require(public.scheme == "wss" && public.host != null && public.path == "/janus" &&
            public.rawQuery == null && public.userInfo == null && public.fragment == null) {
            "JANUS_PUBLIC_WS_URL must be wss://<trusted-host>/janus without credentials or query"
        }
    }
}
