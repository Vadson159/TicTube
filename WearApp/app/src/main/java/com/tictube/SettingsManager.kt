package com.tictube

import android.content.Context

class SettingsManager private constructor(context: Context) {

    enum class StreamQuality(val label: String) {
        AUDIO_ONLY("Audio Only \uD83C\uDFA7"),
        Q360P("360p"),
        Q480P("480p"),
        Q720P("720p"),
        Q1080P("1080p")
    }

    companion object {
        private const val PREFS = "tictube_settings"
        private const val KEY_Q = "stream_quality"
        private const val KEY_CLIENT_ID = "oauth_client_id"
        private const val KEY_CLIENT_SECRET = "oauth_client_secret"
        private const val KEY_REFRESH_TOKEN = "oauth_refresh_token"

        @Volatile private var instance: SettingsManager? = null
        fun getInstance(ctx: Context): SettingsManager =
            instance ?: synchronized(this) {
                instance ?: SettingsManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var accountName: String
        get() = prefs.getString("account_name", "") ?: ""
        set(value) { prefs.edit().putString("account_name", value).apply() }
        
    fun clearAuth() {
        prefs.edit().remove("account_name").apply()
    }

    fun getQuality(): StreamQuality = try {
        StreamQuality.valueOf(prefs.getString(KEY_Q, StreamQuality.Q360P.name)!!)
    } catch (_: Exception) { StreamQuality.Q360P }

    fun setQuality(q: StreamQuality) { prefs.edit().putString(KEY_Q, q.name).apply() }

    fun cycleQuality(): StreamQuality {
        val next = when (getQuality()) {
            StreamQuality.Q360P -> StreamQuality.Q480P
            StreamQuality.Q480P -> StreamQuality.Q720P
            StreamQuality.Q720P -> StreamQuality.Q1080P
            StreamQuality.Q1080P -> StreamQuality.AUDIO_ONLY
            StreamQuality.AUDIO_ONLY -> StreamQuality.Q360P
        }
        setQuality(next)
        return next
    }
}