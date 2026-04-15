package com.securechat.network.model

import kotlinx.serialization.Serializable

/**
 * Arama tipi: sesli veya goruntulu.
 */
@Serializable
enum class CallType {
    VOICE,
    VIDEO
}
