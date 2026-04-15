package com.securechat.contacts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkAll
import androidx.core.content.ContextCompat
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * ContactPermissionManager icin unit testleri.
 * READ_CONTACTS izin kontrolunu dogrular.
 */
class ContactPermissionManagerTest {

    private lateinit var context: Context
    private lateinit var permissionManager: ContactPermissionManager

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        permissionManager = ContactPermissionManager(context)
        mockkStatic(ContextCompat::class)
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    @Test
    fun `hasPermission izin verilmisse true doner`() {
        every {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
        } returns PackageManager.PERMISSION_GRANTED

        assertTrue(permissionManager.hasPermission())
    }

    @Test
    fun `hasPermission izin verilmemisse false doner`() {
        every {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
        } returns PackageManager.PERMISSION_DENIED

        assertFalse(permissionManager.hasPermission())
    }

    @Test
    fun `hasPermission READ_CONTACTS iznini kontrol eder`() {
        every {
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
        } returns PackageManager.PERMISSION_GRANTED

        // Farkli bir izin kontrolu yapmamali
        every {
            ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_CONTACTS)
        } returns PackageManager.PERMISSION_DENIED

        assertTrue(permissionManager.hasPermission())
    }
}
