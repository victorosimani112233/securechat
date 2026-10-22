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
        val id = store.write(ByteReadChannel(bytes), bytes.size.toLong())

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
        val id = store.write(ByteReadChannel(ByteArray(10)), 10)
        val path = store.file(id)!!
        Files.setLastModifiedTime(path, FileTime.fromMillis(clock))
        clock += 59_000
        assertNotNull(store.file(id))
        clock += 2_000
        assertNull(store.file(id))
        assertFalse(Files.exists(path))

        val other = store.write(ByteReadChannel(ByteArray(10)), 10)
        Files.setLastModifiedTime(store.file(other)!!, FileTime.fromMillis(clock - 120_000))
        val partial = directory.resolve("${"a".repeat(43)}.part")
        Files.write(partial, ByteArray(3))
        Files.setLastModifiedTime(partial, FileTime.fromMillis(clock - 2 * 60 * 60 * 1000L))
        assertEquals(2, store.purgeExpired())
    }

    @Test
    fun `only well formed ids are looked up`() {
        assertNull(store.file("../../etc/passwd"))
        assertNull(store.file("short"))
        assertNull(store.file("a".repeat(43)))
        assertFalse(store.isValidId("a/" + "b".repeat(41)))
    }
}
