package com.tictube

import android.content.Context

data class HistoryEntry(val url: String, val title: String, val timestamp: Long, val positionMs: Long = 0L)

class HistoryManager private constructor(context: Context) {

    companion object {
        private const val PREFS = "tictube_history"
        private const val KEY = "watch_history"
        private const val SEP = "||"
        private const val MAX = 100

        @Volatile private var instance: HistoryManager? = null
        fun getInstance(ctx: Context): HistoryManager =
            instance ?: synchronized(this) {
                instance ?: HistoryManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun add(url: String, title: String, positionMs: Long = 0L) {
        if (url.isBlank()) return
        val set = raw().toMutableSet()
        set.removeAll { it.contains("$SEP$url$SEP") }
        set.add("${System.currentTimeMillis()}$SEP$url$SEP$title$SEP$positionMs")
        val trimmed = set.sortedByDescending {
            it.substringBefore(SEP).toLongOrNull() ?: 0L
        }.take(MAX).toSet()
        prefs.edit().putStringSet(KEY, trimmed).apply()
    }

    fun getAll(): List<HistoryEntry> = raw().mapNotNull { e ->
        val p = e.split(SEP)
        if (p.size >= 3) {
            val pos = if (p.size >= 4) p[3].toLongOrNull() ?: 0L else 0L
            HistoryEntry(p[1], p[2], p[0].toLongOrNull() ?: 0L, pos)
        } else null
    }.sortedByDescending { it.timestamp }

    fun clear() { prefs.edit().remove(KEY).apply() }

    private fun raw(): Set<String> = prefs.getStringSet(KEY, emptySet()) ?: emptySet()
}