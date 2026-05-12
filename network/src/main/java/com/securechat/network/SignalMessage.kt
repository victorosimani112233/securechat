package com.securechat.network

import com.securechat.network.model.CallAction
import com.securechat.network.model.CallType
import com.securechat.network.model.GroupAction
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Signaling sunucusu uzerinden iletilen mesaj tipleri.
 * WebSocket baglantisi uzerinden JSON olarak serialize/deserialize edilir.
 *
 * Her mesaj tipi farkli bir amaca hizmet eder:
 * - SdpOffer/SdpAnswer: WebRTC baglanti kurulumu
 * - IceCandidate: NAT traversal icin aday bilgisi
 * - EncryptedMessage: Signal Protocol ile sifrelenmis mesaj
 * - PreKeyBundleMessage: Ilk baglanti icin anahtar degisimi
 * - CallControl: Arama yasam dongusu kontrol mesajlari
 */
@Serializable
sealed class SignalMessage {
    abstract val senderId: String
    abstract val recipientId: String
    abstract val timestamp: Long

    /** WebRTC SDP Offer — baglanti baslatma istegi. */
    @Serializable
    @SerialName("sdp_offer")
    data class SdpOffer(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val sdp: String,
        val callType: CallType
    ) : SignalMessage()

    /** WebRTC SDP Answer — baglanti kabul yaniti. */
    @Serializable
    @SerialName("sdp_answer")
    data class SdpAnswer(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val sdp: String
    ) : SignalMessage()

    /** WebRTC ICE Candidate — NAT traversal icin aday bilgisi. */
    @Serializable
    @SerialName("ice_candidate")
    data class IceCandidate(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val candidate: String,
        val sdpMid: String?,
        val sdpMLineIndex: Int
    ) : SignalMessage()

    /** Signal Protocol ile sifrelenmis mesaj zarfi. */
    @Serializable
    @SerialName("encrypted_message")
    data class EncryptedMessage(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val envelope: String
    ) : SignalMessage()

    /** X3DH key agreement icin PreKey bundle mesaji. */
    @Serializable
    @SerialName("prekey_bundle")
    data class PreKeyBundleMessage(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val bundle: String
    ) : SignalMessage()

    /** Arama kontrol mesaji (calma, kabul, red, kapatma, mesgul). */
    @Serializable
    @SerialName("call_control")
    data class CallControl(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val action: CallAction,
        // Server ACK icin benzersiz ID — client retry icin kullanir.
        val messageId: String? = null,
        // Grup aramasinda: koordinator HANGUP gonderirken doldurulur — server SFU room
        // ve GroupCallSessionStore temizligi icin kullanir.
        val groupId: String? = null
    ) : SignalMessage()

    /**
     * Server'dan client'a — HANGUP/REJECT/BUSY/ACCEPT ulastiginin onayi.
     * Client retry'i durdurmak icin bu mesaji bekler.
     */
    @Serializable
    @SerialName("call_control_ack")
    data class CallControlAck(
        override val senderId: String = "server",
        override val recipientId: String = "",
        override val timestamp: Long,
        val messageId: String,
        val action: String
    ) : SignalMessage()

    /**
     * WebSocket uzerinden iletilen ses verisi.
     * WebRTC yerine dogrudan signaling kanali uzerinden ses akisi icin kullanilir.
     * PCM ses verisi Base64 ile encode edilir.
     */
    @Serializable
    @SerialName("audio_data")
    data class AudioData(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val data: String // Base64 encoded PCM ses verisi
    ) : SignalMessage()

    /**
     * WebSocket uzerinden iletilen video frame verisi.
     * Kamera goruntusu JPEG olarak sikistirilir ve Base64 ile encode edilir.
     * Dusuk cozunurluk (320x240) ve dusuk JPEG kalitesi (%25) ile bant genisligi optimize edilir.
     * Hedef: 5-8 FPS.
     */
    @Serializable
    @SerialName("video_data")
    data class VideoData(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val data: String, // Base64 encoded JPEG frame
        val width: Int,
        val height: Int
    ) : SignalMessage()

    /**
     * WebSocket uzerinden dosya transferi.
     * Kucuk dosyalar tek parca, buyuk dosyalar chunk'lar halinde gonderilir.
     * Resim, video, belge (pdf, word, zip, txt vb.) destekler.
     *
     * Chunk sistemi: transferId ayni olan parcalar birlestirilir.
     * chunkIndex=0'dan baslar, chunkIndex==totalChunks-1 son parcadir.
     * totalChunks=1 ise tek parca (geriye uyumlu).
     */
    @Serializable
    @SerialName("file_transfer")
    data class FileTransfer(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val fileName: String,
        val mimeType: String,
        val fileSize: Long,
        val data: String, // Base64 encoded dosya icerigi (veya chunk)
        val groupId: String? = null,
        val groupName: String? = null,
        val transferId: String? = null, // Chunk'lari eslestirmek icin benzersiz ID
        val chunkIndex: Int = 0, // Bu parcanin sirasi (0-based)
        val totalChunks: Int = 1, // Toplam parca sayisi (1 = tek parca)
        val caption: String? = null, // Medya altyazisi — alici tarafta ayni baloncukta gosterilir
        val isViewOnce: Boolean = false, // Tek gosterimlik medya bayragi
        val originalMessageId: String? = null // Gondericinin orijinal mesaj ID'si (delivery receipt + view-once edit icin)
    ) : SignalMessage()

    /**
     * Grup yonetimi bildirimleri.
     * Grup olusturma, uye ekleme/cıkarma, grup adı degistirme vb. islemler icin.
     */
    @Serializable
    @SerialName("group_notification")
    data class GroupNotification(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val groupId: String,
        val groupName: String,
        val action: GroupAction,
        val groupMembers: List<String>, // Grup uye listesi (tam liste)
        val targetMemberId: String? = null // ADD_MEMBER/REMOVE_MEMBER icin hedef uye
    ) : SignalMessage()

    /**
     * Mesaj iletim/okundu bilgisi (delivery receipt).
     * Alici cihaza ulastiginda DELIVERED, sohbet ekrani acildiginda READ gonderilir.
     */
    @Serializable
    @SerialName("delivery_receipt")
    data class DeliveryReceipt(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val messageId: String,
        val status: String // "DELIVERED" veya "READ"
    ) : SignalMessage()

    /**
     * Herkesten mesaj silme bildirimi.
     * Gonderici kendi mesajini herkesten sildiginde karsi tarafa iletilir.
     */
    @Serializable
    @SerialName("message_delete")
    data class MessageDelete(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val messageId: String
    ) : SignalMessage()

    /**
     * Mesaj duzenleme bildirimi.
     * Gonderici kendi mesajini duzenledikten sonra karsi tarafa iletilir.
     * Sadece 15 dakika icinde gonderilmis mesajlar duzenlenebilir.
     */
    @Serializable
    @SerialName("message_edit")
    data class MessageEdit(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val messageId: String,
        val newContent: String
    ) : SignalMessage()

    /**
     * Yazma gostergesi. Kullanici yazmaya basladiginda/biraktiginda karsi tarafa iletilir.
     */
    @Serializable
    @SerialName("typing_indicator")
    data class TypingIndicator(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val isTyping: Boolean
    ) : SignalMessage()

    /**
     * Sureli mesaj zamanlayici ayari.
     * Bir konusmada sureli mesaj modu degistiginde karsi tarafa bildirilir.
     * duration 0 ise sureli mesaj kapali demektir.
     * conversationId: birebir icin senderId, grup icin groupId
     */
    @Serializable
    @SerialName("disappearing_timer")
    data class DisappearingTimer(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val duration: Long, // milisaniye, 0 = kapali
        val conversationId: String = "" // bos ise senderId kullanilir (geriye uyumluluk)
    ) : SignalMessage()

    /**
     * Mesaj reaksiyonu (emoji).
     * Kullanici bir mesaja emoji ile tepki verdiginde karsi tarafa iletilir.
     * remove=true ise mevcut reaksiyon kaldirilir.
     */
    @Serializable
    @SerialName("message_reaction")
    data class MessageReaction(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val messageId: String,
        val emoji: String,
        val remove: Boolean = false,
        val groupId: String? = null
    ) : SignalMessage()

    /**
     * Sunucu tarafinda grup mesaj dagitimi (fan-out).
     * Sender tek mesaj gonderir, sunucu her uye icin ayri mesaj olusturur.
     * recipientPayloads: {userId -> sifrelenmis envelope} seklinde her uyenin payloadi.
     */
    @Serializable
    @SerialName("group_message_fanout")
    data class GroupMessageFanout(
        override val senderId: String,
        override val recipientId: String = "server", // Sunucu isleyecek
        override val timestamp: Long,
        val groupId: String,
        val recipientPayloads: Map<String, String> // userId -> envelope
    ) : SignalMessage()

    /**
     * SFU room olusturuldu bildirimi.
     * 4+ katilimcili grup aramasinda sunucu Janus VideoRoom olusturur ve bu bilgiyi gonderir.
     * Client bu bilgiyle mesh yerine Janus SFU'ya baglanir.
     */
    @Serializable
    @SerialName("sfu_room_created")
    data class SfuRoomCreated(
        override val senderId: String = "server",
        override val recipientId: String = "broadcast",
        override val timestamp: Long,
        val groupId: String,
        val roomId: Long,
        val janusWsUrl: String,
        val apiSecret: String = ""
    ) : SignalMessage()

    /**
     * Sunucu kapanma bildirimi. Graceful shutdown sirasinda gonderilir.
     * Client bu mesaji alinca reconnect oncesi 5sn bekler.
     */
    @Serializable
    @SerialName("server_shutdown")
    data class ServerShutdown(
        override val senderId: String = "server",
        override val recipientId: String = "broadcast",
        override val timestamp: Long,
        val message: String = ""
    ) : SignalMessage()

    /** Cevrimici durum bildirimi. Sunucu tarafindan subscribe olan istemcilere gonderilir. */
    @Serializable
    @SerialName("presence_update")
    data class PresenceUpdate(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val isOnline: Boolean,
        val lastSeen: Long,
        val hideLastSeen: Boolean = false
    ) : SignalMessage()

    /** Belirli bir kullanicinin presence durumuna abone olma istegi. Sunucu tarafindan islenir. */
    @Serializable
    @SerialName("presence_subscribe")
    data class PresenceSubscribe(
        override val senderId: String,
        override val recipientId: String, // izlenmek istenen kullanici
        override val timestamp: Long
    ) : SignalMessage()

    /** Presence aboneligini iptal etme istegi. Sunucu tarafindan islenir. */
    @Serializable
    @SerialName("presence_unsubscribe")
    data class PresenceUnsubscribe(
        override val senderId: String,
        override val recipientId: String, // abonelik iptal edilecek kullanici
        override val timestamp: Long
    ) : SignalMessage()

    /**
     * Grup arama davetiyesi. Arayan tum grup uyelerine gonderir.
     * Her uye icin ayri mesaj gonderilir (recipientId = uye ID'si).
     * Mesh WebRTC: Her katilimci birbiriyle dogrudan PeerConnection kurar.
     */
    @Serializable
    @SerialName("group_call_invite")
    data class GroupCallInvite(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val groupId: String,
        val callType: CallType,
        val callId: String,
        val participants: List<String> // Tum davet edilen katilimcilar (arayan dahil)
    ) : SignalMessage()

    /**
     * Grup aramasina yeni uye katildi bildirimi.
     * Arayan (koordinator) mevcut katilimcilara gonderir.
     * Mevcut katilimcilar yeni uyeye PeerConnection kurar.
     */
    @Serializable
    @SerialName("group_call_member_joined")
    data class GroupCallMemberJoined(
        override val senderId: String,
        override val recipientId: String,
        override val timestamp: Long,
        val groupCallId: String,
        val joinedMemberId: String
    ) : SignalMessage()

    /**
     * Aktif grup aramasina sonradan katilim istegi.
     * Yeni katilan kullanici tarafindan koordinatore gonderilir.
     * Koordinator validate edip onGroupMemberAccepted akisini tetikler.
     */
    @Serializable
    @SerialName("group_call_join_request")
    data class GroupCallJoinRequest(
        override val senderId: String,
        override val recipientId: String, // Koordinator ID'si
        override val timestamp: Long,
        val groupId: String,
        val callId: String,
        val callType: CallType
    ) : SignalMessage()

    /**
     * Grup icin aktif arama durumu sorgusu.
     * Istemci ChatScreen acildiginda sunucuya gonderir; sunucu cevaplar.
     * recipientId = "server" sabit string'i.
     */
    @Serializable
    @SerialName("group_call_status_query")
    data class GroupCallStatusQuery(
        override val senderId: String,
        override val recipientId: String, // "server"
        override val timestamp: Long,
        val groupId: String
    ) : SignalMessage()

    /**
     * Aktif grup aramasi durum cevabi (sunucudan istemciye).
     * isActive=false ise diger alanlar null/bos.
     * mode: "MESH" veya "SFU". SFU modunda sfuRoomId/janusWsUrl/apiSecret doludur.
     */
    @Serializable
    @SerialName("group_call_status_response")
    data class GroupCallStatusResponse(
        override val senderId: String, // "server"
        override val recipientId: String,
        override val timestamp: Long,
        val groupId: String,
        val isActive: Boolean,
        val callId: String? = null,
        val coordinatorId: String? = null,
        val callType: CallType? = null,
        val participants: List<String> = emptyList(),
        val mode: String? = null, // "MESH" veya "SFU"
        val sfuRoomId: Long? = null,
        val janusWsUrl: String? = null,
        val apiSecret: String? = null
    ) : SignalMessage()
}
