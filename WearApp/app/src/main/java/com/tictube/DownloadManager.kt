package com.tictube

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

data class DownloadEntry(val fileName: String, val title: String, val filePath: String)

class DownloadManager private constructor(private val context: Context) {

    companion object {
        private const val PREFS = "tictube_downloads"
        private const val KEY = "downloaded_files"
        private const val SEP = "||"

        @Volatile private var instance: DownloadManager? = null
        fun getInstance(ctx: Context): DownloadManager =
            instance ?: synchronized(this) {
                instance ?: DownloadManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val dir = File(context.filesDir, "downloads").apply { mkdirs() }
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    suspend fun download(streamUrl: String, title: String): DownloadEntry =
        withContext(Dispatchers.IO) {
            val name = fileNameFor(streamUrl, title)
            val file = File(dir, name)
            val tempFile = File(dir, "$name.part")
            var completed = false

            val conn = URL(streamUrl).openConnection() as HttpURLConnection
            conn.connectTimeout = 30_000
            conn.readTimeout = 120_000
            conn.instanceFollowRedirects = true
            conn.setRequestProperty("User-Agent",
                "Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0")

            val job = currentCoroutineContext()[Job]
            val cancelHandle = job?.invokeOnCompletion { cause ->
                if (cause is CancellationException) conn.disconnect()
            }

            try {
                tempFile.delete()
                conn.inputStream.use { inp ->
                    tempFile.outputStream().use { out ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            if (job?.isActive == false) throw CancellationException("Download cancelled")
                            val read = inp.read(buffer)
                            if (read < 0) break
                            out.write(buffer, 0, read)
                        }
                    }
                }

                file.delete()
                if (!tempFile.renameTo(file)) {
                    tempFile.copyTo(file, overwrite = true)
                    tempFile.delete()
                }

                val entry = DownloadEntry(name, title, file.absolutePath)
                val set = (prefs.getStringSet(KEY, emptySet()) ?: emptySet()).toMutableSet()
                set.removeAll { it.startsWith("$name$SEP") }
                set.add("$name$SEP$title")
                prefs.edit().putStringSet(KEY, set).apply()
                completed = true
                entry
            } finally {
                cancelHandle?.dispose()
                conn.disconnect()
                if (!completed) {
                    tempFile.delete()
                    file.delete()
                    removeEntry(name)
                }
            }
        }

    fun getAll(): List<DownloadEntry> {
        val set = prefs.getStringSet(KEY, emptySet()) ?: emptySet()
        return set.mapNotNull { e ->
            val p = e.split(SEP, limit = 2)
            if (p.size == 2) {
                val f = File(dir, p[0])
                if (f.exists()) DownloadEntry(p[0], p[1], f.absolutePath) else null
            } else null
        }.sortedByDescending { it.fileName }
    }

    fun delete(fileName: String) {
        File(dir, fileName).delete()
        File(dir, "$fileName.part").delete()
        removeEntry(fileName)
    }

    fun deleteBySource(streamUrl: String, title: String) {
        delete(fileNameFor(streamUrl, title))
    }

    private fun fileNameFor(streamUrl: String, title: String): String {
        val safe = title.replace(Regex("[^a-zA-Z0-9._-]"), "_").trim('_').ifBlank { "video" }.take(40)
        val ext = if (streamUrl.contains("audio", true) ||
            streamUrl.contains("m4a", true)) ".m4a" else ".mp4"
        return "${safe}_${Integer.toHexString(streamUrl.hashCode())}$ext"
    }

    private fun removeEntry(fileName: String) {
        val set = (prefs.getStringSet(KEY, emptySet()) ?: emptySet()).toMutableSet()
        set.removeAll { it.startsWith("$fileName$SEP") }
        prefs.edit().putStringSet(KEY, set).apply()
    }
}
