# generate_phase7.ps1
# TicTube Wear OS - Phase 7: HLS Live Stream Support
# Run from project root: S:\_Vibe_Coding\TicTube\WearApp
#
# Overwrites 3 files:
#   1. app/build.gradle.kts      (adds media3-exoplayer-hls)
#   2. MainScreen.kt             (live badge on search results)
#   3. PlayerScreen.kt           (HLS extraction, LIVE indicator, hide DL/speed)

$ErrorActionPreference = "Stop"
$basePath  = Join-Path $PSScriptRoot "app\src\main\java\com\tictube"
$gradlePath = Join-Path $PSScriptRoot "app"
if (-not (Test-Path $basePath)) { New-Item -ItemType Directory -Force -Path $basePath | Out-Null }
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Emit($dir, $name, $content) {
    $p = Join-Path $dir $name
    [System.IO.File]::WriteAllText($p, $content, $utf8)
    Write-Host "  [OK] $name" -ForegroundColor Green
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host " TicTube Phase 7 - HLS Live Stream Support       " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. app/build.gradle.kts
# ============================================================
Emit $gradlePath "build.gradle.kts" @'
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

# ============================================================
# 2. MainScreen.kt  (adds isLive to VideoItem + LIVE badge)
# ============================================================
Emit $basePath "MainScreen.kt" @'
package com.tictube

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Intent
import android.speech.RecognizerIntent
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
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
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType

// ─── Data ─────────────────────────────────────────────────────

enum class ItemType { VIDEO, PLAYLIST }

data class VideoItem(
    val id: String,
    val title: String,
    val channel: String,
    val durationText: String,
    val thumbnailUrl: String = "",
    val videoUrl: String = "",
    val type: ItemType = ItemType.VIDEO,
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

enum class ScreenMode { FEED, SUBSCRIPTIONS, CHANNEL, HISTORY, DOWNLOADS, PLAYLIST }

// ─── ViewModel ────────────────────────────────────────────────

class MainViewModel(app: Application) : AndroidViewModel(app) {

    companion object { private const val TAG = "MainVM"; private const val MAX = 20 }

    private val subMgr = SubscriptionManager.getInstance(app)
    private val histMgr = HistoryManager.getInstance(app)
    private val dlMgr = DownloadManager.getInstance(app)
    val settingsMgr = SettingsManager.getInstance(app)

    private val _mode = MutableStateFlow(ScreenMode.FEED)
    val mode: StateFlow<ScreenMode> = _mode.asStateFlow()
    private val _ui = MutableStateFlow<UiState>(UiState.Loading)
    val ui: StateFlow<UiState> = _ui.asStateFlow()
    private val _header = MutableStateFlow("")
    val header: StateFlow<String> = _header.asStateFlow()
    private val _quality = MutableStateFlow(settingsMgr.getQuality())
    val quality: StateFlow<SettingsManager.StreamQuality> = _quality.asStateFlow()

    private var lastQuery = "Tech News"
    init { search(lastQuery) }

    fun search(query: String) {
        lastQuery = query; _mode.value = ScreenMode.FEED
        _header.value = "\uD83D\uDD0D $query"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ext = ServiceList.YouTube.getSearchExtractor(query)
                    ext.fetchPage()
                    ext.initialPage.items.mapNotNull { it.toItem() }.take(MAX)
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No results") else UiState.Videos(vids)
            } catch (e: Exception) {
                Log.e(TAG, "search", e); _ui.value = UiState.Error(e.localizedMessage ?: "Search failed")
            }
        }
    }

    fun showSubscriptions() {
        _mode.value = ScreenMode.SUBSCRIPTIONS; _header.value = "\u2764\uFE0F My Channels"
        val s = subMgr.getAll()
        _ui.value = if (s.isEmpty()) UiState.Error("No subscriptions yet.\nSubscribe from the player\nor import a CSV!") else UiState.Channels(s)
    }

    fun showHistory() {
        _mode.value = ScreenMode.HISTORY; _header.value = "\uD83D\uDD52 History"
        val h = histMgr.getAll()
        _ui.value = if (h.isEmpty()) UiState.Error("No history yet.") else UiState.History(h)
    }

    fun showDownloads() {
        _mode.value = ScreenMode.DOWNLOADS; _header.value = "\uD83D\uDCBE Downloads"
        val d = dlMgr.getAll()
        _ui.value = if (d.isEmpty()) UiState.Error("No downloads yet.\nSave videos from the player!") else UiState.Downloads(d)
    }

    fun loadChannel(url: String, name: String) {
        _mode.value = ScreenMode.CHANNEL; _header.value = name
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ce = ServiceList.YouTube.getChannelExtractor(url); ce.fetchPage()
                    val tab = ce.tabs.firstOrNull { t ->
                        t.contentFilters.any { it.contains("videos", true) }
                    } ?: ce.tabs.firstOrNull() ?: throw Exception("No tabs")
                    val te = ServiceList.YouTube.getChannelTabExtractor(tab); te.fetchPage()
                    te.initialPage.items.filterIsInstance<StreamInfoItem>().take(MAX).map { it.toVideoItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No videos") else UiState.Videos(vids)
            } catch (e: Exception) {
                Log.e(TAG, "channel", e); _ui.value = UiState.Error(e.localizedMessage ?: "Failed")
            }
        }
    }

    fun loadPlaylist(url: String) {
        _mode.value = ScreenMode.PLAYLIST; _header.value = "\uD83C\uDFB5 Playlist"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val pe = ServiceList.YouTube.getPlaylistExtractor(url); pe.fetchPage()
                    _header.value = "\uD83C\uDFB5 ${pe.name}"
                    pe.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("Empty playlist") else UiState.Videos(vids)
            } catch (e: Exception) {
                Log.e(TAG, "playlist", e); _ui.value = UiState.Error(e.localizedMessage ?: "Failed")
            }
        }
    }

    fun cycleQuality() { _quality.value = settingsMgr.cycleQuality() }

    fun goBack() { when (_mode.value) {
        ScreenMode.CHANNEL -> showSubscriptions()
        else -> search(lastQuery)
    }}

    fun retry() { when (_mode.value) {
        ScreenMode.FEED, ScreenMode.PLAYLIST -> search(lastQuery)
        ScreenMode.SUBSCRIPTIONS -> showSubscriptions()
        ScreenMode.HISTORY -> showHistory()
        ScreenMode.DOWNLOADS -> showDownloads()
        else -> search(lastQuery)
    }}

    private fun InfoItem.toItem(): VideoItem? = when (this) {
        is StreamInfoItem -> toVideoItem()
        is PlaylistInfoItem -> VideoItem(url, "\uD83C\uDFB5 $name", uploaderName.orEmpty(),
            "${streamCount} videos", thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.PLAYLIST)
        else -> null
    }

    private fun StreamInfoItem.toVideoItem(): VideoItem {
        val live = streamType == StreamType.LIVE_STREAM ||
                   streamType == StreamType.AUDIO_LIVE_STREAM
        return VideoItem(url, name, uploaderName.orEmpty(),
            if (live) "LIVE" else fmtDur(duration),
            thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.VIDEO, isLive = live)
    }
}

private fun fmtDur(s: Long): String {
    if (s < 0) return "LIVE"
    val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec)
}

// ─── Composable ───────────────────────────────────────────────

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val ui by viewModel.ui.collectAsState()
    val mode by viewModel.mode.collectAsState()
    val header by viewModel.header.collectAsState()
    val quality by viewModel.quality.collectAsState()
    val listState = rememberScalingLazyListState()
    val focus = remember { FocusRequester() }
    val ctx = LocalContext.current
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }
    val subMgr = remember { SubscriptionManager.getInstance(ctx.applicationContext) }
    val scope = rememberCoroutineScope()
    val storagePerm = rememberPermissionState(Manifest.permission.READ_EXTERNAL_STORAGE)

    val speechLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { viewModel.search(it) }
        }
    }

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) }
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize()
                .rotaryScrollable(
                    behavior = RotaryScrollableDefaults.behavior(scrollableState = listState),
                    focusRequester = focus
                ).focusRequester(focus).focusable()
        ) {
            // ── Search chip ──
            item {
                Chip(onClick = {
                    try {
                        speechLauncher.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Search YouTube")
                        })
                    } catch (e: Exception) { Log.e("Main", "speech", e) }
                }, label = { Text("\uD83D\uDD0D Search YouTube") },
                    colors = ChipDefaults.primaryChipColors(), modifier = Modifier.fillMaxWidth())
            }

            // ── Navigation chips ──
            if (mode == ScreenMode.FEED) {
                item { Chip(onClick = { viewModel.showSubscriptions() },
                    label = { Text("\u2764\uFE0F Subscriptions") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { Chip(onClick = { viewModel.showHistory() },
                    label = { Text("\uD83D\uDD52 History") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { Chip(onClick = { viewModel.showDownloads() },
                    label = { Text("\uD83D\uDCBE Downloads") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { CompactChip(onClick = { viewModel.cycleQuality() },
                    label = { Text("\u2699\uFE0F Quality: ${quality.label}") },
                    colors = ChipDefaults.secondaryChipColors()) }
            } else {
                item { Chip(onClick = { viewModel.goBack() },
                    label = { Text("\u2190 Back") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
            }

            // ── Import CSV chip (subscriptions view) ──
            if (mode == ScreenMode.SUBSCRIPTIONS) {
                item {
                    Chip(onClick = {
                        if (!storagePerm.status.isGranted) {
                            storagePerm.launchPermissionRequest()
                        }
                        scope.launch {
                            val result = withContext(Dispatchers.IO) {
                                CsvImporter.import(ctx, subMgr)
                            }
                            if (result.isSuccess) {
                                Toast.makeText(ctx,
                                    "\u2705 Imported ${result.count} channels!", Toast.LENGTH_SHORT).show()
                                viewModel.showSubscriptions()
                            } else {
                                Toast.makeText(ctx,
                                    result.error ?: "Import failed", Toast.LENGTH_LONG).show()
                            }
                        }
                    }, label = { Text("\uD83D\uDCE5 Import CSV") },
                        colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
            }

            // ── Header ──
            item { Text(header, style = MaterialTheme.typography.caption1,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }

            // ── Content ──
            when (val s = ui) {
                is UiState.Loading -> item {
                    Box(Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) {
                        Text("Loading\u2026", style = MaterialTheme.typography.body1) }
                }
                is UiState.Error -> item {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(s.message, style = MaterialTheme.typography.body2, textAlign = TextAlign.Center,
                            maxLines = 6, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(4.dp))
                        Chip(onClick = { viewModel.retry() }, label = { Text("Retry") },
                            colors = ChipDefaults.primaryChipColors())
                    }
                }
                is UiState.Channels -> items(s.subs.size) { i ->
                    val sub = s.subs[i]
                    Chip(onClick = { viewModel.loadChannel(sub.url, sub.name) },
                        label = { Text(sub.name, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = { Text("Tap to view videos") },
                        colors = ChipDefaults.gradientBackgroundChipColors(), modifier = Modifier.fillMaxWidth())
                }
                is UiState.History -> items(s.entries.size) { i ->
                    val e = s.entries[i]
                    Chip(onClick = {
                        ctx.startActivity(PlayerActivity.newIntent(ctx, e.url, e.title))
                    }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
                is UiState.Downloads -> items(s.entries.size) { i ->
                    val e = s.entries[i]
                    Chip(onClick = {
                        ctx.startActivity(PlayerActivity.newIntent(ctx, "file://${e.filePath}", e.title))
                    }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = { Text("\u25B6 Play offline") },
                        colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
                is UiState.Videos -> items(s.videos.size) { i ->
                    val v = s.videos[i]
                    Chip(onClick = {
                        if (v.type == ItemType.PLAYLIST) {
                            viewModel.loadPlaylist(v.videoUrl)
                        } else {
                            histMgr.add(v.videoUrl, v.title)
                            val allVids = s.videos.filter { it.type == ItemType.VIDEO }
                            if (mode == ScreenMode.PLAYLIST && allVids.size > 1) {
                                val idx = allVids.indexOf(v).coerceAtLeast(0)
                                ctx.startActivity(PlayerActivity.newPlaylistIntent(ctx,
                                    ArrayList(allVids.map { it.videoUrl }),
                                    ArrayList(allVids.map { it.title }), idx))
                            } else {
                                ctx.startActivity(PlayerActivity.newIntent(ctx, v.videoUrl, v.title))
                            }
                        }
                    }, label = { Text(v.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = {
                            Text(
                                text = if (v.isLive) "\uD83D\uDD34 LIVE \u2022 ${v.channel}"
                                       else "${v.channel} \u2022 ${v.durationText}",
                                maxLines = 1, overflow = TextOverflow.Ellipsis)
                        },
                        icon = {
                            AsyncImage(model = v.thumbnailUrl, contentDescription = null,
                                modifier = Modifier.size(32.dp).clip(RoundedCornerShape(4.dp)),
                                contentScale = ContentScale.Crop)
                        }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
    LaunchedEffect(mode) { listState.scrollToItem(0); focus.requestFocus() }
}
'@

# ============================================================
# 3. PlayerScreen.kt  (HLS live stream support)
# ============================================================
Emit $basePath "PlayerScreen.kt" @'
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
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
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

// ─── Activity ─────────────────────────────────────────────────

class PlayerActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startService(Intent(this, PlaybackService::class.java))
        val url = intent.getStringExtra(EXTRA_VIDEO_URL).orEmpty()
        val title = intent.getStringExtra(EXTRA_VIDEO_TITLE).orEmpty()
        val plUrls = intent.getStringArrayListExtra(EXTRA_PL_URLS) ?: arrayListOf()
        val plTitles = intent.getStringArrayListExtra(EXTRA_PL_TITLES) ?: arrayListOf()
        val startIdx = intent.getIntExtra(EXTRA_START_IDX, 0)
        setContent { MaterialTheme {
            PlayerScreen(url, title, plUrls, plTitles, startIdx)
        }}
    }
    companion object {
        const val EXTRA_VIDEO_URL = "extra_video_url"
        const val EXTRA_VIDEO_TITLE = "extra_video_title"
        const val EXTRA_PL_URLS = "extra_pl_urls"
        const val EXTRA_PL_TITLES = "extra_pl_titles"
        const val EXTRA_START_IDX = "extra_start_idx"

        fun newIntent(ctx: Context, url: String, title: String) =
            Intent(ctx, PlayerActivity::class.java).apply {
                putExtra(EXTRA_VIDEO_URL, url); putExtra(EXTRA_VIDEO_TITLE, title) }

        fun newPlaylistIntent(ctx: Context, urls: ArrayList<String>,
                              titles: ArrayList<String>, startIdx: Int) =
            Intent(ctx, PlayerActivity::class.java).apply {
                putStringArrayListExtra(EXTRA_PL_URLS, urls)
                putStringArrayListExtra(EXTRA_PL_TITLES, titles)
                putExtra(EXTRA_START_IDX, startIdx) }
    }
}

// ─── Data ─────────────────────────────────────────────────────

private data class ExtractionResult(
    val streamUrl: String, val uploaderUrl: String, val uploaderName: String,
    val description: String, val isLive: Boolean)
data class CommentItem(val author: String, val text: String, val likes: Int, val date: String)
enum class DlState { IDLE, RUNNING, DONE, ERROR }

private val SPEEDS = listOf(1.0f, 1.25f, 1.5f, 2.0f)

private fun fmtSpeed(s: Float): String =
    if (s == s.toInt().toFloat()) "${s.toInt()}x" else "${s}x"

// ─── Extraction (HLS-aware) ──────────────────────────────────

private suspend fun extract(ytUrl: String, q: SettingsManager.StreamQuality): ExtractionResult =
    withContext(Dispatchers.IO) {
        val ext = ServiceList.YouTube.getStreamExtractor(ytUrl); ext.fetchPage()
        val uUrl = ext.uploaderUrl.orEmpty()
        val uName = ext.uploaderName.orEmpty()
        val desc = try { ext.description?.content.orEmpty() } catch (_: Exception) { "" }

        val sType = ext.streamType
        val isLive = sType == StreamType.LIVE_STREAM || sType == StreamType.AUDIO_LIVE_STREAM

        var url: String? = null

        // 1. Live streams → prefer HLS manifest
        if (isLive) {
            url = try { ext.hlsUrl } catch (_: Exception) { null }
            Log.i("Extract", "Live HLS url: ${url?.take(80)}")
        }

        // 2. Standard VOD / fallback for live without HLS
        if (url.isNullOrBlank()) {
            val targetRes = when (q) {
                SettingsManager.StreamQuality.AUDIO_ONLY -> 0
                SettingsManager.StreamQuality.Q360P -> 360
                SettingsManager.StreamQuality.Q720P -> 720
            }
            if (targetRes > 0) {
                val muxed = try { ext.videoStreams?.filter { it.isUrl } ?: emptyList() }
                    catch (_: Exception) { emptyList() }
                url = muxed.minByOrNull { s ->
                    val r = s.resolution?.replace(Regex("p.*"), "")?.toIntOrNull() ?: 999
                    kotlin.math.abs(r - targetRes)
                }?.content
            }
            if (url.isNullOrBlank()) {
                val audio = try { ext.audioStreams?.filter { it.isUrl } ?: emptyList() }
                    catch (_: Exception) { emptyList() }
                url = audio.maxByOrNull { it.averageBitrate }?.content
            }
        }

        if (url.isNullOrBlank()) throw IllegalStateException("No playable streams")
        ExtractionResult(url, uUrl, uName, desc, isLive)
    }

private suspend fun loadComments(ytUrl: String): List<CommentItem> = withContext(Dispatchers.IO) {
    try {
        val ce = ServiceList.YouTube.getCommentsExtractor(ytUrl); ce.fetchPage()
        ce.initialPage.items.take(20).map { c ->
            CommentItem(c.uploaderName.orEmpty(),
                c.commentText?.content?.replace(Regex("<[^>]*>"), "").orEmpty(),
                c.likeCount, c.textualUploadDate.orEmpty())
        }
    } catch (e: Exception) { Log.w("Comments", "unavailable", e); emptyList() }
}

// ─── Main Composable ──────────────────────────────────────────

@Composable
fun PlayerScreen(
    videoUrl: String, videoTitle: String,
    plUrls: List<String> = emptyList(), plTitles: List<String> = emptyList(),
    startIdx: Int = 0
) {
    val ctx = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val audioMgr = remember { ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val subMgr = remember { SubscriptionManager.getInstance(ctx.applicationContext) }
    val dlMgr = remember { DownloadManager.getInstance(ctx.applicationContext) }
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }
    val settMgr = remember { SettingsManager.getInstance(ctx.applicationContext) }
    val scope = rememberCoroutineScope()

    val isPlaylist = plUrls.isNotEmpty()
    var curIdx by remember { mutableStateOf(startIdx) }
    val curUrl = if (isPlaylist) plUrls.getOrElse(curIdx) { videoUrl } else videoUrl
    val curTitle = if (isPlaylist) plTitles.getOrElse(curIdx) { videoTitle } else videoTitle
    val isLocal = curUrl.startsWith("file://") || curUrl.startsWith("/")
    val pageCount = if (isLocal) 1 else 2

    var showCtrls by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMsg by remember { mutableStateOf<String?>(null) }
    var player by remember { mutableStateOf(PlaybackService.player) }
    var upUrl by remember { mutableStateOf("") }
    var upName by remember { mutableStateOf("") }
    var isSub by remember { mutableStateOf(false) }
    var desc by remember { mutableStateOf("") }
    var comments by remember { mutableStateOf<List<CommentItem>>(emptyList()) }
    var extractedUrl by remember { mutableStateOf("") }
    var dlState by remember { mutableStateOf(DlState.IDLE) }
    var speed by remember { mutableStateOf(1.0f) }
    var isLive by remember { mutableStateOf(false) }

    val volFocus = remember { FocusRequester() }
    val infoFocus = remember { FocusRequester() }
    val pagerState = rememberPagerState(pageCount = { pageCount })

    // Poll for player
    LaunchedEffect(Unit) { while (player == null) { delay(100); player = PlaybackService.player } }

    // Extract & play
    LaunchedEffect(player, curUrl) {
        val p = player ?: return@LaunchedEffect
        if (curUrl.isEmpty()) return@LaunchedEffect
        isLoading = true; errorMsg = null; dlState = DlState.IDLE
        desc = ""; comments = emptyList(); isLive = false
        try {
            if (isLocal) {
                p.setMediaItem(MediaItem.fromUri(curUrl)); p.prepare(); p.playWhenReady = true
                isLoading = false; showCtrls = true
            } else {
                val result = extract(curUrl, settMgr.getQuality())
                extractedUrl = result.streamUrl
                upUrl = result.uploaderUrl; upName = result.uploaderName
                desc = result.description.replace(Regex("<[^>]*>"), "").trim()
                isSub = subMgr.isSubscribed(result.uploaderUrl)
                isLive = result.isLive
                histMgr.add(curUrl, curTitle)

                // Build MediaItem: HLS needs explicit MIME type
                val mediaItem = if (result.isLive) {
                    MediaItem.Builder()
                        .setUri(result.streamUrl)
                        .setMimeType(MimeTypes.APPLICATION_M3U8)
                        .build()
                } else {
                    MediaItem.fromUri(result.streamUrl)
                }
                p.setMediaItem(mediaItem); p.prepare(); p.playWhenReady = true

                // Preserve speed for VOD; reset to 1x for live
                if (result.isLive) { speed = 1.0f; p.setPlaybackSpeed(1.0f) }
                else { p.setPlaybackSpeed(speed) }

                isLoading = false; showCtrls = true
            }
        } catch (e: Exception) {
            Log.e("Player", "extract", e); isLoading = false
            errorMsg = e.localizedMessage ?: "Could not load video"
        }
    }

    // Load comments lazily
    LaunchedEffect(curUrl) {
        if (isLocal || curUrl.isEmpty()) return@LaunchedEffect
        comments = loadComments(curUrl)
    }

    // Auto-hide controls
    LaunchedEffect(showCtrls) { if (showCtrls) { delay(5000); showCtrls = false } }

    // Player listener
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(p: Boolean) { isPlaying = p }
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && isPlaylist && curIdx < plUrls.size - 1) curIdx++
            }
        }
        player?.addListener(listener)
        onDispose { player?.removeListener(listener) }
    }

    // Lifecycle
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, ev ->
            if (ev == Lifecycle.Event.ON_START) player?.let { isPlaying = it.isPlaying }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    // Focus per page
    LaunchedEffect(pagerState.currentPage) {
        try {
            if (pagerState.currentPage == 0) volFocus.requestFocus() else infoFocus.requestFocus()
        } catch (_: Exception) {}
    }

    // ── UI ────────────────────────────────────────────────────
    Box(Modifier.fillMaxSize().clip(CircleShape).background(Color.Black)) {
        VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
            when (page) {
                0 -> PlayerPage(
                    player = player, isLoading = isLoading, errorMsg = errorMsg,
                    isPlaying = isPlaying, showCtrls = showCtrls,
                    curTitle = curTitle, upUrl = upUrl, upName = upName, isSub = isSub,
                    extractedUrl = extractedUrl, dlState = dlState, speed = speed,
                    isLocal = isLocal, isLive = isLive,
                    isPlaylist = isPlaylist, curIdx = curIdx, totalTracks = plUrls.size,
                    audioMgr = audioMgr, focusReq = volFocus,
                    onTap = { showCtrls = !showCtrls },
                    onPlayPause = { player?.let { if (it.isPlaying) it.pause() else it.play() } },
                    onSub = {
                        if (isSub) subMgr.unsubscribe(upUrl) else subMgr.subscribe(upUrl, upName)
                        isSub = !isSub; showCtrls = true
                    },
                    onDownload = {
                        if (extractedUrl.isNotBlank() && dlState != DlState.RUNNING) {
                            dlState = DlState.RUNNING
                            scope.launch {
                                try { dlMgr.download(extractedUrl, curTitle); dlState = DlState.DONE }
                                catch (e: Exception) { Log.e("DL", "fail", e); dlState = DlState.ERROR }
                            }
                        }
                        showCtrls = true
                    },
                    onCycleSpeed = {
                        val next = SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.size]
                        speed = next
                        player?.setPlaybackSpeed(next)
                        showCtrls = true
                    },
                    onSkipNext = { if (isPlaylist && curIdx < plUrls.size - 1) curIdx++ },
                    onFinish = { (ctx as? ComponentActivity)?.finish() }
                )
                1 -> InfoPage(curTitle, desc, comments, infoFocus)
            }
        }

        // Page indicator
        if (pageCount > 1) {
            Column(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                repeat(pageCount) { idx ->
                    Box(Modifier.size(4.dp).clip(CircleShape)
                        .background(if (idx == pagerState.currentPage) Color.White else Color.Gray.copy(0.4f)))
                }
            }
        }
    }
}

// ─── Page 0: Player ───────────────────────────────────────────

@Composable
private fun PlayerPage(
    player: androidx.media3.exoplayer.ExoPlayer?, isLoading: Boolean, errorMsg: String?,
    isPlaying: Boolean, showCtrls: Boolean, curTitle: String,
    upUrl: String, upName: String, isSub: Boolean,
    extractedUrl: String, dlState: DlState, speed: Float,
    isLocal: Boolean, isLive: Boolean,
    isPlaylist: Boolean, curIdx: Int, totalTracks: Int,
    audioMgr: AudioManager, focusReq: FocusRequester,
    onTap: () -> Unit, onPlayPause: () -> Unit, onSub: () -> Unit,
    onDownload: () -> Unit, onCycleSpeed: () -> Unit,
    onSkipNext: () -> Unit, onFinish: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black)
            .onRotaryScrollEvent { ev ->
                audioMgr.adjustStreamVolume(AudioManager.STREAM_MUSIC,
                    if (ev.verticalScrollPixels > 0f) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                    AudioManager.FLAG_SHOW_UI); true
            }.focusRequester(focusReq).focusable().clickable { onTap() },
        contentAlignment = Alignment.Center
    ) {
        // Video surface
        if (!isLoading && errorMsg == null) {
            player?.let { exo ->
                AndroidView(factory = { c -> PlayerView(c).apply { this.player = exo; useController = false; setKeepScreenOn(true) } },
                    update = { it.player = player }, modifier = Modifier.fillMaxSize())
            }
        }

        // Persistent LIVE badge (always visible when live + playing)
        if (isLive && !isLoading && errorMsg == null) {
            Text("\uD83D\uDD34 LIVE", color = Color(0xFFFF4444),
                style = MaterialTheme.typography.caption2,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp))
        }

        // Loading
        if (isLoading) Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Extracting stream\u2026", color = Color.White, style = MaterialTheme.typography.body1)
            Spacer(Modifier.height(4.dp))
            Text(curTitle, color = Color.Gray, style = MaterialTheme.typography.caption3,
                maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        }
        // Error
        if (errorMsg != null) Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("\u26A0 Error", color = Color(0xFFFF6B6B), style = MaterialTheme.typography.title3)
            Spacer(Modifier.height(4.dp))
            Text(errorMsg, color = Color.White, style = MaterialTheme.typography.caption3,
                maxLines = 3, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            Chip(onClick = onFinish, label = { Text("Back") }, colors = ChipDefaults.secondaryChipColors())
        }
        // Controls overlay
        if (showCtrls && !isLoading && errorMsg == null && player != null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                // Playlist track info
                if (isPlaylist) Text("${curIdx + 1}/$totalTracks",
                    color = Color.White.copy(0.7f), style = MaterialTheme.typography.caption3)
                // Play/Pause
                Button(onClick = onPlayPause, modifier = Modifier.size(ButtonDefaults.LargeButtonSize),
                    colors = ButtonDefaults.buttonColors(backgroundColor = Color.Black.copy(alpha = 0.55f))
                ) { Text(if (isPlaying) "\u23F8" else "\u25B6", style = MaterialTheme.typography.title1, color = Color.White) }

                // Row 1: Subscribe, Download (VOD only), Skip
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (upUrl.isNotEmpty() && !isLocal) {
                        CompactChip(onClick = onSub, label = {
                            Text(if (isSub) "\u2764" else "\u2661", maxLines = 1)
                        }, colors = if (isSub) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors())
                    }
                    // Download: hidden for live streams
                    if (!isLocal && !isLive && extractedUrl.isNotBlank()) {
                        CompactChip(onClick = onDownload, label = {
                            Text(when (dlState) {
                                DlState.IDLE -> "\u2B07"
                                DlState.RUNNING -> "\u231B"
                                DlState.DONE -> "\u2714"
                                DlState.ERROR -> "\u26A0"
                            }, maxLines = 1)
                        }, colors = if (dlState == DlState.DONE) ChipDefaults.primaryChipColors()
                            else ChipDefaults.secondaryChipColors())
                    }
                    if (isPlaylist) {
                        CompactChip(onClick = onSkipNext, label = { Text("\u23ED", maxLines = 1) },
                            colors = ChipDefaults.secondaryChipColors())
                    }
                }

                // Speed control: hidden for live streams
                if (!isLive) {
                    CompactChip(onClick = onCycleSpeed, label = {
                        Text(fmtSpeed(speed), maxLines = 1)
                    }, colors = ChipDefaults.secondaryChipColors())
                }
            }
        }
    }
}

// ─── Page 1: Info ─────────────────────────────────────────────

@Composable
private fun InfoPage(title: String, desc: String, comments: List<CommentItem>, focusReq: FocusRequester) {
    val listState = rememberScalingLazyListState()
    Scaffold(positionIndicator = { PositionIndicator(scalingLazyListState = listState) }) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize()
                .rotaryScrollable(behavior = RotaryScrollableDefaults.behavior(listState), focusRequester = focusReq)
                .focusRequester(focusReq).focusable()
        ) {
            item { Text(title, style = MaterialTheme.typography.title3, color = Color.White,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (desc.isNotBlank()) {
                item { Spacer(Modifier.height(8.dp)) }
                item { Text(desc.take(1000), style = MaterialTheme.typography.body2, color = Color.LightGray,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp)) }
            }
            item { Spacer(Modifier.height(12.dp)) }
            item { Text("\uD83D\uDCAC Comments (${comments.size})", style = MaterialTheme.typography.title3,
                color = Color.White, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (comments.isEmpty()) {
                item { Text("No comments available", color = Color.Gray,
                    style = MaterialTheme.typography.body2, modifier = Modifier.padding(horizontal = 12.dp)) }
            } else {
                items(comments.size) { i ->
                    val c = comments[i]
                    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                        Text(c.author, style = MaterialTheme.typography.caption1, color = Color.Cyan, maxLines = 1)
                        Text(c.text.take(300), style = MaterialTheme.typography.body2, color = Color.White,
                            maxLines = 6, overflow = TextOverflow.Ellipsis)
                        Text("\u2764 ${c.likes}  \u2022  ${c.date}", style = MaterialTheme.typography.caption3,
                            color = Color.Gray)
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}
'@

# ============================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " Phase 7 complete - 3 files generated            " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What changed:" -ForegroundColor White
Write-Host "  build.gradle.kts:" -ForegroundColor Gray
Write-Host "    + media3-exoplayer-hls:1.3.1" -ForegroundColor Gray
Write-Host ""
Write-Host "  MainScreen.kt:" -ForegroundColor Gray
Write-Host "    + isLive field on VideoItem (from StreamType)" -ForegroundColor Gray
Write-Host "    + Red LIVE badge on search result chips" -ForegroundColor Gray
Write-Host ""
Write-Host "  PlayerScreen.kt:" -ForegroundColor Gray
Write-Host "    + extract() checks StreamType.LIVE_STREAM" -ForegroundColor Gray
Write-Host "    + Uses ext.hlsUrl for live HLS manifests" -ForegroundColor Gray
Write-Host "    + MediaItem built with MimeTypes.APPLICATION_M3U8" -ForegroundColor Gray
Write-Host "    + Persistent red LIVE badge at top of player" -ForegroundColor Gray
Write-Host "    + Download button HIDDEN for live streams" -ForegroundColor Gray
Write-Host "    + Speed button HIDDEN for live streams" -ForegroundColor Gray
Write-Host "    + Speed auto-reset to 1x when entering live" -ForegroundColor Gray
Write-Host ""
Write-Host "Next: run '.\build_apk.ps1' to compile." -ForegroundColor Yellow
