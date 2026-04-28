package com.securechat.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Android ConnectivityManager entegrasyonu ile ag durumu izleyici.
 *
 * WebSocket ping/pong timeout'una (30 saniye) guvenme yerine, sistem seviyesinde
 * ag degisikliklerini aninda algilar. Bu sayede:
 * - Ucak modu (Bug 016): Ag kapanir kapanmaz disconnect, acilir acilmaz reconnect
 * - WiFi/Mobile gecisi (Bug 024): Ag degisikliginde aninda reconnect
 *
 * DIKKAT: start() cagrilmadan callback'ler calismaz. Activity/Service yasam dongusuyle
 * eslestirilmeli (onStart -> start, onStop -> stop).
 */
@Singleton
class NetworkMonitor @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private val _isConnected = MutableStateFlow(checkCurrentConnectivity())
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    /** Ag yeniden kullanilabilir oldugunda cagirilir (ornegin ucak modu kapatildi) */
    var onNetworkAvailable: (() -> Unit)? = null

    /** Tum ag baglantilari kaybedildiginde cagirilir (ornegin ucak modu acildi) */
    var onNetworkLost: (() -> Unit)? = null

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val wasDisconnected = !_isConnected.value
            _isConnected.value = true
            if (wasDisconnected) {
                Log.d(TAG, "Network available — triggering reconnect")
                onNetworkAvailable?.invoke()
            }
        }

        override fun onLost(network: Network) {
            // Baska aktif ag olup olmadigini kontrol et (ornegin WiFi kapandi ama mobile var)
            if (!checkCurrentConnectivity()) {
                Log.d(TAG, "Network lost — no remaining connectivity")
                _isConnected.value = false
                onNetworkLost?.invoke()
            }
        }

        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            val connected = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            val wasDisconnected = !_isConnected.value
            _isConnected.value = connected
            if (connected && wasDisconnected) {
                Log.d(TAG, "Network capabilities restored — triggering reconnect")
                onNetworkAvailable?.invoke()
            }
        }
    }

    /**
     * ConnectivityManager callback'ini kayit eder ve ag degisikliklerini dinlemeye baslar.
     * Uygulama on plana gectiginde cagrilmalidir (AppLifecycleObserver.onStart).
     */
    fun start() {
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        try {
            connectivityManager.registerNetworkCallback(request, networkCallback)
            Log.d(TAG, "Network callback registered")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register network callback", e)
        }
    }

    /**
     * ConnectivityManager callback'ini kaldirir ve dinlemeyi durdurur.
     * Uygulama arka plana gectiginde cagrilmalidir (AppLifecycleObserver.onStop).
     */
    fun stop() {
        try {
            connectivityManager.unregisterNetworkCallback(networkCallback)
            Log.d(TAG, "Network callback unregistered")
        } catch (_: Exception) {
            // Zaten unregister edilmis olabilir — guvenlice yoksay
        }
    }

    /**
     * Mevcut ag baglantiligini kontrol eder.
     * Hem INTERNET capability hem de VALIDATED (gercekten internet erisimi var) kontrol eder.
     */
    fun checkCurrentConnectivity(): Boolean {
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    companion object {
        private const val TAG = "NetworkMonitor"
    }
}
