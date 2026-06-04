package com.securechat.botapi.send

import com.securechat.botapi.auth.AuthenticatedClient

/**
 * Bir client'in belirli bir recipient'a gondermeye yetkili olup olmadigini
 * kontrol eder. Allow-list explicit; bos liste = "her sey yasak".
 *
 * Recipient kimligi:
 *  - "user:<uuid>"  → tek kisi
 *  - "group:<id>"   → grup (gruptaki uyelerin allow-list kontrolu BURADA YAPILMAZ;
 *                     sadece grup id allow-list'te mi diye bakar)
 */
object AllowListChecker {

    fun isAllowed(client: AuthenticatedClient, recipientRef: String): Boolean {
        if (recipientRef.isBlank()) return false
        return recipientRef in client.allowList
    }
}
