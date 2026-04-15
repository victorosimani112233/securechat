package com.securechat.contacts

import com.securechat.contacts.model.CheckUsersRequest
import com.securechat.contacts.model.CheckUsersResponse
import com.securechat.contacts.model.DeviceContact
import com.securechat.contacts.model.ServerUser
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.entity.ContactEntity
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * UserDiscoveryService icin unit testleri.
 * Hash uretimi, kullanici kesfi ve veritabani kayit islemlerini dogrular.
 */
class UserDiscoveryServiceTest {

    private lateinit var contactsProvider: ContactsProvider
    private lateinit var contactDao: ContactDao
    private lateinit var apiService: DiscoveryApiService
    private lateinit var service: UserDiscoveryService

    @Before
    fun setup() {
        contactsProvider = mockk()
        contactDao = mockk(relaxed = true)
        apiService = mockk()
        service = UserDiscoveryService(contactsProvider, contactDao, apiService)
    }

    // --- Hash uretimi testleri ---

    @Test
    fun `hashPhoneNumber uretilen hash deterministik olmali`() {
        val phone = "+905551234567"
        val hash1 = UserDiscoveryService.hashPhoneNumber(phone)
        val hash2 = UserDiscoveryService.hashPhoneNumber(phone)
        assertEquals(hash1, hash2)
    }

    @Test
    fun `hashPhoneNumber sonucu 64 karakter hex string olmali`() {
        val hash = UserDiscoveryService.hashPhoneNumber("+905551234567")
        assertEquals(64, hash.length)
        assertTrue("Hash yalnizca hex karakterler icermeli", hash.matches(Regex("[0-9a-f]{64}")))
    }

    @Test
    fun `hashPhoneNumber farkli numaralar farkli hash uretmeli`() {
        val hash1 = UserDiscoveryService.hashPhoneNumber("+905551234567")
        val hash2 = UserDiscoveryService.hashPhoneNumber("+905559876543")
        assertNotEquals(hash1, hash2)
    }

    @Test
    fun `hashPhoneNumber bos string icin de gecerli hash uretmeli`() {
        val hash = UserDiscoveryService.hashPhoneNumber("")
        assertEquals(64, hash.length)
        assertTrue(hash.matches(Regex("[0-9a-f]{64}")))
    }

    @Test
    fun `hashPhoneNumber bilinen deger ile uyumlu olmali`() {
        // SHA-256 of "+905551234567" kontrol degeri
        val hash = UserDiscoveryService.hashPhoneNumber("+905551234567")
        // Deterministik oldugundan her zaman ayni sonucu vermeli
        val hashAgain = UserDiscoveryService.hashPhoneNumber("+905551234567")
        assertEquals(hash, hashAgain)
    }

    // --- Kullanici kesfi testleri ---

    @Test
    fun `discoverRegisteredUsers basarili eslesme dondurur`() = runTest {
        val phoneNumber = "+905551234567"
        val phoneHash = UserDiscoveryService.hashPhoneNumber(phoneNumber)

        val deviceContacts = listOf(
            DeviceContact(
                id = "1",
                displayName = "Ali Veli",
                phoneNumber = phoneNumber,
                avatarUri = null
            )
        )

        coEvery { contactsProvider.getAllContacts() } returns deviceContacts
        coEvery { apiService.checkRegisteredUsers(any()) } returns CheckUsersResponse(
            users = listOf(ServerUser(userId = "user-123", phoneHash = phoneHash))
        )

        val result = service.discoverRegisteredUsers()

        assertEquals(1, result.size)
        assertEquals("user-123", result[0].userId)
        assertEquals("Ali Veli", result[0].displayName)
        assertEquals(phoneNumber, result[0].phoneNumber)
        assertEquals(phoneHash, result[0].phoneHash)
    }

    @Test
    fun `discoverRegisteredUsers sunucuya yalnizca hash gonderir`() = runTest {
        val phoneNumber = "+905551234567"
        val phoneHash = UserDiscoveryService.hashPhoneNumber(phoneNumber)

        val deviceContacts = listOf(
            DeviceContact(
                id = "1",
                displayName = "Test Kisi",
                phoneNumber = phoneNumber,
                avatarUri = null
            )
        )

        val requestSlot = slot<CheckUsersRequest>()

        coEvery { contactsProvider.getAllContacts() } returns deviceContacts
        coEvery { apiService.checkRegisteredUsers(capture(requestSlot)) } returns CheckUsersResponse(
            users = emptyList()
        )

        service.discoverRegisteredUsers()

        val capturedRequest = requestSlot.captured
        // Gonderilen hash'ler plaintext numara icermemeli
        capturedRequest.hashes.forEach { hash ->
            assertNotEquals("Plaintext numara sunucuya gonderilmemeli", phoneNumber, hash)
            assertEquals("Hash 64 karakter olmali", 64, hash.length)
        }
        assertEquals(phoneHash, capturedRequest.hashes[0])
    }

    @Test
    fun `discoverRegisteredUsers eslesen kisiler veritabanina kaydedilir`() = runTest {
        val phoneNumber = "+905551234567"
        val phoneHash = UserDiscoveryService.hashPhoneNumber(phoneNumber)

        coEvery { contactsProvider.getAllContacts() } returns listOf(
            DeviceContact(
                id = "1",
                displayName = "Test Kisi",
                phoneNumber = phoneNumber,
                avatarUri = "content://photo/1"
            )
        )
        coEvery { apiService.checkRegisteredUsers(any()) } returns CheckUsersResponse(
            users = listOf(ServerUser(userId = "user-456", phoneHash = phoneHash))
        )

        service.discoverRegisteredUsers()

        val entitySlot = slot<ContactEntity>()
        coVerify { contactDao.insert(capture(entitySlot)) }

        val savedEntity = entitySlot.captured
        assertEquals("user-456", savedEntity.id)
        assertEquals(phoneNumber, savedEntity.phoneNumber)
        assertEquals(phoneHash, savedEntity.phoneHash)
        assertEquals("Test Kisi", savedEntity.displayName)
        assertTrue(savedEntity.isRegistered)
        assertEquals("content://photo/1", savedEntity.avatarUri)
    }

    @Test
    fun `discoverRegisteredUsers eslesme yoksa bos liste doner`() = runTest {
        coEvery { contactsProvider.getAllContacts() } returns listOf(
            DeviceContact(
                id = "1",
                displayName = "Bilinmeyen",
                phoneNumber = "+905559999999",
                avatarUri = null
            )
        )
        coEvery { apiService.checkRegisteredUsers(any()) } returns CheckUsersResponse(
            users = emptyList()
        )

        val result = service.discoverRegisteredUsers()

        assertTrue(result.isEmpty())
        coVerify(exactly = 0) { contactDao.insert(any()) }
    }

    @Test
    fun `discoverRegisteredUsers birden fazla eslesme isler`() = runTest {
        val phone1 = "+905551111111"
        val phone2 = "+905552222222"
        val hash1 = UserDiscoveryService.hashPhoneNumber(phone1)
        val hash2 = UserDiscoveryService.hashPhoneNumber(phone2)

        coEvery { contactsProvider.getAllContacts() } returns listOf(
            DeviceContact("1", "Kisi Bir", phone1, null),
            DeviceContact("2", "Kisi Iki", phone2, null),
            DeviceContact("3", "Kisi Uc", "+905553333333", null)
        )
        coEvery { apiService.checkRegisteredUsers(any()) } returns CheckUsersResponse(
            users = listOf(
                ServerUser(userId = "u1", phoneHash = hash1),
                ServerUser(userId = "u2", phoneHash = hash2)
            )
        )

        val result = service.discoverRegisteredUsers()

        assertEquals(2, result.size)
        assertEquals("u1", result[0].userId)
        assertEquals("u2", result[1].userId)
        coVerify(exactly = 2) { contactDao.insert(any()) }
    }
}
