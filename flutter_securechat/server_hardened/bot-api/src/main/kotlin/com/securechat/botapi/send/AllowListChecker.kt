package com.securechat.botapi.send

import com.securechat.botapi.auth.AuthenticatedClient

/**
 * Bir client'in belirli bir aliciya gondermeye yetkili olup olmadigini
 * kontrol eder. Allow-list explicit; bos liste = "her sey yasak".
 *
 * Recipient kimligi:
 *  - "user:<uuid>"  → tek kisi
 *  - "group:<token>" → grup
 *
 * Grup gonderiminde **grup tokeni tek basina yetki degildir**. Onceki
 * davranista yalniz `recipientRef` allow-list ile karsilastiriliyordu; bu
 * durumda izinli bir grup tokenini bilen bir client istegin govdesine
 * istedigi UUID'leri koyabiliyor ve bot o kisilere mesaj gonderiyordu.
 * Bu yuzden her alici ayrica `user:<uuid>` olarak izinli olmalidir.
 *
 * Sunucu kalici grup uyeligi tutmadigi icin gercek uyelik burada
 * dogrulanamaz; kalici bir grup grafigi olusturmak gizlilik sozlesmesine
 * aykiri olurdu. Kalici cozum device-signed, kisa omurlu bir group send
 * capability'sidir (bkz. SERVER_HARDENING_PROGRESS.md).
 */
object AllowListChecker {

    fun isAllowed(client: AuthenticatedClient, recipientRef: String): Boolean {
        if (recipientRef.isBlank()) return false
        return recipientRef in client.allowList
    }

    /**
     * Grup fanout'unun her alicisi icin ayri yetki kontrolu.
     *
     * @return izinli olmayan ilk alicinin bulunup bulunmadigi; tum alicilar
     *   izinliyse true.
     */
    fun areRecipientsAllowed(
        client: AuthenticatedClient,
        recipientUserIds: List<String>,
    ): Boolean {
        if (recipientUserIds.isEmpty()) return false
        return recipientUserIds.all { "user:$it" in client.allowList }
    }
}
