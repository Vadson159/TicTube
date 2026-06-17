package com.tictube

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class YouTubeApi private constructor(private val context: Context) {

    companion object {
        private const val TAG = "YouTubeApi"

        @Volatile private var instance: YouTubeApi? = null
        fun getInstance(ctx: Context): YouTubeApi =
            instance ?: synchronized(this) {
                instance ?: YouTubeApi(ctx.applicationContext).also { instance = it }
            }
    }

    private val authManager = AuthManager.getInstance(context)
    @Volatile var lastError: String? = null
        private set

    private data class SubscriptionFetchResult(
        val subscriptions: List<Subscription>,
        val responseCode: Int = HttpURLConnection.HTTP_OK,
        val errorMessage: String = ""
    )

    suspend fun getSubscriptions(): List<Subscription> = withContext(Dispatchers.IO) {
        lastError = null
        var token = authManager.getAccessToken() ?: run {
            lastError = authManager.lastError
            return@withContext emptyList()
        }

        repeat(2) { attempt ->
            val result = fetchSubscriptions(token)
            if (result.responseCode == HttpURLConnection.HTTP_OK) {
                return@withContext result.subscriptions
            }

            val canRefresh = result.responseCode == HttpURLConnection.HTTP_UNAUTHORIZED ||
                result.responseCode == HttpURLConnection.HTTP_FORBIDDEN
            if (attempt == 0 && canRefresh) {
                authManager.invalidateToken(token)
                val refreshedToken = authManager.getAccessToken(forceRefresh = true)
                if (refreshedToken != null) {
                    token = refreshedToken
                    return@repeat
                }
            }

            lastError = result.errorMessage.ifBlank { "YouTube API error ${result.responseCode}" }
            return@withContext emptyList()
        }

        lastError = "Could not refresh YouTube access"
        emptyList()
    }

    private fun fetchSubscriptions(token: String): SubscriptionFetchResult {
        val channels = mutableListOf<Subscription>()
        var nextPageToken: String? = null

        return try {
            do {
                var urlStr = "https://youtube.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&maxResults=50"
                if (nextPageToken != null) urlStr += "&pageToken=$nextPageToken"
                
                val url = URL(urlStr)
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 15_000
                conn.readTimeout = 15_000
                conn.setRequestProperty("Accept", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token")
                
                if (conn.responseCode == 200) {
                    val json = JSONObject(conn.inputStream.bufferedReader().readText())
                    val items = json.optJSONArray("items") ?: break
                    for (i in 0 until items.length()) {
                        val item = items.getJSONObject(i)
                        val snippet = item.getJSONObject("snippet")
                        val channelId = snippet.getJSONObject("resourceId").getString("channelId")
                        val title = snippet.getString("title")
                        val thumbnails = snippet.optJSONObject("thumbnails")
                        val avatarUrl = thumbnails?.optJSONObject("default")?.optString("url") ?: ""
                        channels.add(Subscription("https://www.youtube.com/channel/$channelId", title, avatarUrl))
                    }
                    nextPageToken = json.optString("nextPageToken", "").takeIf { it.isNotBlank() }
                } else {
                    val errorBody = conn.errorStream?.bufferedReader()?.readText().orEmpty()
                    val message = "Subscriptions request failed: ${conn.responseCode} ${conn.responseMessage} $errorBody"
                    Log.w(TAG, message)
                    return SubscriptionFetchResult(emptyList(), conn.responseCode, message)
                }
            } while (nextPageToken != null && channels.size < 500) // cap API calls, but allow large accounts
            SubscriptionFetchResult(channels)
        } catch (e: Exception) {
            val message = e.localizedMessage ?: "Failed to load subscriptions"
            Log.w(TAG, "Failed to load subscriptions", e)
            SubscriptionFetchResult(emptyList(), -1, message)
        }
    }

    suspend fun getUploadPlaylists(channelIds: List<String>): List<String> = withContext(Dispatchers.IO) {
        val token = authManager.getAccessToken() ?: return@withContext emptyList()
        val playlists = mutableListOf<String>()
        
        try {
            // YouTube API allows up to 50 IDs per request
            channelIds.chunked(50).forEach { chunk ->
                val ids = chunk.joinToString(",")
                val url = URL("https://youtube.googleapis.com/youtube/v3/channels?part=contentDetails&id=$ids")
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 15_000
                conn.readTimeout = 15_000
                conn.setRequestProperty("Accept", "application/json")
                conn.setRequestProperty("Authorization", "Bearer $token")
                
                if (conn.responseCode == 200) {
                    val json = JSONObject(conn.inputStream.bufferedReader().readText())
                    val items = json.optJSONArray("items") ?: return@forEach
                    for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val uploadsId = item.optJSONObject("contentDetails")?.optJSONObject("relatedPlaylists")?.optString("uploads")
                if (uploadsId != null) playlists.add(uploadsId)
                    }
                } else {
                    Log.w(TAG, "Upload playlists request failed: ${conn.responseCode} ${conn.responseMessage}")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load upload playlists", e)
        }
        return@withContext playlists
    }

    suspend fun getLatestVideos(playlistId: String, maxResults: Int = 5): List<VideoItem> = withContext(Dispatchers.IO) {
        val token = authManager.getAccessToken() ?: return@withContext emptyList()
        val videos = mutableListOf<VideoItem>()
        
        try {
            val url = URL("https://youtube.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=$playlistId&maxResults=$maxResults")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            conn.setRequestProperty("Accept", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $token")
            
            if (conn.responseCode == 200) {
                val json = JSONObject(conn.inputStream.bufferedReader().readText())
                val items = json.optJSONArray("items") ?: return@withContext emptyList()
                for (i in 0 until items.length()) {
                    val snippet = items.getJSONObject(i).getJSONObject("snippet")
                    val videoId = snippet.getJSONObject("resourceId").getString("videoId")
                    val title = snippet.getString("title")
                    val uploader = snippet.getString("channelTitle")
                    val thumbnails = snippet.optJSONObject("thumbnails")
                    val thumbUrl = thumbnails?.optJSONObject("high")?.optString("url") 
                        ?: thumbnails?.optJSONObject("medium")?.optString("url") 
                        ?: thumbnails?.optJSONObject("default")?.optString("url") ?: ""
                        
                    videos.add(VideoItem(
                        id = videoId,
                        videoUrl = "https://www.youtube.com/watch?v=$videoId",
                        title = title,
                        channel = uploader,
                        thumbnailUrl = thumbUrl,
                        durationText = "",
                        isLive = false,
                        type = ItemType.VIDEO
                    ))
                }
            } else {
                Log.w(TAG, "Latest videos request failed: ${conn.responseCode} ${conn.responseMessage}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load latest videos", e)
        }
        return@withContext videos
    }
}
