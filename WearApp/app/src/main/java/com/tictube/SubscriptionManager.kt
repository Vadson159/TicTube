package com.tictube

import android.content.Context
import android.content.SharedPreferences

/**
 * Lightweight channel subscription store backed by [SharedPreferences].
 *
 * Each subscription is persisted as a single string in the format
 * `"channelUrl||channelName"` inside a `StringSet`.
 *
 * Thread-safety: [SharedPreferences] reads are thread-safe; writes use
 * [SharedPreferences.Editor.apply] (async, non-blocking).
 */
class SubscriptionManager private constructor(context: Context) {

    companion object {
        private const val PREFS_NAME = "tictube_subscriptions"
        private const val KEY_CHANNELS = "subscribed_channels"
        private const val SEPARATOR = "||"

        @Volatile
        private var instance: SubscriptionManager? = null

        fun getInstance(context: Context): SubscriptionManager {
            return instance ?: synchronized(this) {
                instance ?: SubscriptionManager(context.applicationContext)
                    .also { instance = it }
            }
        }
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Subscribe to a channel. Duplicates (by URL) are silently ignored. */
    fun subscribe(url: String, name: String) {
        if (url.isBlank()) return
        val current = rawSet().toMutableSet()
        // Remove any existing entry for this URL first (name might have changed)
        current.removeAll { it.startsWith("$url$SEPARATOR") }
        current.add("$url$SEPARATOR$name")
        prefs.edit().putStringSet(KEY_CHANNELS, current).apply()
    }

    /** Unsubscribe from a channel by its URL. */
    fun unsubscribe(url: String) {
        val current = rawSet().toMutableSet()
        current.removeAll { it.startsWith("$url$SEPARATOR") }
        prefs.edit().putStringSet(KEY_CHANNELS, current).apply()
    }

    /** Check whether a channel URL is currently subscribed. */
    fun isSubscribed(url: String): Boolean {
        return rawSet().any { it.startsWith("$url$SEPARATOR") }
    }

    /** Return all subscriptions sorted alphabetically by name. */
    fun getAll(): List<Subscription> {
        return rawSet().mapNotNull { entry ->
            val parts = entry.split(SEPARATOR, limit = 2)
            if (parts.size == 2 && parts[0].isNotBlank())
                Subscription(url = parts[0], name = parts[1])
            else null
        }.sortedBy { it.name.lowercase() }
    }

    /** Number of subscribed channels. */
    fun count(): Int = rawSet().size

    private fun rawSet(): Set<String> =
        prefs.getStringSet(KEY_CHANNELS, emptySet()) ?: emptySet()
}

/** A subscribed channel. */
data class Subscription(val url: String, val name: String, val avatarUrl: String = "")