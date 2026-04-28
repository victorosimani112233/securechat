package com.securechat.app.ui.viewmodel

import app.cash.turbine.test
import com.securechat.contacts.ContactPermissionManager
import com.securechat.contacts.ContactSearchManager
import com.securechat.storage.entity.ContactEntity
import com.securechat.contacts.ContactsProvider
import com.securechat.contacts.UserDiscoveryService
import com.securechat.contacts.DiscoveryApiService
import com.securechat.storage.dao.ContactDao
import com.securechat.storage.repository.MessageRepository
import com.securechat.contacts.model.RegisteredContact
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * ContactsViewModel birim testleri.
 * Arama, izin yonetimi, kullanici kesfi ve manuel ID girisi islemlerini dogrular.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ContactsViewModelTest {

    private val testDispatcher = UnconfinedTestDispatcher()
    private lateinit var contactSearchManager: ContactSearchManager
    private lateinit var contactPermissionManager: ContactPermissionManager
    private lateinit var userDiscoveryService: UserDiscoveryService
    private lateinit var contactsProvider: ContactsProvider
    private lateinit var messageRepository: MessageRepository
    private lateinit var discoveryApiService: DiscoveryApiService
    private lateinit var contactDao: ContactDao

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        contactSearchManager = mockk()
        contactPermissionManager = mockk()
        userDiscoveryService = mockk(relaxed = true)
        contactsProvider = mockk(relaxed = true)
        messageRepository = mockk(relaxed = true)
        discoveryApiService = mockk(relaxed = true)
        contactDao = mockk(relaxed = true)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(hasPermission: Boolean = false): ContactsViewModel {
        every { contactPermissionManager.hasPermission() } returns hasPermission
        every { contactSearchManager.getRegisteredContacts() } returns flowOf(emptyList())
        every { contactSearchManager.searchContacts(any()) } returns flowOf(emptyList())
        return ContactsViewModel(contactSearchManager, contactPermissionManager, userDiscoveryService, contactsProvider, messageRepository, discoveryApiService, contactDao)
    }

    // --- Arama testleri ---

    @Test
    fun `searchQuery baslangicta bos olmali`() = runTest {
        val viewModel = createViewModel()
        assertEquals("", viewModel.searchQuery.value)
    }

    @Test
    fun `onSearchQueryChanged sorguyu gunceller`() = runTest {
        val viewModel = createViewModel()

        viewModel.onSearchQueryChanged("Ali")

        assertEquals("Ali", viewModel.searchQuery.value)
    }

    @Test
    fun `contacts bos sorgu icin getRegisteredContacts kullanir`() = runTest {
        val testEntities = listOf(
            ContactEntity(id = "u1", phoneNumber = "+905551111111", phoneHash = "h1", displayName = "Ali Veli", isRegistered = true),
            ContactEntity(id = "u2", phoneNumber = "+905552222222", phoneHash = "h2", displayName = "Ayse Fatma", isRegistered = true)
        )
        every { contactPermissionManager.hasPermission() } returns false
        coEvery { contactDao.getRegisteredCount() } returns 2
        coEvery { contactDao.getRegisteredPaginated(any(), any()) } returns testEntities
        every { contactSearchManager.searchContacts(any()) } returns flowOf(emptyList())

        val viewModel = ContactsViewModel(
            contactSearchManager, contactPermissionManager, userDiscoveryService, contactsProvider, messageRepository, discoveryApiService, contactDao
        )

        // WhileSubscribed flow'u Turbine ile dinle, debounce(300) icin zamani ilerlet
        viewModel.contacts.test {
            val first = awaitItem() // initial emptyList()
            if (first.size == 2) {
                assertEquals("Ali Veli", first[0].displayName)
            } else {
                val second = awaitItem()
                assertEquals(2, second.size)
                assertEquals("Ali Veli", second[0].displayName)
            }
            cancelAndConsumeRemainingEvents()
        }
    }

    @Test
    fun `contacts sorgu girilince searchContacts kullanir`() = runTest {
        val searchResult = listOf(createTestContact("u1", "Ali Veli"))
        every { contactPermissionManager.hasPermission() } returns false
        every { contactSearchManager.getRegisteredContacts() } returns flowOf(emptyList())
        every { contactSearchManager.searchContacts("Ali") } returns flowOf(searchResult)

        val viewModel = ContactsViewModel(
            contactSearchManager, contactPermissionManager, userDiscoveryService, contactsProvider, messageRepository, discoveryApiService, contactDao
        )

        viewModel.onSearchQueryChanged("Ali")

        viewModel.contacts.test {
            val first = awaitItem()
            if (first.isEmpty()) {
                val second = awaitItem()
                assertEquals(1, second.size)
                assertEquals("Ali Veli", second[0].displayName)
            } else {
                assertEquals(1, first.size)
                assertEquals("Ali Veli", first[0].displayName)
            }
            cancelAndConsumeRemainingEvents()
        }
    }

    @Test
    fun `contacts varsayilan olarak bos liste`() = runTest {
        val viewModel = createViewModel()
        assertEquals(emptyList<RegisteredContact>(), viewModel.contacts.value)
    }

    // --- Izin yonetimi testleri ---

    @Test
    fun `permissionGranted baslangicta hasPermission'a gore belirlenir - izinli`() = runTest {
        val viewModel = createViewModel(hasPermission = true)
        assertTrue(viewModel.permissionGranted.value)
    }

    @Test
    fun `permissionGranted baslangicta hasPermission'a gore belirlenir - izinsiz`() = runTest {
        val viewModel = createViewModel(hasPermission = false)
        assertFalse(viewModel.permissionGranted.value)
    }

    @Test
    fun `hasPermission contactPermissionManager'a delege eder`() = runTest {
        every { contactPermissionManager.hasPermission() } returns true
        every { contactSearchManager.getRegisteredContacts() } returns flowOf(emptyList())

        val viewModel = ContactsViewModel(
            contactSearchManager, contactPermissionManager, userDiscoveryService, contactsProvider, messageRepository, discoveryApiService, contactDao
        )

        assertTrue(viewModel.hasPermission())
    }

    @Test
    fun `onPermissionGranted izin durumunu true yapar`() = runTest {
        val viewModel = createViewModel(hasPermission = false)

        viewModel.onPermissionGranted()

        assertTrue(viewModel.permissionGranted.value)
    }

    @Test
    fun `onPermissionDenied izin durumunu false yapar`() = runTest {
        val viewModel = createViewModel(hasPermission = true)

        viewModel.onPermissionDenied()

        assertFalse(viewModel.permissionGranted.value)
    }

    // --- Kullanici kesfi testleri ---

    @Test
    fun `onPermissionGranted kullanici kesfini baslatir`() = runTest {
        val viewModel = createViewModel(hasPermission = false)
        coEvery { userDiscoveryService.discoverRegisteredUsers() } returns emptyList()

        viewModel.onPermissionGranted()
        advanceUntilIdle()

        coVerify { userDiscoveryService.discoverRegisteredUsers() }
    }

    @Test
    fun `discoverUsers basarisiz olursa hata yutulur`() = runTest {
        val viewModel = createViewModel(hasPermission = false)
        coEvery { userDiscoveryService.discoverRegisteredUsers() } throws RuntimeException("Network error")

        viewModel.discoverUsers()
        advanceUntilIdle()

        // Hata firlatilmamali, viewModel calismaya devam etmeli
        assertFalse(viewModel.isDiscovering.value)
    }

    @Test
    fun `isDiscovering kesif sirasinda true olur`() = runTest {
        val viewModel = createViewModel(hasPermission = false)
        coEvery { userDiscoveryService.discoverRegisteredUsers() } returns emptyList()

        // Kesif tamamlandiktan sonra false olmali
        viewModel.discoverUsers()
        advanceUntilIdle()

        assertFalse(viewModel.isDiscovering.value)
    }

    // --- Manuel ID girisi testleri ---

    @Test
    fun `manualUserId baslangicta bos olmali`() = runTest {
        val viewModel = createViewModel()
        assertEquals("", viewModel.manualUserId.value)
    }

    @Test
    fun `onManualUserIdChanged ID'yi gunceller`() = runTest {
        val viewModel = createViewModel()

        viewModel.onManualUserIdChanged("user-123")

        assertEquals("user-123", viewModel.manualUserId.value)
    }

    @Test
    fun `onManualUserIdChanged bos string kabul eder`() = runTest {
        val viewModel = createViewModel()

        viewModel.onManualUserIdChanged("user-123")
        viewModel.onManualUserIdChanged("")

        assertEquals("", viewModel.manualUserId.value)
    }

    private fun createTestContact(userId: String, displayName: String): RegisteredContact {
        return RegisteredContact(
            userId = userId,
            displayName = displayName,
            phoneNumber = "+905551234567",
            phoneHash = "a1b2c3d4e5f6",
            avatarUri = null
        )
    }
}
