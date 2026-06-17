# fix_phase8_v7.ps1
$ErrorActionPreference = 'Stop'
$basePath = Join-Path $PSScriptRoot 'app\src\main\java\com\tictube'
$manifestDir = Join-Path $PSScriptRoot 'app\src\main'
$resDir = Join-Path $PSScriptRoot 'app\src\main\res\drawable'
$gradlePath = Join-Path $PSScriptRoot 'app\build.gradle.kts'
if (-not (Test-Path $resDir)) { New-Item -ItemType Directory -Force -Path $resDir | Out-Null }
function Emit($path, $content) {
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [OK] $path" -ForegroundColor Green
}

Emit $gradlePath @'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.tictube"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.tictube"
        minSdk = 30
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions {
        jvmTarget = "1.8"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.11"
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.google.android.gms:play-services-wearable:18.1.0")
    
    // Compose
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.wear.compose:compose-material:1.4.0")
    implementation("androidx.wear.compose:compose-foundation:1.4.0")
    implementation("androidx.wear.compose:compose-navigation:1.4.0")
    implementation("androidx.compose.material:material-icons-extended:1.6.0")

    // Media3 (ExoPlayer)
    val media3_version = "1.3.1"
    implementation("androidx.media3:media3-exoplayer:$media3_version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3_version")
    implementation("androidx.media3:media3-ui:$media3_version")
    implementation("androidx.media3:media3-session:$media3_version")

    // NewPipeExtractor
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.26.3")

    // Async / Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-rx3:1.7.3")
    implementation("io.reactivex.rxjava3:rxandroid:3.0.2")

    // Accompanist (permissions)
    implementation("com.google.accompanist:accompanist-permissions:0.35.0-alpha")
    implementation("io.coil-kt:coil-compose:2.6.0")
}
'@


Emit (Join-Path $manifestDir 'AndroidManifest.xml') @'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    >

    <uses-feature android:name="android.hardware.type.watch" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:name=".TicTubeApp"
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:label="TicTube"
        android:supportsRtl="true"
        android:theme="@android:style/Theme.DeviceDefault">
        
        <meta-data
            android:name="com.google.android.wearable.standalone"
            android:value="true" />
            
        <meta-data
            android:name="androidx.media3.session.notification.small_icon"
            android:resource="@drawable/ic_notification" />

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:taskAffinity=""
            android:theme="@android:style/Theme.DeviceDefault">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".PlayerActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@android:style/Theme.DeviceDefault" />

        <service
            android:name=".PlaybackService"
            android:exported="true"
            android:foregroundServiceType="mediaPlayback">
            <intent-filter>
                <action android:name="androidx.media3.session.MediaSessionService" />
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
    </application>
</manifest>
'@


Emit (Join-Path $resDir 'ic_notification.xml') @'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="@android:color/white"
        android:pathData="M8,5.14V19.14L19,12.14L8,5.14Z" />
</vector>

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

        @Volatile private var instance: SettingsManager? = null
        fun getInstance(ctx: Context): SettingsManager =
            instance ?: synchronized(this) {
                instance ?: SettingsManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

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
}

enum class ScreenMode { FEED, SUBSCRIPTIONS, CHANNEL, HISTORY, DOWNLOADS, PLAYLIST, TAGS }

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
                val tags = _activeTags.value
                val randomTag = if (tags.isNotEmpty()) tags.random() else "Tech"
                val vids = withContext(Dispatchers.IO) {
                    if (!tagExtractors.containsKey(randomTag)) {
                        val ext = ServiceList.YouTube.getSearchExtractor(randomTag)
                        @Suppress("UNCHECKED_CAST")
                        tagExtractors[randomTag] = ext as ListExtractor<InfoItem>
                        ext.fetchPage()
                        tagPages[randomTag] = ext.initialPage.nextPage
                        ext.initialPage.items.mapNotNull { it.toItem() }
                    } else {
                        val ext = tagExtractors[randomTag]!!
                        val nextPage = tagPages[randomTag]
                        if (nextPage != null) { val page = ext.getPage(nextPage); tagPages[randomTag] = page.nextPage; page.items.mapNotNull { it.toItem() } } else emptyList()
                    }
                }
                val uniqueVids = vids.filter { it.type == ItemType.VIDEO && seenVideoIds.add(it.id) }
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

    fun goBack() { when (_mode.value) { ScreenMode.CHANNEL -> showSubscriptions(); ScreenMode.TAGS -> loadMixedFeed(true); else -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true) } }
    fun retry() { when (_mode.value) { ScreenMode.FEED -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true); ScreenMode.SUBSCRIPTIONS -> showSubscriptions(); ScreenMode.HISTORY -> showHistory(); ScreenMode.DOWNLOADS -> showDownloads(); ScreenMode.TAGS -> showTags(); else -> loadMixedFeed(true) } }

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


Emit (Join-Path $basePath 'PlayerScreen.kt') @'
package com.tictube

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.FileDownloadDone
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.FastForward
import androidx.compose.material.icons.rounded.FastRewind
import androidx.wear.compose.material.Icon
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.ScalingLazyColumn
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.rememberScalingLazyListState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamType

class PlayerActivity : ComponentActivity() {

    private var videoUrl = ""
    private var videoTitle = ""
    private var plUrls = arrayListOf<String>()
    private var plTitles = arrayListOf<String>()
    private var startIdx = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startService(Intent(this, PlaybackService::class.java))
        parseIntent(intent)
        launchUi()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun parseIntent(intent: Intent) {
        videoUrl = intent.getStringExtra(EXTRA_VIDEO_URL).orEmpty()
        videoTitle = intent.getStringExtra(EXTRA_VIDEO_TITLE).orEmpty()
        plUrls = intent.getStringArrayListExtra(EXTRA_PL_URLS) ?: arrayListOf()
        plTitles = intent.getStringArrayListExtra(EXTRA_PL_TITLES) ?: arrayListOf()
        startIdx = intent.getIntExtra(EXTRA_START_IDX, 0)
    }

    private fun launchUi() {
        setContent { MaterialTheme {
            PlayerScreen(videoUrl, videoTitle, plUrls, plTitles, startIdx)
        }}
    }

    companion object {
        const val EXTRA_VIDEO_URL = "extra_video_url"
        const val EXTRA_VIDEO_TITLE = "extra_video_title"
        const val EXTRA_PL_URLS = "extra_pl_urls"
        const val EXTRA_PL_TITLES = "extra_pl_titles"
        const val EXTRA_START_IDX = "extra_start_idx"

        fun newIntent(ctx: Context, url: String, title: String) = Intent(ctx, PlayerActivity::class.java).apply { putExtra(EXTRA_VIDEO_URL, url); putExtra(EXTRA_VIDEO_TITLE, title) }
        fun newPlaylistIntent(ctx: Context, urls: ArrayList<String>, titles: ArrayList<String>, startIdx: Int) = Intent(ctx, PlayerActivity::class.java).apply { putStringArrayListExtra(EXTRA_PL_URLS, urls); putStringArrayListExtra(EXTRA_PL_TITLES, titles); putExtra(EXTRA_START_IDX, startIdx) }
    }
}

private data class ExtractionResult(val streamUrl: String, val uploaderUrl: String, val uploaderName: String, val description: String, val isLive: Boolean)
data class CommentItem(val author: String, val text: String, val likes: Int, val date: String)
enum class DlState { IDLE, RUNNING, DONE, ERROR }
private val SPEEDS = listOf(1.0f, 1.25f, 1.5f, 2.0f)
private fun fmtSpeed(s: Float): String = if (s == s.toInt().toFloat()) "${s.toInt()}x" else "${s}x"

private suspend fun extract(ytUrl: String, q: SettingsManager.StreamQuality): ExtractionResult =
    withContext(Dispatchers.IO) {
        val ext = ServiceList.YouTube.getStreamExtractor(ytUrl); ext.fetchPage()
        val uUrl = ext.uploaderUrl.orEmpty(); val uName = ext.uploaderName.orEmpty(); val desc = try { ext.description?.content.orEmpty() } catch (_: Exception) { "" }; val sType = ext.streamType
        val isLive = sType == StreamType.LIVE_STREAM || sType == StreamType.AUDIO_LIVE_STREAM; var url: String? = null
        if (isLive) { url = try { ext.hlsUrl } catch (_: Exception) { null } }
        if (url.isNullOrBlank()) {
            val targetRes = when (q) { SettingsManager.StreamQuality.AUDIO_ONLY -> 0; SettingsManager.StreamQuality.Q360P -> 360; SettingsManager.StreamQuality.Q480P -> 480; SettingsManager.StreamQuality.Q720P -> 720; SettingsManager.StreamQuality.Q1080P -> 1080 }
            if (targetRes > 0) { val muxed = try { ext.videoStreams?.filter { it.isUrl } ?: emptyList() } catch (_: Exception) { emptyList() }; url = muxed.minByOrNull { s -> val r = s.resolution?.replace(Regex("p.*"), "")?.toIntOrNull() ?: 999; kotlin.math.abs(r - targetRes) }?.content }
            if (url.isNullOrBlank()) { val audio = try { ext.audioStreams?.filter { it.isUrl } ?: emptyList() } catch (_: Exception) { emptyList() }; url = audio.maxByOrNull { it.averageBitrate }?.content }
        }
        if (url.isNullOrBlank()) throw IllegalStateException("No playable streams")
        ExtractionResult(url, uUrl, uName, desc, isLive)
    }

private suspend fun loadComments(ytUrl: String): List<CommentItem> = withContext(Dispatchers.IO) {
    try { val ce = ServiceList.YouTube.getCommentsExtractor(ytUrl); ce.fetchPage(); ce.initialPage.items.take(20).map { c -> CommentItem(c.uploaderName.orEmpty(), c.commentText?.content?.replace(Regex("<[^>]*>"), "").orEmpty(), c.likeCount, c.textualUploadDate.orEmpty()) } } catch (e: Exception) { emptyList() }
}

@Composable
fun PlayerScreen(videoUrl: String, videoTitle: String, plUrls: List<String> = emptyList(), plTitles: List<String> = emptyList(), startIdx: Int = 0) {
    val ctx = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val audioMgr = remember { ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val subMgr = remember { SubscriptionManager.getInstance(ctx.applicationContext) }
    val dlMgr = remember { DownloadManager.getInstance(ctx.applicationContext) }
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }
    val settMgr = remember { SettingsManager.getInstance(ctx.applicationContext) }
    val scope = rememberCoroutineScope()

    val isPlaylist = plUrls.isNotEmpty()
    var curIdx by remember { mutableIntStateOf(startIdx) }
    val curUrl = if (isPlaylist) plUrls.getOrElse(curIdx) { videoUrl } else videoUrl
    val curTitle = if (isPlaylist) plTitles.getOrElse(curIdx) { videoTitle } else videoTitle
    var resolvedTitle by remember { mutableStateOf(curTitle) }
    val isLocal = curUrl.startsWith("file://") || curUrl.startsWith("/")
    val pageCount = if (isLocal) 1 else 2

    var showCtrls by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMsg by remember { mutableStateOf<String?>(null) }
    var player by remember { mutableStateOf(PlaybackService.player) }
    var upUrl by remember { mutableStateOf("") }; var upName by remember { mutableStateOf("") }; var isSub by remember { mutableStateOf(false) }; var desc by remember { mutableStateOf("") }; var comments by remember { mutableStateOf<List<CommentItem>>(emptyList()) }; var extractedUrl by remember { mutableStateOf("") }; var dlState by remember { mutableStateOf(DlState.IDLE) }; var speed by remember { mutableFloatStateOf(1.0f) }; var isLive by remember { mutableStateOf(false) }

    val volFocus = remember { FocusRequester() }
    val infoFocus = remember { FocusRequester() }
    val pagerState = rememberPagerState(pageCount = { pageCount })

    LaunchedEffect(Unit) { while (player == null) { delay(100); player = PlaybackService.player } }

    LaunchedEffect(player, curUrl) {
        val p = player ?: return@LaunchedEffect
        if (curUrl.isEmpty()) {
            if (p.currentMediaItem != null) { 
                isLoading = false; showCtrls = true; isPlaying = p.isPlaying 
                resolvedTitle = p.currentMediaItem?.mediaMetadata?.title?.toString() ?: "Now Playing"
            }
            return@LaunchedEffect
        }
        
        isLoading = true; errorMsg = null; dlState = DlState.IDLE; desc = ""; comments = emptyList(); isLive = false
        try {
            if (isLocal) {
                p.setMediaItem(MediaItem.fromUri(curUrl)); p.prepare(); p.playWhenReady = true
                isLoading = false; showCtrls = true
            } else {
                val result = extract(curUrl, settMgr.getQuality())
                extractedUrl = result.streamUrl; upUrl = result.uploaderUrl; upName = result.uploaderName
                desc = result.description.replace(Regex("<[^>]*>"), "").trim(); isSub = subMgr.isSubscribed(result.uploaderUrl); isLive = result.isLive
                resolvedTitle = curTitle
                histMgr.add(curUrl, curTitle)

                val mediaItem = if (result.isLive) MediaItem.Builder().setUri(result.streamUrl).setMimeType(MimeTypes.APPLICATION_M3U8).build() else MediaItem.fromUri(result.streamUrl)
                p.setMediaItem(mediaItem); p.prepare(); p.playWhenReady = true
                if (result.isLive) { speed = 1.0f; p.setPlaybackSpeed(1.0f) } else { p.setPlaybackSpeed(speed) }
                isLoading = false; showCtrls = true
            }
        } catch (e: Exception) { Log.e("Player", "extract", e); isLoading = false; errorMsg = e.localizedMessage ?: "Could not load video" }
    }

    LaunchedEffect(curUrl) { if (!isLocal && curUrl.isNotEmpty()) comments = loadComments(curUrl) }
    LaunchedEffect(showCtrls) { if (showCtrls) { delay(5000); showCtrls = false } }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(p: Boolean) { isPlaying = p }
            override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_ENDED && isPlaylist && curIdx < plUrls.size - 1) curIdx++ }
        }
        player?.addListener(listener)
        onDispose { player?.removeListener(listener) }
    }

    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, ev -> if (ev == Lifecycle.Event.ON_START) player?.let { isPlaying = it.isPlaying } }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    LaunchedEffect(pagerState.currentPage) { try { if (pagerState.currentPage == 0) volFocus.requestFocus() else infoFocus.requestFocus() } catch (_: Exception) {} }

    Box(Modifier.fillMaxSize().clip(CircleShape).background(Color.Black)) {
        VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
            when (page) {
                0 -> PlayerPage(
                    player = player, isLoading = isLoading, errorMsg = errorMsg, isPlaying = isPlaying, showCtrls = showCtrls,
                    curTitle = resolvedTitle, upUrl = upUrl, upName = upName, isSub = isSub, extractedUrl = extractedUrl, dlState = dlState, speed = speed,
                    isLocal = isLocal, isLive = isLive, isPlaylist = isPlaylist, curIdx = curIdx, totalTracks = plUrls.size,
                    audioMgr = audioMgr, focusReq = volFocus,
                    onTap = { showCtrls = !showCtrls },
                    onPlayPause = { player?.let { if (it.isPlaying) it.pause() else it.play() } },
                    onSub = { if (isSub) subMgr.unsubscribe(upUrl) else subMgr.subscribe(upUrl, upName); isSub = !isSub; showCtrls = true },
                    onDownload = { if (extractedUrl.isNotBlank() && dlState != DlState.RUNNING) { dlState = DlState.RUNNING; scope.launch { try { dlMgr.download(extractedUrl, resolvedTitle); dlState = DlState.DONE } catch (e: Exception) { dlState = DlState.ERROR } } }; showCtrls = true },
                    onCycleSpeed = { val next = SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.size]; speed = next; player?.setPlaybackSpeed(next); showCtrls = true },
                    onSkipNext = { if (isPlaylist && curIdx < plUrls.size - 1) curIdx++ },
                    onFinish = { (ctx as? ComponentActivity)?.finish() }
                )
                1 -> InfoPage(resolvedTitle, desc, comments, infoFocus)
            }
        }

        if (pageCount > 1) { Column(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) { repeat(pageCount) { idx -> Box(Modifier.size(4.dp).clip(CircleShape).background(if (idx == pagerState.currentPage) Color.White else Color.Gray.copy(0.4f))) } } }
    }
}

@Composable
private fun PlayerPage(
    player: androidx.media3.exoplayer.ExoPlayer?, isLoading: Boolean, errorMsg: String?,
    isPlaying: Boolean, showCtrls: Boolean, curTitle: String, upUrl: String, upName: String, isSub: Boolean,
    extractedUrl: String, dlState: DlState, speed: Float, isLocal: Boolean, isLive: Boolean,
    isPlaylist: Boolean, curIdx: Int, totalTracks: Int,
    audioMgr: AudioManager, focusReq: FocusRequester,
    onTap: () -> Unit, onPlayPause: () -> Unit, onSub: () -> Unit, onDownload: () -> Unit, onCycleSpeed: () -> Unit, onSkipNext: () -> Unit, onFinish: () -> Unit
) {
    var curVol by remember { mutableIntStateOf(audioMgr.getStreamVolume(AudioManager.STREAM_MUSIC)) }
    val maxVol = remember { audioMgr.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }
    var showVolIndicator by remember { mutableStateOf(false) }

    var scrollAccum by remember { mutableFloatStateOf(0f) }
    val scrollThreshold = 80f

    var showRewind by remember { mutableStateOf(false) }
    var showForward by remember { mutableStateOf(false) }

    LaunchedEffect(showVolIndicator) { if (showVolIndicator) { delay(1500); showVolIndicator = false } }
    LaunchedEffect(showRewind) { if (showRewind) { delay(800); showRewind = false } }
    LaunchedEffect(showForward) { if (showForward) { delay(800); showForward = false } }

    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black)
            .onRotaryScrollEvent { ev ->
                scrollAccum += ev.verticalScrollPixels
                if (kotlin.math.abs(scrollAccum) >= scrollThreshold) {
                    val dir = if (scrollAccum > 0f) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
                    audioMgr.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, 0)
                    curVol = audioMgr.getStreamVolume(AudioManager.STREAM_MUSIC)
                    scrollAccum = 0f
                }
                showVolIndicator = true
                true
            }.focusRequester(focusReq).focusable()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { onTap() },
                    onDoubleTap = { offset ->
                        player?.let { p ->
                            if (offset.x < size.width / 2) {
                                p.seekTo((p.currentPosition - 10000).coerceAtLeast(0))
                                showRewind = true
                            } else {
                                p.seekTo((p.currentPosition + 10000).coerceAtMost(p.duration))
                                showForward = true
                            }
                        }
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        if (!isLoading && errorMsg == null) {
            player?.let { exo -> AndroidView(factory = { c -> PlayerView(c).apply { this.player = exo; useController = false; setKeepScreenOn(true) } }, update = { it.player = player }, modifier = Modifier.fillMaxSize()) }
        }

        if (isLive && !isLoading && errorMsg == null) { Text("\uD83D\uDD34 LIVE", color = Color(0xFFFF4444), style = MaterialTheme.typography.caption2, modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp)) }

        if (showVolIndicator) {
            CircularProgressIndicator(progress = curVol.toFloat() / maxVol.toFloat(), modifier = Modifier.fillMaxSize().padding(2.dp), strokeWidth = 4.dp, indicatorColor = Color.Cyan, trackColor = Color.DarkGray.copy(alpha = 0.5f))
            Text(text = "\uD83D\uDD0A $curVol/$maxVol", color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.caption2, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp))
        }

        if (showRewind) { Box(Modifier.fillMaxSize().padding(end = 40.dp), contentAlignment = Alignment.CenterStart) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.FastRewind, null, tint = Color.White, modifier = Modifier.size(32.dp)); Text("10s", color = Color.White, style = MaterialTheme.typography.title3) } } }
        if (showForward) { Box(Modifier.fillMaxSize().padding(start = 40.dp), contentAlignment = Alignment.CenterEnd) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.FastForward, null, tint = Color.White, modifier = Modifier.size(32.dp)); Text("10s", color = Color.White, style = MaterialTheme.typography.title3) } } }

        if (isLoading) Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(indicatorColor = Color(0xFFCC0000), trackColor = Color.DarkGray, modifier = Modifier.size(48.dp)); Spacer(Modifier.height(12.dp)); Text("Loading\u2026", color = Color.White, style = MaterialTheme.typography.body1); Spacer(Modifier.height(4.dp)); Text(curTitle, color = Color.Gray, style = MaterialTheme.typography.caption3, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp)) }
        if (errorMsg != null) Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.Warning, null, tint = Color(0xFFFF6B6B), modifier = Modifier.size(32.dp)); Spacer(Modifier.height(4.dp)); Text("Error", color = Color(0xFFFF6B6B), style = MaterialTheme.typography.title3); Spacer(Modifier.height(4.dp)); Text(errorMsg, color = Color.White, style = MaterialTheme.typography.caption3, maxLines = 3, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp)); Spacer(Modifier.height(8.dp)); Chip(onClick = onFinish, label = { Text("Back") }, colors = ChipDefaults.secondaryChipColors()) }

        if (showCtrls && !isLoading && errorMsg == null && player != null) {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f))) {
                Column(modifier = Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (isPlaylist) Text("${curIdx + 1}/$totalTracks", color = Color.White.copy(0.7f), style = MaterialTheme.typography.caption3)
                    Button(onClick = onPlayPause, modifier = Modifier.size(ButtonDefaults.LargeButtonSize), colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFCC0000))) { Icon(if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.White) }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (upUrl.isNotEmpty() && !isLocal) CompactChip(onClick = onSub, label = { Icon(if (isSub) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null, modifier = Modifier.size(16.dp)) }, colors = if (isSub) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors())
                        if (!isLocal && !isLive && extractedUrl.isNotBlank()) CompactChip(onClick = onDownload, label = { Icon(when (dlState) { DlState.IDLE -> Icons.Rounded.Download; DlState.RUNNING -> Icons.Rounded.Speed; DlState.DONE -> Icons.Rounded.FileDownloadDone; DlState.ERROR -> Icons.Rounded.Warning }, null, modifier = Modifier.size(16.dp)) }, colors = if (dlState == DlState.DONE) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors())
                        if (isPlaylist) CompactChip(onClick = onSkipNext, label = { Icon(Icons.Rounded.SkipNext, null, modifier = Modifier.size(16.dp)) }, colors = ChipDefaults.secondaryChipColors())
                    }
                    if (!isLive) CompactChip(onClick = onCycleSpeed, label = { Text(fmtSpeed(speed), maxLines = 1) }, icon = { Icon(Icons.Rounded.Speed, null, modifier = Modifier.size(14.dp)) }, colors = ChipDefaults.secondaryChipColors())
                }
            }
        }
    }
}

@Composable
private fun InfoPage(title: String, desc: String, comments: List<CommentItem>, focusReq: FocusRequester) {
    val listState = rememberScalingLazyListState()
    Scaffold(positionIndicator = { PositionIndicator(scalingLazyListState = listState) }) {
        ScalingLazyColumn(state = listState, modifier = Modifier.fillMaxSize().rotaryScrollable(behavior = RotaryScrollableDefaults.behavior(listState), focusRequester = focusReq)) {
            item { Text(title, style = MaterialTheme.typography.title3, color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (desc.isNotBlank()) { item { Spacer(Modifier.height(8.dp)) }; item { Text(desc.take(1000), style = MaterialTheme.typography.body2, color = Color.LightGray, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp)) } }
            item { Spacer(Modifier.height(12.dp)) }
            item { Text("\uD83D\uDCAC Comments (${comments.size})", style = MaterialTheme.typography.title3, color = Color.White, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (comments.isEmpty()) { item { Text("No comments available", color = Color.Gray, style = MaterialTheme.typography.body2, modifier = Modifier.padding(horizontal = 12.dp)) } } else {
                items(comments.size) { i -> val c = comments[i]
                    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                        Text(c.author, style = MaterialTheme.typography.caption1, color = Color.Cyan, maxLines = 1)
                        Text(c.text.take(300), style = MaterialTheme.typography.body2, color = Color.White, maxLines = 6, overflow = TextOverflow.Ellipsis)
                        Text("\u2764 ${c.likes}  \u2022  ${c.date}", style = MaterialTheme.typography.caption3, color = Color.Gray)
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}
'@


Write-Host 'Phase 8 Final v7 ready!' -ForegroundColor Cyan

