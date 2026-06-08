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

    /** Grup admin listesi güncellendi (yükseltme) */
    UPDATE_ADMIN,

    /** Grup admin yetkisi alındı (düşürme) */
    DEMOTE_ADMIN,

    /**
     * Sohbet dışa aktarma izni değiştirildi (sadece admin tarafından).
     * `targetMemberId` alanı "true" / "false" stringi olarak yeni durumu taşır
     * (yeni alan eklemeden mevcut wire formatına geri-uyumlu kalmak için).
     */
    UPDATE_EXPORT_POLICY
}