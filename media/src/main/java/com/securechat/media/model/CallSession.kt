package com.securechat.media.model

import com.securechat.network.model.CallType

/**
 * Aktif bir arama oturumunun tum bilgilerini tutan veri sinifi.
 *
 * @property callId Benzersiz arama kimlik numarasi (UUID)
 * @property peerId Karsi tarafin kullanici ID'si
 * @property callType Arama tipi: sesli veya goruntulu
 * @property direction Arama yonu: gelen veya giden
 * @property state Aramanin mevcut durumu
 * @property startTime Aramanin baglanti kuruldugu zaman (epoch ms), null ise henuz baglanilmadi
 * @property duration Aramanin suresi (ms), null ise henuz sonlanmadi
 * @property isMuted Mikrofon sessiz mi
 * @property isSpeakerOn Hoparlor acik mi
 * @property isCameraEnabled Kamera acik mi (sadece video aramalar icin anlamli)
 * @property isUsingFrontCamera On kamera mi kullaniliyor
 */
data class CallSession(
    val callId: String,
    val peerId: String,
    val callType: CallType,
    val direction: CallDirection,
    val state: CallState,
    val startTime: Long? = null,
    val duration: Long? = null,
    val isMuted: Boolean = false,
    val isSpeakerOn: Boolean = false,
    val isCameraEnabled: Boolean = true,
    val isUsingFrontCamera: Boolean = true
)
