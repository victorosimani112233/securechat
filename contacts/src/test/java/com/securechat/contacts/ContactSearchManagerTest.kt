package com.securechat.contacts

import com.securechat.storage.dao.ContactDao
import com.securechat.storage.entity.ContactEntity
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * ContactSearchManager icin unit testleri.
 * Arama, filtreleme ve entity donusumu islemlerini dogrular.
 */
class ContactSearchManagerTest {

    private lateinit var contactDao: ContactDao
    private lateinit var searchManager: ContactSearchManager

    @Before
    fun setup() {
        contactDao = mockk()
        searchManager = ContactSearchManager(contactDao)
    }

    @Test
    fun `searchContacts yalnizca kayitli kisileri doner`() = runTest {
        val entities = listOf(
            createContactEntity("1", "Ali", "+905551111111", isRegistered = true),
            createContactEntity("2", "Veli", "+905552222222", isRegistered = false),
            createContactEntity("3", "Ayse", "+905553333333", isRegistered = true)
        )

        every { contactDao.search("Ali") } returns flowOf(entities)

        val result = searchManager.searchContacts("Ali").first()

        assertEquals(2, result.size)
        assertEquals("Ali", result[0].displayName)
        assertEquals("Ayse", result[1].displayName)
    }

    @Test
    fun `searchContacts bos sonuc icin bos liste doner`() = runTest {
        every { contactDao.search("xyz") } returns flowOf(emptyList())

        val result = searchManager.searchContacts("xyz").first()

        assertTrue(result.isEmpty())
    }

    @Test
    fun `getRegisteredContacts tum kayitli kisileri doner`() = runTest {
        val entities = listOf(
            createContactEntity("1", "Ali", "+905551111111", isRegistered = true),
            createContactEntity("2", "Veli", "+905552222222", isRegistered = true)
        )

        every { contactDao.getRegistered() } returns flowOf(entities)

        val result = searchManager.getRegisteredContacts().first()

        assertEquals(2, result.size)
        assertEquals("Ali", result[0].displayName)
        assertEquals("Veli", result[1].displayName)
    }

    @Test
    fun `getRegisteredContacts bos veritabani icin bos liste doner`() = runTest {
        every { contactDao.getRegistered() } returns flowOf(emptyList())

        val result = searchManager.getRegisteredContacts().first()

        assertTrue(result.isEmpty())
    }

    @Test
    fun `toRegisteredContact donusumu dogru calismali`() {
        val entity = createContactEntity(
            id = "user-123",
            displayName = "Test Kisi",
            phoneNumber = "+905551234567",
            isRegistered = true,
            avatarUri = "content://photo/1"
        )

        val result = entity.toRegisteredContact()

        assertEquals("user-123", result.userId)
        assertEquals("Test Kisi", result.displayName)
        assertEquals("+905551234567", result.phoneNumber)
        assertEquals("content://photo/1", result.avatarUri)
    }

    @Test
    fun `toRegisteredContact null avatarUri dogru islenmeli`() {
        val entity = createContactEntity(
            id = "user-456",
            displayName = "Fotosuz Kisi",
            phoneNumber = "+905559999999",
            isRegistered = true,
            avatarUri = null
        )

        val result = entity.toRegisteredContact()

        assertEquals(null, result.avatarUri)
    }

    private fun createContactEntity(
        id: String,
        displayName: String,
        phoneNumber: String,
        isRegistered: Boolean,
        avatarUri: String? = null
    ): ContactEntity {
        return ContactEntity(
            id = id,
            phoneNumber = phoneNumber,
            phoneHash = UserDiscoveryService.hashPhoneNumber(phoneNumber),
            displayName = displayName,
            isRegistered = isRegistered,
            avatarUri = avatarUri
        )
    }
}
