package com.securechat.signaling

import io.ktor.utils.io.ByteReadChannel
import java.nio.file.Files
import java.nio.file.attribute.FileTime
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Sifreli ek deposu: diske akitarak yazar, suresi dolani siler. */
class AttachmentStoreTest {
    private val directory = Files.createTempDirectory("attachments")
    private var clock = 1_000_000L
    private val store = AttachmentStore(directory, ttlMillis = 60_000L, maxBytes = 1024) { clock }

    @Test
    fun `an upload is stored under an unguessable id and read back`() = runBlocking {
        val bytes = ByteArray(700) { (it % 251).toByte() }
        val id = store.write(ByteReadChannel(bytes), bytes.size.toLong()).id

        assertTrue(store.isValidId(id))
        assertEquals(43, id.length)
        val path = store.file(id)
        assertNotNull(path)
        assertArrayEquals(bytes, Files.readAllBytes(path!!))
    }

    @Test
    fun `a body that does not match its declared size leaves nothing behind`() {
        val bytes = ByteArray(100)
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { store.write(ByteReadChannel(bytes), 200) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { store.write(ByteReadChannel(bytes), 50) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            runBlocking { store.write(ByteReadChannel(ByteArray(2000)), 2000) }
        }
        assertEquals(0, Files.list(directory).use { it.count() })
    }

    @Test
    fun `an expired attachment is gone and purged`() = runBlocking {
        val id = store.write(ByteReadChannel(ByteArray(10)), 10).id
        val path = store.file(id)!!
        Files.setLastModifiedTime(path, FileTime.fromMillis(clock))
        clock += 59_000
        assertNotNull(store.file(id))
        clock += 2_000
        assertNull(store.file(id))
        assertFalse(Files.exists(path))

        val other = store.write(ByteReadChannel(ByteArray(10)), 10).id
        Files.setLastModifiedTime(store.file(other)!!, FileTime.fromMillis(clock - 120_000))
        val partial = directory.resolve("${"a".repeat(43)}.part")
        Files.write(partial, ByteArray(3))
        Files.setLastModifiedTime(partial, FileTime.fromMillis(clock - 2 * 60 * 60 * 1000L))
        assertEquals(2, store.purgeExpired())
    }

    @Test
    fun `only the delete token removes an attachment early`() = runBlocking {
        val stored = store.write(ByteReadChannel(ByteArray(10)), 10)
        val other = store.write(ByteReadChannel(ByteArray(10)), 10)

        // Sunucu jetonun kendisini degil yalniz ozetini tutar.
        val owner = Files.readAllBytes(directory.resolve("${stored.id}.owner"))
        assertFalse(owner.contentEquals(stored.deleteToken.toByteArray()))

        assertFalse(store.delete(stored.id, other.deleteToken))
        assertFalse(store.delete(stored.id, "not a token"))
        assertNotNull(store.file(stored.id))

        assertTrue(store.delete(stored.id, stored.deleteToken))
        assertNull(store.file(stored.id))
        assertFalse(Files.exists(directory.resolve("${stored.id}.owner")))
        // Ikinci silme ayni yaniti alir; diger ek etkilenmez.
        assertFalse(store.delete(stored.id, stored.deleteToken))
        assertNotNull(store.file(other.id))
    }

    @Test
    fun `only well formed ids are looked up`() {
        assertNull(store.file("../../etc/passwd"))
        assertNull(store.file("short"))
        assertNull(store.file("a".repeat(43)))
        assertFalse(store.isValidId("a/" + "b".repeat(41)))
    }
}
