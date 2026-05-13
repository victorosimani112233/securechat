package com.securechat.network

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.webrtc.PeerConnection
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

/**
 * Sunucudan dinamik TURN credential'lari ceker.
 * Hardcoded credential yerine her arama oncesi taze credential alinir.
 */
@Singleton
class IceServerFetcher @Inject constructor(
    private val okHttpClient: OkHttpClient,
    @Named("stunUrl") private val stunUrl: String
) {
    @Volatile
    var apiBaseUrl: String = ""

    /** Auth token'i set eden callback — UserSession'dan bagimsiz kalmak icin */
    @Volatile
    var accessTokenProvider: () -> String? = { null }

    companion object {
        private const val TAG = "IceServerFetcher"
    }

    /**
     * Sunucudan ICE server listesini ceker.
     * Basarisiz olursa sadece STUN doner (TURN olmadan).
     * Sunucu artik userId'yi token claim'inden okur — query param gereksiz ama backward-compat icin tutuluyor.
     */
    fun fetch(@Suppress("UNUSED_PARAMETER") userId: String): List<PeerConnection.IceServer> {
        return try {
            val url = "$apiBaseUrl/api/v1/ice/config"
            val token = accessTokenProvider()
            if (token.isNullOrBlank()) {
                Log.w(TAG, "Access token yok — fallback STUN")
                return fallbackServers()
            }
            val request = Request.Builder()
                .url(url)
                .addHeader("Authorization", "Bearer $token")
                .get()
                .build()
            val response = okHttpClient.newCall(request).execute()

            if (!response.isSuccessful) {
                Log.w(TAG, "ICE config alinamadi: ${response.code}")
                return fallbackServers()
            }

            val body = response.body?.string() ?: return fallbackServers()
            val json = JSONObject(body)
            val iceServersArray = json.getJSONArray("iceServers")

            val servers = mutableListOf<PeerConnection.IceServer>()
            for (i in 0 until iceServersArray.length()) {
                val server = iceServersArray.getJSONObject(i)
                val urls = server.getString("urls")
                val username = if (server.has("username")) server.getString("username") else null
                val credential = if (server.has("credential")) server.getString("credential") else null

                val builder = PeerConnection.IceServer.builder(urls)
                if (!username.isNullOrBlank()) builder.setUsername(username)
                if (!credential.isNullOrBlank()) builder.setPassword(credential)
                servers.add(builder.createIceServer())
            }

            Log.d(TAG, "ICE config alindi: ${servers.size} sunucu")
            servers
        } catch (e: Exception) {
            Log.e(TAG, "ICE config hatasi: ${e.message}")
            fallbackServers()
        }
    }

    private fun fallbackServers(): List<PeerConnection.IceServer> {
        return listOf(
            PeerConnection.IceServer.builder(stunUrl)
                .createIceServer()
        )
    }
}
