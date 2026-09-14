package com.securechat.signaling

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

    @Volatile
    private var cached: List<PrivateDirectoryEntry>? = null

    @Volatile
    private var cachedVersion: Long = -1

    @Volatile
    private var cachedKeyId: String? = null

    @Volatile
    private var builtAtMillis: Long = 0

    fun entries(
        registry: UserRegistry,
        oprf: PrivateDirectoryOprf = PrivateDirectory.oprf,
        nowMillis: Long = System.currentTimeMillis(),
    ): List<PrivateDirectoryEntry> {
        val version = registry.membershipVersion()
        val current = cached
        if (current != null &&
            cachedVersion == version &&
            cachedKeyId == oprf.keyId &&
            nowMillis - builtAtMillis < TTL_MILLIS
        ) {
            return current
        }
        synchronized(lock) {
            val existing = cached
            if (existing != null &&
                cachedVersion == version &&
                cachedKeyId == oprf.keyId &&
                nowMillis - builtAtMillis < TTL_MILLIS
            ) {
                return existing
            }
            val built = build(registry, oprf)
            cached = built
            cachedVersion = version
            cachedKeyId = oprf.keyId
            builtAtMillis = nowMillis
            return built
        }
    }

    /** Test ve anahtar rotasyonu icin onbellegi bosaltir. */
    fun invalidate() {
        synchronized(lock) {
            cached = null
            cachedVersion = -1
            cachedKeyId = null
            builtAtMillis = 0
        }
    }

    internal fun paddedSize(realCount: Int, bucket: Int = PADDING_BUCKET): Int {
        require(bucket > 0) { "Invalid padding bucket" }
        // Bos bir sunucu bile bir kova dolusu kayit dondurur; aksi halde
        // "hic kullanici yok" durumu ayirt edilebilirdi.
        val buckets = (realCount / bucket) + 1
        return buckets * bucket
    }

    private fun build(
        registry: UserRegistry,
        oprf: PrivateDirectoryOprf,
    ): List<PrivateDirectoryEntry> {
        val real = registry.privateDirectorySnapshot().map { user ->
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
