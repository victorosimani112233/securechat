package com.securechat.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkConstructor
import io.mockk.slot
import io.mockk.unmockkConstructor
import io.mockk.verify
import org.junit.After
import org.junit.Before
import org.junit.Test

/**
 * NetworkMonitor sinifinin unit testleri.
 * Ag durumu degisikliklerini algilama, callback tetikleme ve
 * ConnectivityManager entegrasyonunu test eder (Bug 016, Bug 024).
 *
 * NOT: Android framework siniflarinin (NetworkRequest.Builder vb.) JVM unit test
 * ortaminda sinirli olmasindan dolayi, Builder mock'lanir ve
 * NetworkCallback dogrudan slot ile yakalanir.
 */
class NetworkMonitorTest {

    private lateinit var mockContext: Context
    private lateinit var mockConnectivityManager: ConnectivityManager
    private lateinit var mockNetwork: Network
    private lateinit var mockCapabilities: NetworkCapabilities
    private lateinit var mockNetworkRequest: NetworkRequest
    private lateinit var networkMonitor: NetworkMonitor
    private var capturedCallback: ConnectivityManager.NetworkCallback? = null

    @Before
    fun setUp() {
        mockContext = mockk(relaxed = true)
        mockConnectivityManager = mockk(relaxed = true)
        mockNetwork = mockk(relaxed = true)
        mockCapabilities = mockk(relaxed = true)
        mockNetworkRequest = mockk(relaxed = true)

        every {
            mockContext.getSystemService(Context.CONNECTIVITY_SERVICE)
        } returns mockConnectivityManager

        // Baslangicta ag baglantisi yok
        every { mockConnectivityManager.activeNetwork } returns null

        // NetworkRequest.Builder Android stub'i mock'la — addCapability/build zinciri duzgun calismali
        mockkConstructor(NetworkRequest.Builder::class)
        every { anyConstructed<NetworkRequest.Builder>().addCapability(any()) } returns NetworkRequest.Builder()
        every { anyConstructed<NetworkRequest.Builder>().build() } returns mockNetworkRequest

        // NetworkCallback'i yakala — registerNetworkCallback cagrildiginda
        val callbackSlot = slot<ConnectivityManager.NetworkCallback>()
        every {
            mockConnectivityManager.registerNetworkCallback(any<NetworkRequest>(), capture(callbackSlot))
        } answers {
            capturedCallback = callbackSlot.captured
        }

        networkMonitor = NetworkMonitor(mockContext)
    }

    @After
    fun tearDown() {
        unmockkConstructor(NetworkRequest.Builder::class)
    }

    @Test
    fun `initial state reflects current connectivity - no network`() {
        // ConnectivityManager.activeNetwork null dondugunde baslangic durumu false
        assertThat(networkMonitor.isConnected.value).isFalse()
    }

    @Test
    fun `initial state reflects current connectivity - network available`() {
        every { mockConnectivityManager.activeNetwork } returns mockNetwork
        every { mockConnectivityManager.getNetworkCapabilities(mockNetwork) } returns mockCapabilities
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns true

        // Yeni bir NetworkMonitor olustur — checkCurrentConnectivity true donecek
        val connectedMonitor = NetworkMonitor(mockContext)
        assertThat(connectedMonitor.isConnected.value).isTrue()
    }

    @Test
    fun `start registers network callback`() {
        networkMonitor.start()

        verify {
            mockConnectivityManager.registerNetworkCallback(
                any<NetworkRequest>(),
                any<ConnectivityManager.NetworkCallback>()
            )
        }
    }

    @Test
    fun `stop unregisters network callback`() {
        networkMonitor.start()
        networkMonitor.stop()

        verify {
            mockConnectivityManager.unregisterNetworkCallback(any<ConnectivityManager.NetworkCallback>())
        }
    }

    @Test
    fun `onAvailable sets isConnected to true`() {
        networkMonitor.start()
        val callback = capturedCallback!!

        callback.onAvailable(mockNetwork)

        assertThat(networkMonitor.isConnected.value).isTrue()
    }

    @Test
    fun `onAvailable triggers onNetworkAvailable when previously disconnected`() {
        var callbackTriggered = false
        networkMonitor.onNetworkAvailable = { callbackTriggered = true }

        networkMonitor.start()
        val callback = capturedCallback!!

        // Baslangicta bagli degil (isConnected = false)
        assertThat(networkMonitor.isConnected.value).isFalse()

        callback.onAvailable(mockNetwork)

        assertThat(callbackTriggered).isTrue()
    }

    @Test
    fun `onAvailable does not trigger callback when already connected`() {
        var callbackCount = 0
        networkMonitor.onNetworkAvailable = { callbackCount++ }

        networkMonitor.start()
        val callback = capturedCallback!!

        // Ilk onAvailable — callback tetiklenir
        callback.onAvailable(mockNetwork)
        assertThat(callbackCount).isEqualTo(1)

        // Ikinci onAvailable — zaten bagliyiz, callback tekrar tetiklenmemeli
        callback.onAvailable(mockNetwork)
        assertThat(callbackCount).isEqualTo(1)
    }

    @Test
    fun `onLost sets isConnected to false when no other network`() {
        networkMonitor.start()
        val callback = capturedCallback!!

        // Once baglanti kur
        callback.onAvailable(mockNetwork)
        assertThat(networkMonitor.isConnected.value).isTrue()

        // Sonra ag kaybet — baska aktif ag yok
        every { mockConnectivityManager.activeNetwork } returns null
        callback.onLost(mockNetwork)

        assertThat(networkMonitor.isConnected.value).isFalse()
    }

    @Test
    fun `onLost triggers onNetworkLost callback`() {
        var lostCallbackTriggered = false
        networkMonitor.onNetworkLost = { lostCallbackTriggered = true }

        networkMonitor.start()
        val callback = capturedCallback!!

        callback.onAvailable(mockNetwork)
        assertThat(networkMonitor.isConnected.value).isTrue()

        every { mockConnectivityManager.activeNetwork } returns null
        callback.onLost(mockNetwork)

        assertThat(lostCallbackTriggered).isTrue()
    }

    @Test
    fun `onLost does not disconnect if another network exists`() {
        var lostCallbackTriggered = false
        networkMonitor.onNetworkLost = { lostCallbackTriggered = true }

        networkMonitor.start()
        val callback = capturedCallback!!

        callback.onAvailable(mockNetwork)

        // Ag kaybedildi ama baska aktif ag var (WiFi -> Mobile gecisi)
        val anotherNetwork: Network = mockk(relaxed = true)
        every { mockConnectivityManager.activeNetwork } returns anotherNetwork
        every { mockConnectivityManager.getNetworkCapabilities(anotherNetwork) } returns mockCapabilities
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns true

        callback.onLost(mockNetwork)

        // Hala bagli olmali — baska ag var
        assertThat(networkMonitor.isConnected.value).isTrue()
        assertThat(lostCallbackTriggered).isFalse()
    }

    @Test
    fun `onCapabilitiesChanged updates connectivity state`() {
        networkMonitor.start()
        val callback = capturedCallback!!

        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns true

        callback.onCapabilitiesChanged(mockNetwork, mockCapabilities)

        assertThat(networkMonitor.isConnected.value).isTrue()
    }

    @Test
    fun `onCapabilitiesChanged triggers callback when transitioning from disconnected`() {
        var callbackTriggered = false
        networkMonitor.onNetworkAvailable = { callbackTriggered = true }

        networkMonitor.start()
        val callback = capturedCallback!!

        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns true

        callback.onCapabilitiesChanged(mockNetwork, mockCapabilities)

        assertThat(callbackTriggered).isTrue()
    }

    @Test
    fun `checkCurrentConnectivity returns false when no active network`() {
        every { mockConnectivityManager.activeNetwork } returns null

        assertThat(networkMonitor.checkCurrentConnectivity()).isFalse()
    }

    @Test
    fun `checkCurrentConnectivity returns false when no capabilities`() {
        every { mockConnectivityManager.activeNetwork } returns mockNetwork
        every { mockConnectivityManager.getNetworkCapabilities(mockNetwork) } returns null

        assertThat(networkMonitor.checkCurrentConnectivity()).isFalse()
    }

    @Test
    fun `checkCurrentConnectivity returns false without VALIDATED capability`() {
        every { mockConnectivityManager.activeNetwork } returns mockNetwork
        every { mockConnectivityManager.getNetworkCapabilities(mockNetwork) } returns mockCapabilities
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns false

        assertThat(networkMonitor.checkCurrentConnectivity()).isFalse()
    }

    @Test
    fun `checkCurrentConnectivity returns true with INTERNET and VALIDATED`() {
        every { mockConnectivityManager.activeNetwork } returns mockNetwork
        every { mockConnectivityManager.getNetworkCapabilities(mockNetwork) } returns mockCapabilities
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } returns true
        every { mockCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) } returns true

        assertThat(networkMonitor.checkCurrentConnectivity()).isTrue()
    }

    @Test
    fun `stop does not throw if start was never called`() {
        // start() cagirmadan stop() cagirildiginda hata firlatilmamali
        networkMonitor.stop()
    }

    @Test
    fun `callback slot is captured after start`() {
        networkMonitor.start()

        // start() cagirildiktan sonra callback yakalanmis olmali
        assertThat(capturedCallback).isNotNull()
    }
}
