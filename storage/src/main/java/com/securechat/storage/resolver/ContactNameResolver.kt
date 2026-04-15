package com.securechat.storage.resolver

/**
 * Telefon numarasından kişi adını çözümleme interface'i.
 * Storage modülünün contacts modülüne doğrudan bağımlı olmaması için kullanılır.
 */
interface ContactNameResolver {

    /**
     * Telefon numarasından görüntüleme adını döner.
     * @param phoneNumber Telefon numarası (genellikle peerId)
     * @return Kişi adı veya formatted telefon numarası
     */
    suspend fun resolveDisplayName(phoneNumber: String): String
}