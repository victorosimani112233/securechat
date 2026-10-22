package com.securechat.signaling

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/**
 * Padded ve onbelleklenmis private-directory snapshot'i.
 *
 * Iki sorun kapatilir:
 *
 *  1. **Kullanici sayisi sizintisi.** Yanit her hesaba ayni listeyi verir,
 *     dolayisiyla eleman sayisi dogrudan kayitli hesap sayisidir. Kimlik
 *     dogrulamis herhangi bir istemci sunucunun buyuklugunu ve gunluk buyume
 *     hizini olcebiliyordu. Liste artik bir kova sinirina yuvarlanir; sayim
 *     yalniz kova genisligi kadar hassastir.
 *  2. **Istek basina O(N).** Her istek tum kayitlari yeniden muhurluyordu.
 *     Liste zaten herkes icin ayni oldugu icin bir kez uretilip uyelik
 *     degisene kadar (ya da TTL dolana kadar) paylasilir.
 *
 * Onbellek gizlilik acisindan notrdur: her istemci zaten ayni listeyi alir,
 * dolayisiyla paylasilan kopya yeni bir bilgi vermez.
 */
object DirectorySnapshotCache {

    /** Eleman sayisi bu katlara yuvarlanir. */
    const val PADDING_BUCKET = 256

    /** Onbellek yenileme ust siniri; uyelik degisimi zaten aninda gecersiz kilar. */
    internal const val TTL_MILLIS = 60_000L

    private val lock = Any()

    /** Paylasilan liste ve listeden cikarilan anahtarsiz hesaplar birlikte tutulur. */
    private class Built(
        val entries: List<PrivateDirectoryEntry>,
        val hidden: Set<String>?,
        val version: Long,
        val keyId: String,
        val builtAtMillis: Long,
        val etag: String,
    )

    /** Isteyen hesabin alacagi liste ve (paylasilan listeyse) ETag'i. */
    class SnapshotView(val entries: List<PrivateDirectoryEntry>, val etag: String?)

    /**
     * ETag'e katilir; sunucu yeniden baslayinca surum sayaci sifirlandigi
     * icin eski bir ETag yeni bir listeyle cakisamaz.
     */
    private val instanceNonce = ByteArray(16).also(SecureRandom()::nextBytes)

    @Volatile
    private var cached: Built? = null

    fun entries(
        registry: UserRegistry,
        oprf: PrivateDirectoryOprf = PrivateDirectory.oprf,
        nowMillis: Long = System.currentTimeMillis(),
        keylessUsers: () -> Set<String>? = OlmPreKeyStore::keylessUsers,
    ): List<PrivateDirectoryEntry> = built(registry, oprf, nowMillis, keylessUsers).entries

    /**
     * Isteyen hesabin gordugu liste: paylasilan liste, hesap anahtarsiz
     * oldugu icin listeden cikarildiysa kendi kaydiyla birlikte.
     *
     * Yeni kayit numarasini Olm anahtarlarindan once alir ve hemen ardindan
     * kendini rehberde arar; kendi kaydini goremezse kurulum durur. Kayit
     * yalniz sahibine eklenir; sahibi numarasini ve kimligini zaten bilir.
     */
    fun entriesFor(
        requesterId: String,
        registry: UserRegistry,
        oprf: PrivateDirectoryOprf = PrivateDirectory.oprf,
        nowMillis: Long = System.currentTimeMillis(),
        keylessUsers: () -> Set<String>? = OlmPreKeyStore::keylessUsers,
    ): List<PrivateDirectoryEntry> =
        snapshotFor(requesterId, registry, oprf, nowMillis, keylessUsers).entries

    /**
     * [entriesFor] ile ayni liste ve ETag.
     *
     * Liste her yeniden kurulusta (en gec [TTL_MILLIS]) rastgele nonce ile
     * yeniden muhurlenir; baytlar degisir ama anlami degismez. ETag bu
     * yuzden baytlardan degil anlamdan uretilir (anahtar, uyelik surumu,
     * gizlenen hesaplar): ayniysa istemcinin elindeki eski kopya ayni
     * etiketleri ve ayni kimlikleri acar, yeniden indirmesi gerekmez.
     * Kendi kaydi eklenen (anahtarsiz) hesap ETag almaz.
     */
    fun snapshotFor(
        requesterId: String,
        registry: UserRegistry,
        oprf: PrivateDirectoryOprf = PrivateDirectory.oprf,
        nowMillis: Long = System.currentTimeMillis(),
        keylessUsers: () -> Set<String>? = OlmPreKeyStore::keylessUsers,
    ): SnapshotView {
        val built = built(registry, oprf, nowMillis, keylessUsers)
        val entries = withOwnEntry(
            built.entries,
            built.hidden,
            registry.directoryEntryOf(requesterId),
            oprf,
        )
        return SnapshotView(entries, if (entries === built.entries) built.etag else null)
    }

    internal fun withOwnEntry(
        shared: List<PrivateDirectoryEntry>,
        hidden: Set<String>?,
        requester: RegisteredUser?,
        oprf: PrivateDirectoryOprf,
    ): List<PrivateDirectoryEntry> {
        if (requester == null || hidden == null || requester.userId !in hidden) return shared
        if (requester.directoryKeyId != oprf.keyId) return shared
        return (shared + oprf.sealUserId(requester.directoryToken, requester.userId))
            .sortedBy { it.label }
    }

    private fun built(
        registry: UserRegistry,
        oprf: PrivateDirectoryOprf,
        nowMillis: Long,
        keylessUsers: () -> Set<String>?,
    ): Built {
        val version = registry.membershipVersion()
        cached?.takeIf { it.isFresh(version, oprf.keyId, nowMillis) }?.let { return it }
        synchronized(lock) {
            cached?.takeIf { it.isFresh(version, oprf.keyId, nowMillis) }?.let { return it }
            val hidden = keylessUsers()
            val built = Built(
                entries = build(registry, oprf, hidden),
                hidden = hidden,
                version = version,
                keyId = oprf.keyId,
                builtAtMillis = nowMillis,
                etag = etagOf(oprf.keyId, version, hidden),
            )
            cached = built
            return built
        }
    }

    private fun etagOf(keyId: String, version: Long, hidden: Set<String>?): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(instanceNonce)
        digest.update("$keyId\u0000$version\u0000".toByteArray())
        if (hidden == null) {
            digest.update("*".toByteArray())
        } else {
            for (userId in hidden.sorted()) digest.update("$userId\u0000".toByteArray())
        }
        val tag = Base64.getUrlEncoder().withoutPadding().encodeToString(digest.digest())
        return "\"${tag.take(27)}\""
    }

    private fun Built.isFresh(version: Long, keyId: String, nowMillis: Long): Boolean =
        this.version == version && this.keyId == keyId && nowMillis - builtAtMillis < TTL_MILLIS

    /** Test ve anahtar rotasyonu icin onbellegi bosaltir. */
    fun invalidate() {
        synchronized(lock) {
            cached = null
        }
    }

    internal fun paddedSize(realCount: Int, bucket: Int = PADDING_BUCKET): Int {
        require(bucket > 0) { "Invalid padding bucket" }
        // Bos bir sunucu bile bir kova dolusu kayit dondurur; aksi halde
        // "hic kullanici yok" durumu ayirt edilebilirdi.
        val buckets = (realCount / bucket) + 1
        return buckets * bucket
    }

    /**
     * Olm kimligi olmayan hesaplar rehberde "ELÇİM'de" gorunmez.
     *
     * Iki tur: vodozemac gecisinden beri acilmamis, yalniz libsignal kimligi
     * olan hesap ve numarayi alip anahtar yuklemeden yarim kalmis kayit.
     * Ikisine de mesaj ya da grup daveti sifrelenemez; kisi davet listesine
     * duser. Listede gorunselerdi ayni numarayla yeniden kayit olan
     * istemci numarayi "baskasinda" sanip sunucuya devir istegi bile
     * gondermeden dururdu. Anahtarini yayinlayan hesap en gec [TTL_MILLIS]
     * icinde gorunur. Sorgu basarisizsa ([hidden] null) herkes listelenir.
     */
    internal fun messageable(
        users: List<RegisteredUser>,
        hidden: Set<String>?,
    ): List<RegisteredUser> =
        if (hidden == null) users else users.filter { it.userId !in hidden }

    private fun build(
        registry: UserRegistry,
        oprf: PrivateDirectoryOprf,
        hidden: Set<String>?,
    ): List<PrivateDirectoryEntry> {
        val real = messageable(registry.privateDirectorySnapshot(), hidden).map { user ->
            oprf.sealUserId(user.directoryToken, user.userId)
        }
        val target = paddedSize(real.size)
        val entries = ArrayList<PrivateDirectoryEntry>(target)
        entries += real
        for (index in real.size until target) {
            // Tohum sunucu anahtariyla HMAC'lenir: istemci bir etiketin dolgu
            // olup olmadigini hesaplayamaz, fakat etiket rebuild'ler arasinda
            // sabit kalir.
            entries += oprf.decoyEntry(
                ServerPrivacy.blindIndex("directory-decoy", "${oprf.keyId} $index"),
            )
        }
        // Dolgular listenin sonunda kumelenmemeli: sira, gercek kayit sayisini
        // ima etmemesi icin etikete gore deterministik olarak siralanir.
        return entries.sortedBy { it.label }
    }
}
