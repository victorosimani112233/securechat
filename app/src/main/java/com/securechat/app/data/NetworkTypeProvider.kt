package com.securechat.app.data

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mevcut ag tipi bilgisi saglar (WIFI / CELLULAR / OTHER).
 *
 * AutoDownloadDecider.shouldDownload icin gerekli girdi.
 *
 * Not: izin gerektirmez (ACCESS_NETWORK_STATE manifest'e zaten ekli).
 */
@Singleton
class NetworkTypeProvider @Inject constructor(
    @ApplicationContext private val context: Context
) {
    fun current(): NetworkType {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return NetworkType.OTHER
        val network = cm.activeNetwork ?: return NetworkType.OTHER
        val caps = cm.getNetworkCapabilities(network) ?: return NetworkType.OTHER
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkType.WIFI
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkType.CELLULAR
            else -> NetworkType.OTHER
        }
    }
}
