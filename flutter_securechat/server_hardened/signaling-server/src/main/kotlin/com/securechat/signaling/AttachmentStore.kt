package com.securechat.signaling

import io.ktor.utils.io.ByteReadChannel
import io.ktor.utils.io.core.isEmpty
import io.ktor.utils.io.core.readBytes
import io.ktor.utils.io.readRemaining
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.PosixFilePermissions
import java.security.SecureRandom
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.slf4j.LoggerFactory

private val attachmentLog = LoggerFactory.getLogger("AttachmentStore")

/**
 * Istemcide sifrelenmis ek dosyalari (fotograf, video, belge).
 *
 * Onceki yol dosyayi 128 KB'lik parcalara bolup her parcayi her aliciya
 * ayri sifreleyerek WebSocket'ten gonderiyordu: dosya telde ~1,8 kat
 * buyuyordu, grupta uye sayisi kadar tekrarlaniyordu ve cevrimdisi aliciya
 * giden parcalar sunucuda yalniz 5 dakika tutuluyordu. Artik istemci dosyayi
 * rastgele bir anahtarla BIR KEZ sifreler ve buraya yukler; alicilara yalniz
 * uctan uca sifreli kucuk bir isaretci (kimlik, anahtar, ozet) gider.
 *
 * Sunucu yalniz sifreli baytlari ve rastgele 256 bitlik kimligi gorur; ad,
 * tur, anahtar ve alicilar sifreli isaretcidedir. Dosyalar [ttlMillis] sonra
 * silinir.
 */
class AttachmentStore(
    private val directory: Path,
    private val ttlMillis: Long,
    private val maxBytes: Long = MAX_BYTES,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val random = SecureRandom()

    init {
        Files.createDirectories(directory)
        runCatching {
            Files.setPosixFilePermissions(directory, PosixFilePermissions.fromString("rwx------"))
        }
    }

    fun isValidId(id: String): Boolean = ID_PATTERN.matches(id)

    /**
     * Govdeyi diske akitarak yazar; tam [declaredLength] bayt gelmezse ya da
     * sinir asilirsa yarim dosya silinir ve [IllegalArgumentException] atilir.
     */
    suspend fun write(body: ByteReadChannel, declaredLength: Long): String {
        require(declaredLength in 1..maxBytes) { "Invalid attachment size" }
        val id = newId()
        val partial = directory.resolve("$id.part")
        try {
            var written = 0L
            withContext(Dispatchers.IO) {
                Files.newOutputStream(
                    partial,
                    StandardOpenOption.CREATE_NEW,
                    StandardOpenOption.WRITE,
                ).use { output ->
                    while (true) {
                        val packet = body.readRemaining(CHUNK_BYTES)
                        if (packet.isEmpty) break
                        val bytes = packet.readBytes()
                        written += bytes.size
                        require(written <= declaredLength) { "Attachment exceeds its declared size" }
                        output.write(bytes)
                    }
                }
                require(written == declaredLength) { "Attachment is shorter than declared" }
                Files.move(
                    partial,
                    directory.resolve("$id.blob"),
                    StandardCopyOption.ATOMIC_MOVE,
                )
            }
            return id
        } catch (error: Throwable) {
            runCatching { Files.deleteIfExists(partial) }
            throw error
        }
    }

    /** Sureli ve var olan ekin yolu; yoksa ya da suresi dolduysa null. */
    fun file(id: String): Path? {
        if (!isValidId(id)) return null
        val path = directory.resolve("$id.blob")
        if (!Files.isRegularFile(path)) return null
        if (expired(path)) {
            runCatching { Files.deleteIfExists(path) }
            return null
        }
        return path
    }

    /** Suresi dolan ekleri ve yarim kalan yuklemeleri siler. */
    fun purgeExpired(): Int {
        var removed = 0
        Files.newDirectoryStream(directory).use { entries ->
            for (path in entries) {
                val name = path.fileName.toString()
                val stale = when {
                    name.endsWith(".blob") -> expired(path)
                    name.endsWith(".part") ->
                        now() - Files.getLastModifiedTime(path).toMillis() > PARTIAL_TTL_MILLIS
                    else -> false
                }
                if (stale && runCatching { Files.deleteIfExists(path) }.getOrDefault(false)) removed++
            }
        }
        if (removed > 0) attachmentLog.info("[Attachment] Expired attachments removed: {}", removed)
        return removed
    }

    fun expiresAt(path: Path): Long = Files.getLastModifiedTime(path).toMillis() + ttlMillis

    private fun expired(path: Path): Boolean = now() >= expiresAt(path)

    private fun newId(): String {
        val bytes = ByteArray(32).also(random::nextBytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    companion object {
        /** 100 MB dosya + parcali AEAD ek yuku icin pay. */
        const val MAX_BYTES = 110L * 1024 * 1024
        private const val CHUNK_BYTES = 64L * 1024
        private const val PARTIAL_TTL_MILLIS = 60 * 60 * 1000L
        private val ID_PATTERN = Regex("^[A-Za-z0-9_-]{43}$")

        /** Ortamdan: `ATTACHMENT_DIR`, `ATTACHMENT_TTL_HOURS` (1..720, varsayilan 168). */
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): AttachmentStore {
            val hours = environment["ATTACHMENT_TTL_HOURS"]?.let { raw ->
                val value = raw.toLongOrNull() ?: error("ATTACHMENT_TTL_HOURS must be an integer")
                require(value in 1L..720L) { "ATTACHMENT_TTL_HOURS must be in 1..720" }
                value
            } ?: 168L
            val dir = environment["ATTACHMENT_DIR"]?.takeIf { it.isNotBlank() } ?: "data/attachments"
            return AttachmentStore(Paths.get(dir).toAbsolutePath(), hours * 60 * 60 * 1000L)
        }
    }
}
