# fix_phase9_v1.ps1
$ErrorActionPreference = 'Stop'
$basePath = Join-Path $PSScriptRoot 'app\src\main\java\com\tictube'
function Emit($path, $content) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [OK] $path" -ForegroundColor Green
}

Emit (Join-Path $basePath 'AuthManager.kt') @'
package com.tictube

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class DeviceCodeResponse(val deviceCode: String, val userCode: String, val verificationUrl: String, val interval: Int)

class AuthManager private constructor(private val context: Context) {
    
    companion object {
        @Volatile private var instance: AuthManager? = null
        fun getInstance(ctx: Context): AuthManager =
            instance ?: synchronized(this) {
                instance ?: AuthManager(ctx.applicationContext).also { instance = it }
            }
            
        private const val SCOPE = "https://www.googleapis.com/auth/youtube.readonly"
    }

    private val settings = SettingsManager.getInstance(context)
    private var accessToken: String? = null
    private var tokenExpiryTime: Long = 0

    suspend fun getAccessToken(): String? = withContext(Dispatchers.IO) {
        if (accessToken != null && System.currentTimeMillis() < tokenExpiryTime - 60000) {
            return@withContext accessToken
        }
        
        val refreshToken = settings.refreshToken
        val clientId = settings.clientId
        val clientSecret = settings.clientSecret
        
        if (refreshToken.isBlank() || clientId.isBlank() || clientSecret.isBlank()) return@withContext null

        try {
            val url = URL("https://oauth2.googleapis.com/token")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            
            val params = "client_id=${URLEncoder.encode(clientId, "UTF-8")}" +
                         "&client_secret=${URLEncoder.encode(clientSecret, "UTF-8")}" +
                         "&refresh_token=${URLEncoder.encode(refreshToken, "UTF-8")}" +
                         "&grant_type=refresh_token"
                         
            conn.outputStream.write(params.toByteArray())
            
            if (conn.responseCode == 200) {
                val response = conn.inputStream.bufferedReader().readText()
                val json = JSONObject(response)
                accessToken = json.getString("access_token")
                val expiresIn = json.getInt("expires_in")
                tokenExpiryTime = System.currentTimeMillis() + (expiresIn * 1000L)
                return@withContext accessToken
            } else {
                val err = conn.errorStream.bufferedReader().readText()
                if (err.contains("invalid_grant")) {
                    settings.clearAuth()
                    accessToken = null
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext null
    }

    suspend fun requestDeviceCode(): DeviceCodeResponse? = withContext(Dispatchers.IO) {
        val clientId = settings.clientId
        if (clientId.isBlank()) return@withContext null
        
        try {
            val url = URL("https://oauth2.googleapis.com/device/code")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            
            val params = "client_id=${URLEncoder.encode(clientId, "UTF-8")}" +
                         "&scope=${URLEncoder.encode(SCOPE, "UTF-8")}"
                         
            conn.outputStream.write(params.toByteArray())
            
            if (conn.responseCode == 200) {
                val json = JSONObject(conn.inputStream.bufferedReader().readText())
                return@withContext DeviceCodeResponse(
                    deviceCode = json.getString("device_code"),
                    userCode = json.getString("user_code"),
                    verificationUrl = json.getString("verification_url"),
                    interval = json.optInt("interval", 5)
                )
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext null
    }

    suspend fun pollForToken(deviceCode: String, intervalSeconds: Int, onProgress: () -> Boolean): Boolean = withContext(Dispatchers.IO) {
        val clientId = settings.clientId
        val clientSecret = settings.clientSecret
        
        while (onProgress()) {
            delay(intervalSeconds * 1000L)
            
            try {
                val url = URL("https://oauth2.googleapis.com/token")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                
                val params = "client_id=${URLEncoder.encode(clientId, "UTF-8")}" +
                             "&client_secret=${URLEncoder.encode(clientSecret, "UTF-8")}" +
                             "&device_code=${URLEncoder.encode(deviceCode, "UTF-8")}" +
                             "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
                             
                conn.outputStream.write(params.toByteArray())
                
                val code = conn.responseCode
                if (code == 200) {
                    val json = JSONObject(conn.inputStream.bufferedReader().readText())
                    settings.refreshToken = json.getString("refresh_token")
                    accessToken = json.getString("access_token")
                    tokenExpiryTime = System.currentTimeMillis() + (json.getInt("expires_in") * 1000L)
                    return@withContext true
                } else if (code == 400) {
                    val err = conn.errorStream.bufferedReader().readText()
                    if (!err.contains("authorization_pending")) {
                        return@withContext false
                    }
                } else {
                    return@withContext false
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        return@withContext false
    }
}

'@


Emit (Join-Path $basePath 'YouTubeApi.kt') @'
package com.tictube

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class YouTubeApi private constructor(private val context: Context) {

    companion object {
        @Volatile private var instance: YouTubeApi? = null
        fun getInstance(ctx: Context): YouTubeApi =
            instance ?: synchronized(this) {
                instance ?: YouTubeApi(ctx.applicationContext).also { instance = it }
            }
    }

    private val authManager = AuthManager.getInstance(context)

    suspend fun getSubscriptions(): List<String> = withContext(Dispatchers.IO) {
        val token = authManager.getAccessToken() ?: return@withContext emptyList()
        val channels = mutableListOf<String>()
        var nextPageToken: String? = null

        try {
            do {
                var urlStr = "https://youtube.googleapis.com/youtube/v3/subscriptions?part=snippet&mine=true&maxResults=50"
                if (nextPageToken != null) urlStr += "&pageToken=$nextPageToken"
                
                val url = URL(urlStr)
                val conn = url.openConnection() as HttpURLConnection
                conn.setRequestProperty("Authorization", "Bearer $token")
                
                if (conn.responseCode == 200) {
                    val json = JSONObject(conn.inputStream.bufferedReader().readText())
                    val items = json.optJSONArray("items") ?: break
                    for (i in 0 until items.length()) {
                        val item = items.getJSONObject(i)
                        val channelId = item.getJSONObject("snippet").getJSONObject("resourceId").getString("channelId")
                        channels.add(channelId)
                    }
                    nextPageToken = json.optString("nextPageToken", "").takeIf { it.isNotBlank() }
                } else {
                    break
                }
            } while (nextPageToken != null && channels.size < 200) // limit to 200 to avoid excessive API calls
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext channels
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
                conn.setRequestProperty("Authorization", "Bearer $token")
                
                if (conn.responseCode == 200) {
                    val json = JSONObject(conn.inputStream.bufferedReader().readText())
                    val items = json.optJSONArray("items") ?: return@forEach
                    for (i in 0 until items.length()) {
                        val item = items.getJSONObject(i)
                        val uploadsId = item.optJSONObject("contentDetails")?.optJSONObject("relatedPlaylists")?.optString("uploads")
                        if (uploadsId != null) playlists.add(uploadsId)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext playlists
    }

    suspend fun getLatestVideos(playlistId: String, maxResults: Int = 5): List<VideoItem> = withContext(Dispatchers.IO) {
        val token = authManager.getAccessToken() ?: return@withContext emptyList()
        val videos = mutableListOf<VideoItem>()
        
        try {
            val url = URL("https://youtube.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=$playlistId&maxResults=$maxResults")
            val conn = url.openConnection() as HttpURLConnection
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
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext videos
    }
}

'@


Emit (Join-Path $basePath 'SettingsManager.kt') @'
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

    var clientId: String
        get() = prefs.getString(KEY_CLIENT_ID, "") ?: ""
        set(value) { prefs.edit().putString(KEY_CLIENT_ID, value.trim()).apply() }

    var clientSecret: String
        get() = prefs.getString(KEY_CLIENT_SECRET, "") ?: ""
        set(value) { prefs.edit().putString(KEY_CLIENT_SECRET, value.trim()).apply() }

    var refreshToken: String
        get() = prefs.getString(KEY_REFRESH_TOKEN, "") ?: ""
        set(value) { prefs.edit().putString(KEY_REFRESH_TOKEN, value).apply() }
        
    fun clearAuth() {
        refreshToken = ""
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
'@


Emit (Join-Path $basePath 'MainScreen.kt') @'
package com.tictube

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.speech.RecognizerIntent
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.TextStyle
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.List
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.Close
import androidx.wear.compose.material.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.ScalingLazyColumn
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import androidx.wear.compose.material.rememberScalingLazyListState
import coil.compose.AsyncImage
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.InfoItem
import org.schabi.newpipe.extractor.ListExtractor
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType

enum class ItemType { VIDEO, PLAYLIST }

data class VideoItem(
    val id: String, val title: String, val channel: String,
    val durationText: String, val thumbnailUrl: String = "",
    val videoUrl: String = "", val type: ItemType = ItemType.VIDEO,
    val isLive: Boolean = false
)

sealed interface UiState {
    object Loading : UiState
    data class Videos(val videos: List<VideoItem>) : UiState
    data class Channels(val subs: List<Subscription>) : UiState
    data class History(val entries: List<HistoryEntry>) : UiState
    data class Downloads(val entries: List<DownloadEntry>) : UiState
    data class Error(val message: String) : UiState
    data class AuthSetup(val code: String, val url: String) : UiState
}

enum class ScreenMode { FEED, SUBSCRIPTIONS, CHANNEL, HISTORY, DOWNLOADS, PLAYLIST, TAGS, AUTH, SHORTS }

class MainViewModel(app: Application) : AndroidViewModel(app) {
    companion object { 
        private const val TAG = "MainVM"
        val AVAILABLE_TAGS = listOf("Tech", "Business", "Travel", "Science", "Music", "Gaming", "News", "Sports", "Podcasts", "Comedy", "Cars", "Fitness")
    }

    private val subMgr = SubscriptionManager.getInstance(app)
    private val histMgr = HistoryManager.getInstance(app)
    private val dlMgr = DownloadManager.getInstance(app)
    val settingsMgr = SettingsManager.getInstance(app)
    private val prefs = app.getSharedPreferences("tictube_tags", Context.MODE_PRIVATE)

    private val _mode = MutableStateFlow(ScreenMode.FEED)
    val mode: StateFlow<ScreenMode> = _mode.asStateFlow()
    private val _ui = MutableStateFlow<UiState>(UiState.Loading)
    val ui: StateFlow<UiState> = _ui.asStateFlow()
    private val _header = MutableStateFlow("")
    val header: StateFlow<String> = _header.asStateFlow()
    private val _quality = MutableStateFlow(settingsMgr.getQuality())
    val quality: StateFlow<SettingsManager.StreamQuality> = _quality.asStateFlow()

    private val authMgr = AuthManager.getInstance(app)
    private val ytApi = YouTubeApi.getInstance(app)
    private var subChannels = listOf<String>()

    private val _activeTags = MutableStateFlow(
        prefs.getStringSet("tags", AVAILABLE_TAGS.toSet())?.toList() ?: AVAILABLE_TAGS
    )
    val activeTags: StateFlow<List<String>> = _activeTags.asStateFlow()

    private var currentExtractor: ListExtractor<InfoItem>? = null
    private var nextPageUrl: Page? = null
    private var isLoadingMore = false
    private var lastQuery = ""
    private var isMixedFeed = true

    private val seenVideoIds = mutableSetOf<String>()
    private val tagPages = mutableMapOf<String, Page?>()
    private val tagExtractors = mutableMapOf<String, ListExtractor<InfoItem>>()

    init { loadMixedFeed(clear = true) }

    fun toggleTag(tag: String) {
        val current = _activeTags.value.toMutableSet()
        if (current.contains(tag) && current.size > 1) current.remove(tag) else current.add(tag)
        prefs.edit().putStringSet("tags", current).apply()
        _activeTags.value = current.toList()
    }

    fun showTags() { _mode.value = ScreenMode.TAGS; _header.value = "Feed Topics"; _ui.value = UiState.Loading }

    fun loadMixedFeed(clear: Boolean = true) {
        if (isLoadingMore) return
        isLoadingMore = true; isMixedFeed = true; lastQuery = ""
        if (clear) { _mode.value = ScreenMode.FEED; _header.value = "\uD83C\uDFB2 Mixed Feed"; seenVideoIds.clear(); tagPages.clear(); tagExtractors.clear(); _ui.value = UiState.Loading }
        viewModelScope.launch {
            try {
                val vids = withContext(Dispatchers.IO) {
                    val list = mutableListOf<VideoItem>()
                    val token = authMgr.getAccessToken()
                    if (token != null) {
                        if (subChannels.isEmpty()) subChannels = ytApi.getSubscriptions()
                        if (subChannels.isNotEmpty()) {
                            val randomCh = subChannels.shuffled().take(2)
                            val playlists = ytApi.getUploadPlaylists(randomCh)
                            playlists.forEach { pl -> list.addAll(ytApi.getLatestVideos(pl, 4)) }
                        }
                    }
                    
                    val tags = _activeTags.value
                    val randomTag = if (tags.isNotEmpty()) tags.random() else "Tech"
                    
                    if (!tagExtractors.containsKey(randomTag)) {
                        val ext = ServiceList.YouTube.getSearchExtractor(randomTag)
                        @Suppress("UNCHECKED_CAST")
                        tagExtractors[randomTag] = ext as ListExtractor<InfoItem>
                        ext.fetchPage()
                        tagPages[randomTag] = ext.initialPage.nextPage
                        list.addAll(ext.initialPage.items.mapNotNull { it.toItem() })
                    } else {
                        val ext = tagExtractors[randomTag]!!
                        val nextPage = tagPages[randomTag]
                        if (nextPage != null) { val page = ext.getPage(nextPage); tagPages[randomTag] = page.nextPage; list.addAll(page.items.mapNotNull { it.toItem() }) }
                    }
                    list
                }
                
                val uniqueVids = vids.filter { it.type == ItemType.VIDEO && seenVideoIds.add(it.id) }.shuffled()
                val currentState = _ui.value
                if (clear || currentState !is UiState.Videos) _ui.value = if (uniqueVids.isEmpty()) UiState.Error("No videos found.") else UiState.Videos(uniqueVids)
                else _ui.value = UiState.Videos(currentState.videos + uniqueVids)
            } catch (e: Exception) { if (clear) _ui.value = UiState.Error(e.localizedMessage ?: "Failed to load feed") } finally { isLoadingMore = false }
        }
    }

    fun search(query: String) {
        if (query.isBlank()) { loadMixedFeed(true); return }
        lastQuery = query; isMixedFeed = false; _mode.value = ScreenMode.FEED; _header.value = "\uD83D\uDD0D $query"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ext = ServiceList.YouTube.getSearchExtractor(query)
                    @Suppress("UNCHECKED_CAST")
                    currentExtractor = ext as? ListExtractor<InfoItem>
                    ext.fetchPage(); nextPageUrl = ext.initialPage.nextPage; ext.initialPage.items.mapNotNull { it.toItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No results") else UiState.Videos(vids)
            } catch (e: Exception) { _ui.value = UiState.Error(e.localizedMessage ?: "Search failed") }
        }
    }

    fun loadMore() {
        if (isMixedFeed) { loadMixedFeed(clear = false); return }
        if (isLoadingMore || nextPageUrl == null) return
        val ext = currentExtractor ?: return
        val currentState = _ui.value
        if (currentState !is UiState.Videos) return
        isLoadingMore = true
        viewModelScope.launch {
            try {
                val moreVids = withContext(Dispatchers.IO) { val page = ext.getPage(nextPageUrl); nextPageUrl = page.nextPage; page.items.mapNotNull { it.toItem() } }
                _ui.value = UiState.Videos(currentState.videos + moreVids)
            } catch (e: Exception) { } finally { isLoadingMore = false }
        }
    }

    fun deleteDownload(fileName: String) { viewModelScope.launch(Dispatchers.IO) { dlMgr.delete(fileName); val d = dlMgr.getAll(); _ui.value = if (d.isEmpty()) UiState.Error("No downloads left.") else UiState.Downloads(d) } }
    fun showSubscriptions() { _mode.value = ScreenMode.SUBSCRIPTIONS; _header.value = "\u2764\uFE0F My Channels"; val s = subMgr.getAll(); _ui.value = if (s.isEmpty()) UiState.Error("No subscriptions yet.") else UiState.Channels(s) }
    fun showHistory() { _mode.value = ScreenMode.HISTORY; _header.value = "\uD83D\uDD52 History"; val h = histMgr.getAll(); _ui.value = if (h.isEmpty()) UiState.Error("No history yet.") else UiState.History(h) }
    fun showDownloads() { _mode.value = ScreenMode.DOWNLOADS; _header.value = "\uD83D\uDCBE Downloads"; val d = dlMgr.getAll(); _ui.value = if (d.isEmpty()) UiState.Error("No downloads yet.") else UiState.Downloads(d) }
    fun cycleQuality() { _quality.value = settingsMgr.cycleQuality() }
    
    fun showShorts() {
        if (isLoadingMore) return
        isLoadingMore = true; isMixedFeed = false; lastQuery = ""
        _mode.value = ScreenMode.SHORTS; _header.value = "\u26A1 Shorts"; currentExtractor = null; nextPageUrl = null; _ui.value = UiState.Loading
        viewModelScope.launch {
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ext = ServiceList.YouTube.getSearchExtractor("#shorts")
                    @Suppress("UNCHECKED_CAST")
                    currentExtractor = ext as? ListExtractor<InfoItem>
                    ext.fetchPage(); nextPageUrl = ext.initialPage.nextPage; ext.initialPage.items.mapNotNull { it.toItem() }.filter { it.durationText.contains(":") && it.durationText.split(":").let { p -> p.size == 2 && p[0].toIntOrNull() == 0 } }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No shorts found") else UiState.Videos(vids)
            } catch (e: Exception) { _ui.value = UiState.Error(e.localizedMessage ?: "Failed") } finally { isLoadingMore = false }
        }
    }
    
    fun startAuth(clientId: String, clientSecret: String) {
        settingsMgr.clientId = clientId
        settingsMgr.clientSecret = clientSecret
        _mode.value = ScreenMode.AUTH
        _header.value = "Google Login"
        _ui.value = UiState.Loading
        viewModelScope.launch {
            val res = authMgr.requestDeviceCode()
            if (res != null) {
                _ui.value = UiState.AuthSetup(res.userCode, res.verificationUrl)
                val success = authMgr.pollForToken(res.deviceCode, res.interval) { _mode.value == ScreenMode.AUTH }
                if (success) {
                    loadMixedFeed(true)
                } else {
                    _ui.value = UiState.Error("Login failed or timed out")
                }
            } else {
                _ui.value = UiState.Error("Failed to get device code. Check Client ID/Secret.")
            }
        }
    }

    fun showAuthSetup() {
        _mode.value = ScreenMode.AUTH
        _header.value = "Google Login"
        _ui.value = UiState.AuthSetup("", "")
    }

    fun loadChannel(url: String, name: String) {
        _mode.value = ScreenMode.CHANNEL; _header.value = name
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ce = ServiceList.YouTube.getChannelExtractor(url); ce.fetchPage()
                    val tab = ce.tabs.firstOrNull { t -> t.contentFilters.any { it.contains("videos", true) } } ?: ce.tabs.firstOrNull() ?: throw Exception("No tabs")
                    val te = ServiceList.YouTube.getChannelTabExtractor(tab)
                    @Suppress("UNCHECKED_CAST")
                    currentExtractor = te as? ListExtractor<InfoItem>
                    te.fetchPage(); nextPageUrl = te.initialPage.nextPage; te.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No videos") else UiState.Videos(vids)
            } catch (e: Exception) { _ui.value = UiState.Error(e.localizedMessage ?: "Failed") }
        }
    }

    fun loadPlaylist(url: String) {
        _mode.value = ScreenMode.PLAYLIST; _header.value = "\uD83C\uDFB5 Playlist"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val pe = ServiceList.YouTube.getPlaylistExtractor(url); pe.fetchPage()
                    _header.value = "\uD83C\uDFB5 ${pe.name}"; currentExtractor = null; nextPageUrl = null
                    pe.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("Empty playlist") else UiState.Videos(vids)
            } catch (e: Exception) { _ui.value = UiState.Error(e.localizedMessage ?: "Failed") }
        }
    }

    fun goBack() { when (_mode.value) { ScreenMode.CHANNEL -> showSubscriptions(); ScreenMode.TAGS -> loadMixedFeed(true); ScreenMode.AUTH -> loadMixedFeed(true); else -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true) } }
    fun retry() { when (_mode.value) { ScreenMode.FEED -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true); ScreenMode.SHORTS -> showShorts(); ScreenMode.SUBSCRIPTIONS -> showSubscriptions(); ScreenMode.HISTORY -> showHistory(); ScreenMode.DOWNLOADS -> showDownloads(); ScreenMode.TAGS -> showTags(); else -> loadMixedFeed(true) } }

    private fun InfoItem.toItem(): VideoItem? = when (this) { is StreamInfoItem -> toVideoItem(); is PlaylistInfoItem -> VideoItem(url, "\uD83C\uDFB5 $name", uploaderName.orEmpty(), "${streamCount} videos", thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.PLAYLIST); else -> null }
    private fun StreamInfoItem.toVideoItem(): VideoItem { val live = streamType == StreamType.LIVE_STREAM || streamType == StreamType.AUDIO_LIVE_STREAM; return VideoItem(url, name, uploaderName.orEmpty(), if (live) "LIVE" else fmtDur(duration), thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.VIDEO, isLive = live) }
}

private fun fmtDur(s: Long): String { if (s < 0) return "LIVE"; val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60; return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec) }

@Composable
fun VideoCard(video: VideoItem, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFF1E1E1E))
            .clickable { onClick() }
            .padding(6.dp)
    ) {
        Box(modifier = Modifier.fillMaxWidth().height(80.dp).clip(RoundedCornerShape(8.dp))) {
            AsyncImage(model = video.thumbnailUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Box(modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp).background(if (video.isLive) Color(0xFFCC0000) else Color.Black.copy(0.8f), RoundedCornerShape(4.dp))) {
                Text(if (video.isLive) "LIVE" else video.durationText, color = Color.White, style = MaterialTheme.typography.caption3, modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(video.title, style = MaterialTheme.typography.caption2, maxLines = 2, overflow = TextOverflow.Ellipsis, color = Color.White)
        Text(video.channel, style = MaterialTheme.typography.caption3, color = Color.Gray, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val ui by viewModel.ui.collectAsState()
    val mode by viewModel.mode.collectAsState()
    val header by viewModel.header.collectAsState()
    val quality by viewModel.quality.collectAsState()
    val activeTags by viewModel.activeTags.collectAsState()
    
    val listState = rememberScalingLazyListState()
    val focus = remember { FocusRequester() }
    val ctx = LocalContext.current
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }
    val subMgr = remember { SubscriptionManager.getInstance(ctx.applicationContext) }
    val scope = rememberCoroutineScope()
    val storagePerm = rememberPermissionState(Manifest.permission.READ_EXTERNAL_STORAGE)
    val notifPerm = rememberPermissionState(Manifest.permission.POST_NOTIFICATIONS)

    var hasActivePlayer by remember { mutableStateOf(PlaybackService.player?.currentMediaItem != null) }
    LaunchedEffect(Unit) {
        if (!notifPerm.status.isGranted) {
            notifPerm.launchPermissionRequest()
        }
        while(true) {
            hasActivePlayer = PlaybackService.player?.currentMediaItem != null
            kotlinx.coroutines.delay(1000)
        }
    }

    val isAtBottom by remember { derivedStateOf { val layoutInfo = listState.layoutInfo; val totalItems = layoutInfo.totalItemsCount; val lastVisibleItem = layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0; lastVisibleItem >= totalItems - 3 && totalItems > 0 } }
    LaunchedEffect(isAtBottom) { if (isAtBottom && (mode == ScreenMode.FEED || mode == ScreenMode.CHANNEL)) viewModel.loadMore() }

    val speechLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result -> if (result.resultCode == Activity.RESULT_OK) { result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { viewModel.search(it) } } }

    Scaffold(timeText = { TimeText() }, vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) }, positionIndicator = { PositionIndicator(scalingLazyListState = listState) }) {
        ScalingLazyColumn(state = listState, modifier = Modifier.fillMaxSize().background(Color(0xFF0F0F0F)).rotaryScrollable(behavior = RotaryScrollableDefaults.behavior(listState), focusRequester = focus)) {
            if (mode == ScreenMode.TAGS) {
                item { Chip(onClick = { viewModel.loadMixedFeed(true) }, label = { Text("Back & Refresh") }, icon = { Icon(Icons.Rounded.Refresh, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { Text("Select Feed Topics", style = MaterialTheme.typography.caption1, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }
                items(MainViewModel.AVAILABLE_TAGS.size) { i ->
                    val tag = MainViewModel.AVAILABLE_TAGS[i]
                    val isSelected = activeTags.contains(tag)
                    Chip(onClick = { viewModel.toggleTag(tag) }, label = { Text(tag) }, secondaryLabel = { Text(if (isSelected) "Enabled" else "Disabled", color = if(isSelected) Color.Green else Color.Gray) }, colors = if (isSelected) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
            } else {
                item { Chip(onClick = { try { speechLauncher.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply { putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM); putExtra(RecognizerIntent.EXTRA_PROMPT, "Search") }) } catch (e: Exception) {} }, label = { Text("Search YouTube") }, icon = { Icon(Icons.Rounded.Search, null, tint = Color.White) }, colors = ChipDefaults.chipColors(backgroundColor = Color(0xFFCC0000)), modifier = Modifier.fillMaxWidth()) }

                if (hasActivePlayer) {
                    item { Chip(onClick = { ctx.startActivity(Intent(ctx, PlayerActivity::class.java).apply { putExtra("from_notification", true) }) }, label = { Text("Now Playing") }, secondaryLabel = { Text("Tap to resume video") }, icon = { Icon(Icons.Rounded.PlayArrow, null, tint = Color.Green) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                }

                if (mode == ScreenMode.FEED) {
                    item { Chip(onClick = { viewModel.showTags() }, label = { Text("Feed Topics") }, icon = { Icon(Icons.Rounded.List, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showSubscriptions() }, label = { Text("Subscriptions") }, icon = { Icon(Icons.Rounded.Favorite, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showHistory() }, label = { Text("History") }, icon = { Icon(Icons.Rounded.History, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showDownloads() }, label = { Text("Downloads") }, icon = { Icon(Icons.Rounded.Download, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showShorts() }, label = { Text("Shorts") }, icon = { Icon(Icons.Rounded.PlayArrow, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { CompactChip(onClick = { viewModel.showAuthSetup() }, label = { Text("Login / API") }, icon = { Icon(Icons.Rounded.Settings, null, modifier = Modifier.size(16.dp)) }, colors = ChipDefaults.secondaryChipColors()) }
                    item { CompactChip(onClick = { viewModel.cycleQuality() }, label = { Text("Quality: ${quality.label}") }, icon = { Icon(Icons.Rounded.Settings, null, modifier = Modifier.size(16.dp)) }, colors = ChipDefaults.secondaryChipColors()) }
                } else {
                    item { Chip(onClick = { viewModel.goBack() }, label = { Text("Back") }, icon = { Icon(Icons.Rounded.ArrowBack, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                }

                if (mode == ScreenMode.SUBSCRIPTIONS) {
                    item { Chip(onClick = { if (!storagePerm.status.isGranted) storagePerm.launchPermissionRequest(); scope.launch { val r = withContext(Dispatchers.IO) { CsvImporter.import(ctx, subMgr) }; if (r.isSuccess) { Toast.makeText(ctx, "Imported ${r.count}!", Toast.LENGTH_SHORT).show(); viewModel.showSubscriptions() } else { Toast.makeText(ctx, r.error ?: "Failed", Toast.LENGTH_LONG).show() } } }, label = { Text("Import CSV") }, icon = { Icon(Icons.Rounded.FileDownload, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                }

                item { Text(header, style = MaterialTheme.typography.caption1, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }

                when (val s = ui) {
                    is UiState.Loading -> item { Box(Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) { Text("Loading\u2026", style = MaterialTheme.typography.body1) } }
                    is UiState.Error -> item { Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) { Text(s.message, style = MaterialTheme.typography.body2, textAlign = TextAlign.Center, maxLines = 6, overflow = TextOverflow.Ellipsis); Chip(onClick = { viewModel.retry() }, label = { Text("Retry") }, colors = ChipDefaults.chipColors(backgroundColor = Color(0xFFCC0000))) } }
                    is UiState.Channels -> items(s.subs.size) { i -> val sub = s.subs[i]; Chip(onClick = { viewModel.loadChannel(sub.url, sub.name) }, label = { Text(sub.name, maxLines = 2, overflow = TextOverflow.Ellipsis) }, secondaryLabel = { Text("Tap to view") }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    is UiState.History -> items(s.entries.size) { i -> val e = s.entries[i]; Chip(onClick = { ctx.startActivity(PlayerActivity.newIntent(ctx, e.url, e.title)) }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    is UiState.Downloads -> items(s.entries.size) { i -> val e = s.entries[i]; Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) { Chip(onClick = { ctx.startActivity(PlayerActivity.newIntent(ctx, "file://${e.filePath}", e.title)) }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) }, icon = { Icon(Icons.Rounded.PlayArrow, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.weight(1f)); Button(onClick = { viewModel.deleteDownload(e.fileName) }, modifier = Modifier.size(52.dp), colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFCC0000))) { Icon(Icons.Rounded.Close, null) } } }
                    is UiState.Videos -> items(s.videos.size) { i -> val v = s.videos[i]; VideoCard(v) { if (v.type == ItemType.PLAYLIST) { viewModel.loadPlaylist(v.videoUrl) } else { histMgr.add(v.videoUrl, v.title); val allVids = s.videos.filter { it.type == ItemType.VIDEO }; if (mode == ScreenMode.PLAYLIST && allVids.size > 1) { val idx = allVids.indexOf(v).coerceAtLeast(0); ctx.startActivity(PlayerActivity.newPlaylistIntent(ctx, ArrayList(allVids.map { it.videoUrl }), ArrayList(allVids.map { it.title }), idx)) } else { ctx.startActivity(PlayerActivity.newIntent(ctx, v.videoUrl, v.title)) } } } }
                    is UiState.AuthSetup -> {
                        if (s.code.isNotBlank()) {
                            item { Text("Go to ${s.url}", style = MaterialTheme.typography.caption2, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                            item { Text(s.code, style = MaterialTheme.typography.title3, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), color = Color.Green) }
                            item { Text("Waiting for approval...", style = MaterialTheme.typography.caption3, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }
                        } else {
                            item { Text("Client ID:", style = MaterialTheme.typography.caption2) }
                            item { var cid by remember { mutableStateOf(viewModel.settingsMgr.clientId) }; BasicTextField(value = cid, onValueChange = { cid = it }, textStyle = TextStyle(color = Color.White), modifier = Modifier.fillMaxWidth().background(Color.DarkGray).padding(8.dp), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next)); LaunchedEffect(cid) { viewModel.settingsMgr.clientId = cid } }
                            item { Spacer(Modifier.height(8.dp)) }
                            item { Text("Client Secret:", style = MaterialTheme.typography.caption2) }
                            item { var sec by remember { mutableStateOf(viewModel.settingsMgr.clientSecret) }; BasicTextField(value = sec, onValueChange = { sec = it }, textStyle = TextStyle(color = Color.White), modifier = Modifier.fillMaxWidth().background(Color.DarkGray).padding(8.dp), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done)); LaunchedEffect(sec) { viewModel.settingsMgr.clientSecret = sec } }
                            item { Spacer(Modifier.height(8.dp)) }
                            item { Chip(onClick = { viewModel.startAuth(viewModel.settingsMgr.clientId, viewModel.settingsMgr.clientSecret) }, label = { Text("Sign In") }, colors = ChipDefaults.primaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                            item { Chip(onClick = { viewModel.settingsMgr.clearAuth(); Toast.makeText(ctx, "Logged out", Toast.LENGTH_SHORT).show() }, label = { Text("Logout / Clear") }, colors = ChipDefaults.chipColors(backgroundColor = Color(0xFFCC0000)), modifier = Modifier.fillMaxWidth()) }
                        }
                    }
                }
            }
        }
    }

    LaunchedEffect(mode, ui) {
        val firstIdx = listState.layoutInfo.visibleItemsInfo.firstOrNull()?.index ?: 0
        if (mode == ScreenMode.TAGS || ui !is UiState.Videos || firstIdx == 0) {
            focus.requestFocus()
        }
    }
}
'@


Write-Host 'Phase 9 v1 ready!' -ForegroundColor Cyan

