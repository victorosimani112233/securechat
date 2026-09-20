package com.securechat.app

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import androidx.annotation.RawRes

internal class SecureChatCallTonePlayer(
    private val context: Context
) {
    private var player: MediaPlayer? = null

    @Synchronized
    fun startRingback(): Boolean = play(R.raw.elcim_ringback, looping = true)

    @Synchronized
    fun playCue(cue: String): Boolean = when (cue) {
        "connected" -> play(R.raw.elcim_call_connected, looping = false)
        "ended" -> play(R.raw.elcim_call_ended, looping = false)
        else -> false
    }

    @Synchronized
    fun stop() {
        stopLocked()
    }

    @Synchronized
    fun release() {
        stopLocked()
    }

    private fun play(@RawRes resourceId: Int, looping: Boolean): Boolean {
        stopLocked()
        val next = MediaPlayer()
        return try {
            next.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            context.resources.openRawResourceFd(resourceId).use { descriptor ->
                next.setDataSource(
                    descriptor.fileDescriptor,
                    descriptor.startOffset,
                    descriptor.length
                )
            }
            next.isLooping = looping
            next.setOnCompletionListener { completed ->
                synchronized(this) {
                    if (player === completed) player = null
                }
                completed.release()
            }
            next.prepare()
            next.start()
            player = next
            true
        } catch (_: Exception) {
            next.release()
            false
        }
    }

    private fun stopLocked() {
        val active = player ?: return
        player = null
        try {
            active.stop()
        } catch (_: IllegalStateException) {
            // Already completed or not yet started.
        }
        active.release()
    }
}
