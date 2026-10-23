package com.securechat.signaling

/**
 * Sunucunun hangi dagitim profilinde calistigi.
 *
 * Kod tabani bastan iki profil varsayacak sekilde yazilmisti:
 * `BuildManifest.validate` ve OPRF backend secimi
 * production degilse erken doner. Ancak `ProductionDeploymentPolicy` tek bir
 * `require` ile `PRIVACY_PRODUCTION_MODE=true` zorunlu kildigi icin pratikte
 * tek profil kalmisti: yerel bir calistirma da HSM, dogrulanmis PostgreSQL
 * TLS'i, TLS'li SMTP ve cevrimdisi imzalanmis Sealed Sender sertifikasi
 * istiyordu.
 *
 * Bunun bedeli guvenlik degil, guvenligin yanlis yerde durmasidir: gelistirme
 * ve test icin kurulum o kadar pahali hale gelir ki insanlar dogrulama
 * yapmayi birakir ya da kapilari kalici olarak devre disi birakmanin bir
 * yolunu bulur.
 *
 * Bu yuzden profil **acikca** secilir ve gelistirme profili yalniz
 * *altyapi* kapilarini gevsetir:
 *
 * | Gevseyen (altyapi) | Gevsemeyen (kriptografi) |
 * |---|---|
 * | PostgreSQL `sslmode=verify-full` | `PRIVACY_INDEX_KEY` / `OFFLINE_QUEUE_ENCRYPTION_KEY` zorunlulugu |
 * | PKCS#11 HSM (PKCS#8 dosya anahtari yeter) | Anahtarlarin 32 byte ve amac-ayrimli olmasi |
 * | TLS'li SMTP | Offline kuyrugun AEAD ile sifrelenmesi |
 * | Firebase mutlak yolu | Duz metin kuyruk yasagi |
 * | TURN TLS zorunlulugu | Gercek libsignal Sealed Sender |
 * | Cevrimdisi Sealed Sender sertifikasi | JWT imzalama secret'i gucu |
 *
 * Yani gelistirme profilinde de sunucu mesaji okuyamaz. Degisen tek sey,
 * uretim altyapisinin yerine yerel esdegerlerinin kabul edilmesidir.
 */
object DeploymentProfile {

    private const val DEVELOPMENT_VALUE = "development"

    /**
     * Gelistirme profili yalniz acik ve tek anlamli bir beyanla secilir.
     *
     * `SECURECHAT_PROFILE` verilmemisse davranis degismez: production
     * kapilarinin tamami calisir. Bu, mevcut dagitimlarin yanlislikla
     * gevsemesini imkansiz kilar.
     */
    fun isDevelopment(environment: Map<String, String> = System.getenv()): Boolean =
        environment["SECURECHAT_PROFILE"]?.trim()?.lowercase() == DEVELOPMENT_VALUE

    /**
     * Celiskili bir profil beyani reddedilir.
     *
     * `SECURECHAT_PROFILE=development` ve `PRIVACY_PRODUCTION_MODE=true`
     * birlikte verilirse hangisinin kazandigi okuyucuya gore degisir; boyle
     * bir belirsizlik guvenlik kapisinda kabul edilemez.
     */
    fun requireConsistent(environment: Map<String, String> = System.getenv()) {
        if (!isDevelopment(environment)) return
        require(
            environment["PRIVACY_PRODUCTION_MODE"]?.equals("true", ignoreCase = true) != true,
        ) {
            "SECURECHAT_PROFILE=development and PRIVACY_PRODUCTION_MODE=true are contradictory"
        }
    }

    /** Baslangicta bir kez, karistirilmayacak bicimde yazilir. */
    fun describe(environment: Map<String, String> = System.getenv()): String =
        if (isDevelopment(environment)) {
            "DEVELOPMENT — altyapi kapilari gevsetildi, bu profil production'a acilmamalidir"
        } else {
            "PRODUCTION"
        }
}
