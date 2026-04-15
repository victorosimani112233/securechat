package com.securechat.network.model

import kotlinx.serialization.Serializable

/**
 * Grup yönetimi aksiyonları.
 * GroupNotification mesajında kullanılır.
 */
@Serializable
enum class GroupAction {
    /** Grup oluşturuldu - tüm üyelere bildirim gönderilir */
    CREATE,

    /** Gruba yeni üye eklendi */
    ADD_MEMBER,

    /** Gruptan üye çıkarıldı */
    REMOVE_MEMBER,

    /** Kullanıcı kendi isteğiyle gruptan ayrıldı */
    LEAVE_GROUP,

    /** Grup ismi değiştirildi */
    UPDATE_NAME,

    /** Grup admin listesi güncellendi */
    UPDATE_ADMIN
}