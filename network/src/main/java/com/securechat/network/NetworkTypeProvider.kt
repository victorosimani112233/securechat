package com.securechat.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Aktif aglar — adaptif video kalitesi ve auto-download policy icin kullanilir.
 */
enum class NetworkType { WIFI, CELLULAR, OTHER }

/**
 * Mevcut ag tipi bilgisi saglar (WIFI / CELLULAR / OTHER).
 *
 * Kullanim alanlari:
 *   - PeerConnectionManager: adaptif video bitrate/resolution
 *   - AutoDownloadDecider (F5): otomatik medya indirme karari
 *
 * Not: ACCESS_NETWORK_STATE izni manifest'te zaten ekli.
 *
 * Tasinma notu: Sprint 9'da app/data altinda yazildi, sonra network modulune
 * tasindi cunku PeerConnectionManager (network) da kullaniyor — modul bagimliligi
 * yonunde temizlik.
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
